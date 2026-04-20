#!/bin/bash
# =============================================================================
# EnergyPlus + CONTAM Cosimulation — Automated Setup for UCL Myriad
# =============================================================================
#
# This script sets up everything needed to run EnergyPlus-CONTAM cosimulations
# on UCL Myriad HPC. Run it once from your Scratch directory.
#
# What it does:
#   1. Clones the git repository
#   2. Downloads EnergyPlus 9.4.0 for Linux
#   3. Extracts EnergyPlus, contamx3, and ContamFMU
#   4. Builds a Linux-compatible blank FMU
#   5. Prepares the batchrun folder (ready to add your files and submit)
#
# Usage:
#   cd ~/Scratch
#   bash setup.sh
#
# After running, your directory will look like:
#   ~/Scratch/cosim/
#   ├── energyplus/EnergyPlus-9.4.0/    (EnergyPlus installation)
#   ├── contamx/                         (CONTAM solver)
#   ├── contam_fmu/                      (ContamFMU shared library)
#   ├── blank-fmus/                      (Linux FMU template)
#   └── batchrun/                        (ready-to-use cosim folder)
#
# =============================================================================

set -e  # Exit on any error

# --- Configuration ---
REPO_URL="https://github.com/cairanvanrooyen/eplus_contam_cosim_hpc.git"
INSTALL_DIR="${HOME}/Scratch/cosim"
EP_VERSION="9.4.0"
EP_HASH="998c4b761e"
EP_TARBALL="EnergyPlus-${EP_VERSION}-${EP_HASH}-Linux-Ubuntu18.04-x86_64.tar.gz"
EP_URL="https://github.com/NREL/EnergyPlus/releases/download/v${EP_VERSION}/${EP_TARBALL}"
EP_DIR_NAME="EnergyPlus-${EP_VERSION}-${EP_HASH}-Linux-Ubuntu18.04-x86_64"

# --- Helper functions ---
print_step() {
    echo ""
    echo "======================================================================"
    echo "  $1"
    echo "======================================================================"
}

print_ok() {
    echo "  ✓ $1"
}

print_err() {
    echo "  ✗ ERROR: $1" >&2
}

# =============================================================================
# Pre-flight checks
# =============================================================================
print_step "Pre-flight checks"

# Check we're on Myriad (or at least a Linux system)
if [[ "$(uname)" != "Linux" ]]; then
    print_err "This script is designed for Linux (UCL Myriad). Detected: $(uname)"
    exit 1
fi
print_ok "Running on Linux"

# Check we have the tools we need
for cmd in git curl tar zip chmod; do
    if ! command -v "$cmd" &> /dev/null; then
        print_err "'$cmd' not found. This should be available on Myriad."
        exit 1
    fi
done
print_ok "Required tools available (git, curl, tar, zip, chmod)"

# Check Scratch directory exists
if [[ ! -d "${HOME}/Scratch" ]]; then
    print_err "Scratch directory not found at ${HOME}/Scratch"
    exit 1
fi
print_ok "Scratch directory exists"

# Warn if cosim directory already exists
if [[ -d "${INSTALL_DIR}" ]]; then
    echo ""
    echo "  WARNING: ${INSTALL_DIR} already exists."
    echo "  This script will exit to avoid overwriting your data."
    echo "  To start fresh, run: rm -rf ${INSTALL_DIR}"
    echo ""
    exit 1
fi

# =============================================================================
# Step 1: Clone the repository
# =============================================================================
print_step "Step 1/5: Cloning repository"

echo "  Cloning ${REPO_URL}..."
git clone "${REPO_URL}" "${INSTALL_DIR}"
print_ok "Repository cloned to ${INSTALL_DIR}"

cd "${INSTALL_DIR}"

# =============================================================================
# Step 2: Download EnergyPlus 9.4.0
# =============================================================================
print_step "Step 2/5: Downloading EnergyPlus ${EP_VERSION}"

mkdir -p energyplus
cd energyplus

if [[ -f "${EP_TARBALL}" ]]; then
    print_ok "EnergyPlus tarball already exists, skipping download"
else
    echo "  Downloading ${EP_TARBALL} (~186 MB)..."
    echo "  URL: ${EP_URL}"
    curl -L -o "${EP_TARBALL}" "${EP_URL}"

    if [[ ! -f "${EP_TARBALL}" ]]; then
        print_err "Download failed. Check your network connection."
        exit 1
    fi
    print_ok "Downloaded EnergyPlus ${EP_VERSION}"
fi

cd "${INSTALL_DIR}"

# =============================================================================
# Step 3: Extract everything
# =============================================================================
print_step "Step 3/5: Extracting software"

# --- EnergyPlus ---
echo "  Extracting EnergyPlus..."
cd energyplus
tar -xzf "${EP_TARBALL}"

