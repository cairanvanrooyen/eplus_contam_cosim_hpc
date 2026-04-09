# run-cosim-pool.py

This script runs a set of EnergyPlus-CONTAM co-simulations using a 
multiprocessor pool to run the simulations concurrently. Two required 
arguments to the script include the path to a *Configuration file* and a 
*List file* (see Usage below).  

The *Configuration file* provides paths to the *EnergyPlus* and *readVarsESO* executables as well as a "blank" FMU file. The *List file* defines the locations and names of input files: IDF, EPW, PRJ, VEF, and XML. A blank ContamFMU.fmu file, containing only *contamx3.exe* and *ContamFMU.dll*, must also be provided. The input files will be copied into the FMU by this script prior to launching the co-simulations. 

**NOTE**: The IDF files must match the version of *EnergyPlus* being utilized, and the version of the PRJ files must match that of *ContamX*.
  
Best practice is to run the script using the "-t" option to verify the correct paths are provided by the *Configuration* and *List files*. The script generates a LOG file and RUN directory whose names are based on the current date/time. Review the LOG file and the RUN directory to verify all the files are correctly located and then rerun the script without the "-t" option.  

```
Usage:  
  run-cosim-pool.py [options] arg1 arg2  
  arg1 = config_file_name  
  arg2 = list_file_name  
Parameters:  
  config_file_name = csv text file with paths to the executables to be used.  
  list_file_name   = csv text file with sets of co-sim input files to be run.  
Options:  
  -h, --help         Show this help message and exit.  
  -t                 Test creation of set of files to run without running the  
                     simulations. Then check .log file for status.  
  -w, --workers=NUMWORKERS  
                     Number of CPUs to use: 0=Use (all available-1), or specify
                     a value. When running on AWS-EC2 this option should be used
                     to set desired value.  
```

**Example**  
You ca run the example provided by copying `run-cosim-pool.py` to the *test-fmu-cx-3400* folder. The *config.txt* and *list.txt* files are defined to run the three test cases provided. The *config.txt* file is defined assuming *EnergyPlus* version 9.1 is installed in the default directory. Otherwise, you will need to modify *config.txt* and *list.txt* to utilize the files according to your own directory/file layout.  
  
***Example Config file***
```python
# Path and filename of EnergyPlus executable "energyplus.exe"
ePlus, C:\EnergyPlusV9-1-0\energyplus
# Path and filename of ReadVarsESO bat file "ReadVarsESO.bat"
readVarsESO, C:\EnergyPlusV9-1-0\PostProcess\ReadVarsESO
# Path to blank FMU file containing only ContamFMU.dll and contamx3.exe in binaries\win32\
fileFmu, ..\blank-fmus\ContamFMU-3400.fmu
```
***Example List file***  
```python
# This list file is for inputs files relative to the python script.
#
# For each co-simulation, include a line of input files:
#   filePathIDF, filePathEPW, filePathPRJ, filePathVEF, filePathXML
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
```
