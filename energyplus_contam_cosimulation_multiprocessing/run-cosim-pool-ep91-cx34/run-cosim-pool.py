#!python3
'''
This script runs a set of EnergyPlus-CONTAM co-simulation simulations using multiprocessor pools.
The files used to run the simulations are specified in a user-provided List file.
Blank ContamFMU.fmu files must not contain contam.prj, contam.vef, or modelDescription.xml files, 
due to the zip module not being able to overwrite existing files within the archive.
NOTE: https://stackoverflow.com/questions/20886565/using-multiprocessing-process-with-a-maximum-number-of-simultaneous-processes

Usage:
$ run-cosim-pool.py [options] arg1 arg2
  arg1 = config_file_name
  arg2 = list_file_name
Parameters:
  config_file_name = csv text file with paths to the executables to be used.
  list_file_name   = csv text file with sets of co-sim input files to be run.
Options:
  -t testrun
     Test creation of set of files to run, but do not run the simulations.
	 Default = False
  -w NUMWORKERS, --workers=NUMWORKERS
     Number of CPUs to use: 0=Use all available-1, or specify a value.
	 Default = 0
===================================================================================================
Example config file:
--------------------
# Path and filename of EnergyPlus executable "energyplus.exe"
# NOTE: 
#   Linux version of config file can assume use of symbolic links "energyplus" and "ReadVarsESO" 
#   in /usr/local/bin for desired version of EnergyPlus. Therefore, no path should be used
#   for ePlus and readVarsESO entries of config file.
ePlus, C:\EnergyPlusV9-1-0\energyplus
# Path and filename of ReadVarsESO bat file "ReadVarsESO.bat"
readVarsESO, C:\EnergyPlusV9-1-0\PostProcess\ReadVarsESO
# Path to blank FMU file containing only ContamFMU.dll and contamx3.exe in binaries\win32\
fileFmu, ..\blank-fmus\ContamFMU-3400.fmu
===================================================================================================
Example List file:
--------------------
# This list file is for inputs files relative to the python script.
#
# For each co-simulation, include a line of input files:
# filePathIDF, filePathEPW, filePathPRJ, filePathVEF, filePathXML
# NOTES: 
# - Comment lines only for entire line.
# - File paths can be absolute OR relative to the Python script from which it is to be read.
#
# Input set 1 - sf-slab-gas
.\sf-slab-gas.idf , ..\epw-files\boston-logan.epw,     .\sf-slab.prj, .\sf-slab-contam.vef, .\sf-slab-modelDescription.xml
# Input set 2 - sf-slab-elecres
.\sf-slab-elecres.idf , ..\epw-files\boston-logan.epw, .\sf-slab.prj, .\sf-slab-contam.vef, .\sf-slab-modelDescription.xml
# Input set 3 - sf-slab-hp
.\sf-slab-hp.idf ,  ..\epw-files\boston-logan.epw,     .\sf-slab.prj, .\sf-slab-contam.vef, .\sf-slab-modelDescription.xml
===================================================================================================
 OUTLINE
--------------------
 - Create a run directory based on the current date and time
 - Read Configuration File
 - Read List File
 - For each line in List File
   + Verify existence of files
   + Omit invalid entries from set of simulations (record issues to log file)
   + Add sim files to lists of files on which to run cosimulation
 - For each cosim to run
   + Make a directory \<1...nSimsToRun> within Run directory
   + Move IDF and FMU files into \<#> directory
   + Add command line to list of cosim commands for multiprocessing pool
   + Run energyplus pool
   + Run ReadVarESO pool
   + Rename CONTAM output files (contam.*) to PRJ base name
   + Rename readVarsESO output files using IDF base name
''' 

import array
import glob
import os
import re
import shutil
import subprocess
import sys
import time
import zipfile
import multiprocessing 
from optparse import OptionParser

NUM_WORKERS = 6
DEBUG = 1