# Rename the extracted directory to a simpler name
if [[ -d "${EP_DIR_NAME}" ]]; then
    mv "${EP_DIR_NAME}" "EnergyPlus-${EP_VERSION}"
    print_ok "EnergyPlus extracted to energyplus/EnergyPlus-${EP_VERSION}/"
else
    print_err "Expected directory ${EP_DIR_NAME} not found after extraction."
    echo "  Contents of energyplus/:"
    ls -la
    exit 1
fi

# Make executables runnable
chmod +x "EnergyPlus-${EP_VERSION}/energyplus"
chmod +x "EnergyPlus-${EP_VERSION}/PostProcess/ReadVarsESO"
print_ok "EnergyPlus executables marked as executable"

cd "${INSTALL_DIR}"

# --- CONTAM solver (contamx3) ---
echo "  Extracting contamx3..."
cd contamx
tar -xzf contam-x-3.4.0.0-Linux-64bit.tar.gz
chmod +x contam-x-3.4.0.0-Linux-64bit/contamx3
print_ok "contamx3 extracted and made executable"

cd "${INSTALL_DIR}"

# --- ContamFMU shared library ---
echo "  Extracting ContamFMU..."
cd contam_fmu
tar -xzf ContamFMU-3.4.0-Linux.tar.gz

# Rename the library as required
if [[ -f "ContamFMU-3.4.0-Linux/libContamFMU.so" ]]; then
    cp "ContamFMU-3.4.0-Linux/libContamFMU.so" "ContamFMU.so"
    print_ok "ContamFMU.so ready"
elif [[ -f "ContamFMU-3.4.0-Linux/ContamFMU.so" ]]; then
    cp "ContamFMU-3.4.0-Linux/ContamFMU.so" "ContamFMU.so"
    print_ok "ContamFMU.so ready"
else
    print_err "Could not find ContamFMU shared library after extraction."
    echo "  Contents of contam_fmu/:"
    ls -laR
    exit 1
fi

cd "${INSTALL_DIR}"

# =============================================================================
# Step 4: Build the Linux blank FMU
# =============================================================================
print_step "Step 4/5: Building Linux blank FMU"

mkdir -p blank-fmus
cd blank-fmus

# Create the FMU directory structure
mkdir -p fmu_build/binaries/linux64

# Copy the Linux binaries into the FMU structure
# contamx3 must be named contamx3.exe even on Linux — EnergyPlus expects this exact name
cp "${INSTALL_DIR}/contamx/contam-x-3.4.0.0-Linux-64bit/contamx3" fmu_build/binaries/linux64/contamx3.exe
cp "${INSTALL_DIR}/contam_fmu/ContamFMU.so" fmu_build/binaries/linux64/ContamFMU.so

chmod +x fmu_build/binaries/linux64/contamx3.exe
chmod +x fmu_build/binaries/linux64/ContamFMU.so

# Package into an FMU (which is just a zip file)
cd fmu_build
zip -r ../ContamFMU-3400-linux64.fmu binaries/
cd ..

# Verify the FMU
if [[ -f "ContamFMU-3400-linux64.fmu" ]]; then
    echo "  FMU contents:"
    unzip -l ContamFMU-3400-linux64.fmu
    print_ok "Blank FMU built: blank-fmus/ContamFMU-3400-linux64.fmu"
else
    print_err "Failed to create FMU"
    exit 1
fi

# Clean up build directory
rm -rf fmu_build

cd "${INSTALL_DIR}"

# =============================================================================
# Step 5: Set up the batchrun folder
# =============================================================================
print_step "Step 5/5: Setting up batchrun folder"

# Get the username for path substitution
USERNAME=$(whoami)

# Ensure batchrun directory exists
mkdir -p "${INSTALL_DIR}/batchrun"

# Copy the cosimulation runner script
cp "${INSTALL_DIR}/energyplus_contam_cosimulation_multiprocessing/run-cosim-pool-ep91-cx34/run-cosim-pool.py" \
   "${INSTALL_DIR}/batchrun/run-cosim-pool.py"
print_ok "Copied run-cosim-pool.py"

# Copy the blank FMU
cp "${INSTALL_DIR}/blank-fmus/ContamFMU-3400-linux64.fmu" \
   "${INSTALL_DIR}/batchrun/ContamFMU-3400-linux64.fmu"
print_ok "Copied blank FMU"

# Write config.txt with the actual EnergyPlus paths
cat > "${INSTALL_DIR}/batchrun/config.txt" << CONFIGEOF
# EnergyPlus-CONTAM cosimulation configuration file
# Auto-generated by setup.sh for user: ${USERNAME}
#
# Path to EnergyPlus executable
ePlus, ${INSTALL_DIR}/energyplus/EnergyPlus-${EP_VERSION}/energyplus
# Path to ReadVarsESO post-processor
readVarsESO, ${INSTALL_DIR}/energyplus/EnergyPlus-${EP_VERSION}/PostProcess/ReadVarsESO
# Path to blank Linux FMU (contains ContamFMU.so and contamx3.exe)
fileFmu, ./ContamFMU-3400-linux64.fmu
CONFIGEOF
print_ok "config.txt updated with correct paths"

