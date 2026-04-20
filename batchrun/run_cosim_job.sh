#!/bin/bash -l
#
# SGE job script for EnergyPlus-CONTAM cosimulation on UCL Myriad
#
# Usage: qsub run_cosim_job.sh
#
# Before submitting:
#   1. Add your input files (IDF, EPW, PRJ, VEF, XML) to this directory
#   2. Edit list.txt with one line per simulation
#   3. Adjust the resource requests below if needed

#$ -N cosim_batch
#$ -l h_rt=02:00:00
#$ -l mem=4G
#$ -l tmpfs=10G
#$ -pe smp 4
# Set working directory to this folder (edit the path to match your setup)
#$ -wd /home/USERNAME/Scratch/cosim/batchrun

# --- Module setup ---
# EnergyPlus 9.4 needs GLIBCXX_3.4.21 which is not in the default gcc-libs/4.9.2
module unload gcc-libs
module load gcc-libs/10.2.0
module load python3/3.11

# --- Environment ---
export LD_LIBRARY_PATH="${HOME}/Scratch/cosim/energyplus/EnergyPlus-9.4.0:${LD_LIBRARY_PATH:-}"

WORK_DIR="${HOME}/Scratch/cosim/batchrun"

# --- Copy inputs to fast local storage ($TMPDIR) ---
echo "Copying input files to TMPDIR..."
cp "${WORK_DIR}/run-cosim-pool.py" "$TMPDIR/"
cp "${WORK_DIR}/config.txt" "$TMPDIR/"
cp "${WORK_DIR}/list.txt" "$TMPDIR/"
cp "${WORK_DIR}/ContamFMU-3400-linux64.fmu" "$TMPDIR/"
cp "${WORK_DIR}"/*.idf "$TMPDIR/" 2>/dev/null
cp "${WORK_DIR}"/*.epw "$TMPDIR/" 2>/dev/null
cp "${WORK_DIR}"/*.prj "$TMPDIR/" 2>/dev/null
cp "${WORK_DIR}"/*.vef "$TMPDIR/" 2>/dev/null
cp "${WORK_DIR}"/*.xml "$TMPDIR/" 2>/dev/null
echo "Done copying to TMPDIR."

# --- Run cosimulation ---
cd "$TMPDIR"
echo "Starting cosimulation with ${NSLOTS} workers..."
python3 run-cosim-pool.py -w ${NSLOTS:-4} config.txt list.txt

# --- Copy results back to Scratch ---
echo "Copying results back to ${WORK_DIR}..."
cp -r "$TMPDIR"/run_* "${WORK_DIR}/" 2>/dev/null
cp "$TMPDIR"/*.log "${WORK_DIR}/" 2>/dev/null
echo "Job complete."