def ePlusWorker(in1, in2):
	print(f"\n===== ePlusWorker =====\n {in1}\t{in2}")
	os.chdir(in2)
	p = subprocess.Popen(in1)
	p.wait()
	# Back to base directory.
	os.chdir("..\\..\\")
	
def readVarsWorker(in1, in2, in3):
	print(f"\n===== readVarsWorker =====\n", in1, "\t", in2, "\t", in3 )
	os.chdir(in2)
	os.rename(in3, "eplusout.eso")
	p = subprocess.Popen(in1);
	p.wait()
	# Back to base directory.
	os.chdir("..\\..\\")


def checkFile(ext, fname):
	checksOut = True
	root, extension = os.path.splitext(fname) 
	if extension != ext:
		checksOut = False
	elif not os.path.exists(fname):
		checksOut = False
	return checksOut


def main():
	# ----- Manage option parser
	parser = OptionParser(usage="%prog [options] arg1 arg2\n\targ1=config_file_name\n\targ2=list_file_name")
	parser.set_defaults(testrun=False)
	parser.add_option("-t", action="store_true", dest="testrun",
						help="Test creation of set of files to run without running the simulations. Then check .log file for status.")
	parser.add_option("-w", "--workers", action="store", dest="numworkers", type="int", default=0,
						help="Number of CPUs to use: 0=Use (all available-1), or specify a value. When running on AWS-EC2 this option should be used to set desired value.")
	(options, args) = parser.parse_args()

	if len(args) != 2:
		parser.error("Need two argurments:\n  arg1 = Configuration file\n  arg2 = List file.\nRun with -h for detailed help.")
		return
	else:
		Config_file_in  = args[0]
		List_file_in = args[1]

	if (not os.path.exists(Config_file_in)):
		print("ERROR: Configuration file not found.")
		return
	elif ( not os.path.exists(List_file_in) ):
		print("ERROR: List file not found.")
		return

	#----- Define constants -----
	#
	fnameContamFMU = "ContamFMU.fmu"               # Name of FMU file for EnergyPlus-CONTAM simulations
	fnameFmuZip    = "ContamFMU.zip"               # Zip file archive name. Wile be renamed fnameContamFMU
	zipDestVef     = "./contam.vef"				   # VEF file name and location within fmu/archive
	zipDestXml     = "./modelDescription.xml"      # XML file name and location within fmu/archive
	
	# PRJ file name and location within fmu/archive
	if sys.platform == "win32":
		zipDestPrj     = "./binaries/win32/contam.prj"
	elif sys.platform == "linux" or sys.platform == "linux2":
		zipDestPrj     = "./binaries/linux64/contam.prj"
	else:
		print("ERROR: Unkown OS.")
		return
	

	#----- Initialize lists -----
	#
	# Each line in List file should contain this number of items.
	nItemsPerLine = 5
	# file lists
	prj_list = []
	idf_list = []
	epw_list = []
	vef_list = []
	xml_list = []

	# ESO file list created from verified IDF file list.
	eso_list = []
	
	# subprocess lists
	dirList = []
	cmdListEPlus = []
	ep_processes = []
	cmdListReadVarsEso = []

	#----- Get CPU counts -----
	#
	ncpu = multiprocessing.cpu_count()
	print("number of cpus = ", ncpu)

	# Process command line options
	TESTRUN = options.testrun
	NUM_WORKERS = options.numworkers
	if( NUM_WORKERS <= 0 ):
		NUM_WORKERS = max(ncpu - 1, 1)

	#----- Create RUN Directory -----
	#
	# Set date and time strings for use in result file names
	now_dt_str = time.strftime("%Y-%m-%d_%H%M%S",time.localtime())
	dirRunName = "run_" + now_dt_str
	dirRun = os.path.join('.', dirRunName)
	os.mkdir(dirRun)
	print("\n=== Created run directory: ", dirRun, "\n")
	
	#----- Create LOG File -----
	#
	log_file_name  = dirRunName + ".log"
	flog = open(log_file_name , "w")

	flog.write("run-cosim-pool.py" + "\n")
	flog.write("TESTRUN = " + str(TESTRUN) + "\n")
	flog.write("Working Directory = " + os.getcwd() + "\n" )
	print("TESTRUN = " + str(TESTRUN))
	print("Working Directory = " + os.getcwd() )
	
	# ----- Read configuration file -----
	#
	Config_ok = 0
	fd_Config  = open(Config_file_in, "r")
	for line_cfg in fd_Config:
		if( not line_cfg.rstrip('\n') ):
			continue
        # Remove white space and provide line items as list.
		line_list_Config = [x1.strip(' \n') for x1 in line_cfg.split(',')]
		if( line_list_Config[0][:1] == '#'):
			# Skip comment lines in CfgFile.
			continue
		if( line_list_Config[0] == "ePlus"):
			ePlus = line_list_Config[1]
			print("EnergyPlus executable = ", ePlus)
			Config_ok += 1
		elif( line_list_Config[0] == "readVarsESO"):
			readVarsESO = line_list_Config[1]
			print("readVarsESO executable = ", readVarsESO)
			Config_ok += 1
		elif( line_list_Config[0] == "fileFmu"):
			fileFmu = line_list_Config[1]
			print("Blank FMU file name = ", fileFmu)
			Config_ok += 1
		else:
			print("Unrecognized value in configuration file.", line_list_Config[0])
		
		# Check to see if all the necessary configuration values have been read.
		if( Config_ok == 3 ):
			fd_Config.close()
			break

	#----- Read List file and populate file lists.
	#
	# Each line should contain:
	# filePathIDF, filePathEPW, filePathPRJ, filePathVEF, filePathXML
	nSimsToRun = 0
	nLinesRead = 0
	fd_List = open(List_file_in, "r")
	for line_in_fdList in fd_List:
		if( not line_in_fdList.rstrip('\n') ):
			continue
        # Remove white space and provide line items as list.
		itemsOnLineOfListfile = [x1.strip(' \n') for x1 in line_in_fdList.split(',')]
		if( itemsOnLineOfListfile[0][:1] == '#'):
			# Skip comment lines in List File.
			continue
		nLinesRead += 1
		if( len(itemsOnLineOfListfile) != nItemsPerLine):
			flog.write("Incorrect number of parameters on line: " + str(itemsOnLineOfListfile) + "\n")
			continue
		# Verify file types have correct extensions.
		bSkipFiles = False
		for file in itemsOnLineOfListfile:
			root, ext = os.path.splitext(file)
			if not checkFile(ext, file):
				# File not found or incorrect type => skip this set of files
				bSkipFiles = True
				flog.write("x File not found or incorrect type: " + file + "  " + str(itemsOnLineOfListfile) + "\n")
				continue
			if( ext == ".idf"):
				esoName = root + "out.eso"
		if bSkipFiles == True:
			continue

		# Add items read to lists.
		idf_list.append(itemsOnLineOfListfile[0])
		epw_list.append(itemsOnLineOfListfile[1])
		prj_list.append(itemsOnLineOfListfile[2])
		vef_list.append(itemsOnLineOfListfile[3])
		xml_list.append(itemsOnLineOfListfile[4])

		# ESO file name based on IDF but without path.
		# The path will be managed by the readVarsEso process worker.
		filename_w_ext = os.path.basename(itemsOnLineOfListfile[0])
		idfPrefix, file_extension = os.path.splitext(filename_w_ext)
		esoName = idfPrefix + "out.eso"
		eso_list.append(esoName)

		flog.write("o " + str(nSimsToRun) + " Simulation to run: " + str(itemsOnLineOfListfile) + "\n")
		nSimsToRun += 1
		# End 

	flog.write("Number of lines read  = " + str(nLinesRead) + "\n")
	flog.write("Number of sims to run = " + str(nSimsToRun) + "\n")
	if( nSimsToRun == 0 ):
		flog.write("*** ERROR: No simulations to run. ***\n")
		print("*** ERROR: No simulations to run. ***")
		sys.exit(0)

	#----- Create a list of command lines to pass to worker() function -----
	#
	iSim = 0
	for i in range(nSimsToRun):
		dirDest = os.path.join(dirRun, str(iSim+1))
		dirDestAbs = os.path.abspath(dirDest)
		os.mkdir(dirDest)
		dirList.append(dirDestAbs)

		# Create FMU file for current PRJ in list from copy of ContamFMU.FMU and 
		#   rename as ContamFMU.zip.
		shutil.copy( fileFmu, fnameFmuZip )
			
		# Copy PRJ, VEF, and XML files to ZIP/FMU file.
		zf = zipfile.ZipFile(fnameFmuZip, mode='a')
		zf.write(prj_list[i], arcname=zipDestPrj)
		zf.write(vef_list[i], arcname=zipDestVef)
		zf.write(xml_list[i], arcname=zipDestXml)
		zf.close()

		# Allow time to close zip archive.
		time.sleep(0.125)

		# Need absolute paths and IDF base file name for EnergyPlus command line.
		idfRun = os.path.abspath(idf_list[i])
		idfFileName_w_ext = os.path.basename(idfRun)
		if( DEBUG > 0 ):
			flog.write("idfFileName_w_ext = " + idfFileName_w_ext + '\n')
		idfRun = os.path.abspath(idfRun)
		idfPrefix, file_extension = os.path.splitext(idfFileName_w_ext)
		epwRun = os.path.abspath(epw_list[i])

		# Move FMU and copy IDF to run subdirectory.
		if( DEBUG > 0 ):
			flog.write("idfRun =" + idfRun + '\n')
		zipDestPrjPath = os.path.join(dirDest, fnameContamFMU)
		shutil.move(fnameFmuZip, zipDestPrjPath)
		shutil.copy(idfRun, dirDest)
		idfCmdLine = os.path.join(dirDestAbs, idfFileName_w_ext)

		# Write EnergyPlus command line to list.
		cmd = [ePlus,'-w',epwRun,'-p',idfPrefix, idfCmdLine]
		cmdListEPlus.append(cmd)
		flog.write(str(iSim+1) + "\t" + str(cmd) + "\n")

		# Increment directory name, iSim.
		iSim = iSim + 1

	#------------------------------------------------------------------------------------------------#
	#-----                                 RUN SIMULATIONS                                      -----#
	#------------------------------------------------------------------------------------------------#
	flog.write(str(dirList))
	
	if (TESTRUN == False):
		flog.write("\n=== Run Co-Simulations ===")
		
		# Use all available cores, otherwise use [option NUM_WORKERS] to specify the number desired.
		pool = multiprocessing.Pool( processes = NUM_WORKERS ) 
		for i in range(len(cmdListEPlus)):
			pool.apply_async(ePlusWorker, args=(cmdListEPlus[i], dirList[i],))
		pool.close()
		pool.join()
	
		#----- Run ReadVarsESO -----
		pool = multiprocessing.Pool( processes = NUM_WORKERS )
		for i in range(len(dirList)):
			pool.apply_async(readVarsWorker, args=(readVarsESO, dirList[i], eso_list[i],))
		pool.close()
		pool.join()
		
		#----- Rename files -----
		for i in range(len(dirList)):
			os.chdir(dirList[i])

			# Rename contam.* files.
			files = glob.glob('contam.*')
			filename_w_ext = os.path.basename(idf_list[i])
			idfPrefix, file_extension = os.path.splitext(filename_w_ext)
			for file in files:
				parts = file.split('.')
				new_name = idfPrefix + '.' + parts[1]
				os.rename(file, new_name)
			
			# Rename ESO files.
			os.rename("eplusout.eso", eso_list[i])
			new_name = idfPrefix + "out.csv"
			os.rename("eplusout.csv", new_name)

			# Back to base directory.
			os.chdir("../../")

	# End if(TESTRUN)			

	flog.close()
	sys.exit(0)
	
		  
#--- End main() ---#

if __name__ == "__main__":
	main()