# Create list.txt template if it doesn't exist
if [[ ! -f "${INSTALL_DIR}/batchrun/list.txt" ]]; then
    cat > "${INSTALL_DIR}/batchrun/list.txt" << 'LISTEOF'
# EnergyPlus-CONTAM cosimulation list file
#
# Each line defines one cosimulation to run. Format (5 comma-separated paths):
#   IDF, EPW, PRJ, VEF, modelDescription.xml
#
# Paths are relative to this directory. Place your input files here or in subdirectories.
#
# Example:
# ./my-building.idf , ./my-weather.epw , ./contam.prj , ./contam.vef , ./modelDescription.xml
LISTEOF
    print_ok "Created list.txt template"
else
    print_ok "list.txt already exists"
fi

# Create or update the SGE job script
cat > "${INSTALL_DIR}/batchrun/run_cosim_job.sh" << JOBEOF
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

#\$ -N cosim_batch
#\$ -l h_rt=02:00:00
#\$ -l mem=4G
#\$ -l tmpfs=10G
#\$ -pe smp 4
# Set working directory to this folder
#\$ -wd /home/${USERNAME}/Scratch/cosim/batchrun

# --- Module setup ---
# EnergyPlus 9.4 needs GLIBCXX_3.4.21 which is not in the default gcc-libs/4.9.2
module unload gcc-libs
module load gcc-libs/10.2.0
module load python3/3.11

# --- Environment ---
export LD_LIBRARY_PATH="${INSTALL_DIR}/energyplus/EnergyPlus-${EP_VERSION}:\${LD_LIBRARY_PATH:-}"

WORK_DIR="${INSTALL_DIR}/batchrun"

# --- Copy inputs to fast local storage (\$TMPDIR) ---
echo "Copying input files to TMPDIR..."
cp "\${WORK_DIR}/run-cosim-pool.py" "\$TMPDIR/"
cp "\${WORK_DIR}/config.txt" "\$TMPDIR/"
cp "\${WORK_DIR}/list.txt" "\$TMPDIR/"
cp "\${WORK_DIR}/ContamFMU-3400-linux64.fmu" "\$TMPDIR/"
cp "\${WORK_DIR}"/*.idf "\$TMPDIR/" 2>/dev/null
cp "\${WORK_DIR}"/*.epw "\$TMPDIR/" 2>/dev/null
cp "\${WORK_DIR}"/*.prj "\$TMPDIR/" 2>/dev/null
cp "\${WORK_DIR}"/*.vef "\$TMPDIR/" 2>/dev/null
cp "\${WORK_DIR}"/*.xml "\$TMPDIR/" 2>/dev/null
echo "Done copying to TMPDIR."

# --- Run cosimulation ---
cd "\$TMPDIR"
echo "Starting cosimulation with \${NSLOTS} workers..."
python3 run-cosim-pool.py -w \${NSLOTS:-4} config.txt list.txt

# --- Copy results back to Scratch ---
echo "Copying results back to \${WORK_DIR}..."
cp -r "\$TMPDIR"/run_* "\${WORK_DIR}/" 2>/dev/null
cp "\$TMPDIR"/*.log "\${WORK_DIR}/" 2>/dev/null
echo "Job complete."
JOBEOF
print_ok "Job script created with username: ${USERNAME}"

# =============================================================================
# Done
# =============================================================================
print_step "Setup complete!"

echo ""
echo "  Installation directory: ${INSTALL_DIR}"
echo "  EnergyPlus version:     ${EP_VERSION}"
echo "  contamx3 version:       3.4.0.0"
echo "  ContamFMU version:      3.4"
echo ""
echo "  Ready-to-use folder:    ${INSTALL_DIR}/batchrun/"
echo ""
echo "  Next steps:"
echo "    1. cd ${INSTALL_DIR}/batchrun"
echo "    2. Copy your input files here (IDF, EPW, PRJ, VEF, XML)"
echo "    3. Edit list.txt with your simulation entries"
echo "    4. Submit: qsub run_cosim_job.sh"
echo ""
echo "  To test on the login node (quick single sim):"
echo "    module unload gcc-libs"
echo "    module load gcc-libs/10.2.0"
echo "    module load python3/3.11"
echo "    export LD_LIBRARY_PATH=\"${INSTALL_DIR}/energyplus/EnergyPlus-${EP_VERSION}:\${LD_LIBRARY_PATH:-}\""
echo "    cd ${INSTALL_DIR}/batchrun"
echo "    python3 run-cosim-pool.py -w 1 config.txt list.txt"
echo ""
