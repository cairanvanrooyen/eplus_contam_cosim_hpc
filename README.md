# EnergyPlus + CONTAM Cosimulation on UCL Myriad HPC

> This guide was written with assistance from Anthropic's Claude (claude-opus-4-6).

Step-by-step guide and scripts for running EnergyPlus and CONTAM cosimulation on [UCL Myriad](https://www.rc.ucl.ac.uk/docs/Clusters/Myriad/) (Linux HPC).

Uses the [NIST CONTAM Parametric Analysis Utilities](https://www.nist.gov/el/beed/nist-multizone-modeling/contam-parametric-analysis-utilities) for batch cosimulation via FMI (Functional Mock-up Interface).

## Version Requirements

> **Critical:** The ContamFMU shared library does **not** work with EnergyPlus 9.5 or later. You must use these specific versions.

| Software | Version | Notes |
|----------|---------|-------|
| EnergyPlus | **9.1.0** | IDF files are v9.1 format |
| CONTAM (contamx3) | **3.4.0.0** | Must use 3.4.0.0 — see note below |
| ContamFMU | **3.4** | FMI cosimulation interface |
| Python | 3.7+ | For the parametric runner script |

> **Why contamx3 3.4.0.0?** The newer contamx3 3.4.0.3 binary was built on Debian 12 and requires glibc 2.34+. UCL Myriad runs RHEL 7.9 with glibc 2.17, so contamx3 3.4.0.3 will fail with `GLIBC_2.28 not found` errors. The older 3.4.0.0 binary works with glibc 2.17. Download it from: https://www.nist.gov/document/contam-x-3400-linux-64bittargz

## Background

The bundled `ContamFMU-3400.fmu` from NIST only contains **win32** binaries. To run on Linux (Myriad), you need to:

1. Extract the Linux `contamx3` solver and `ContamFMU.so` shared library (included in this repo)
2. Package them into a new FMU with `linux64` binaries
3. Extract EnergyPlus 9.1.0 in user space (no `sudo` on HPC)

Most required tarballs are included in this repo. However, the EnergyPlus 9.1.0 Linux tarball (`EnergyPlus-9.1.0-08d2e308bb-Linux-x86_64.tar.gz`) exceeds GitHub's file size limit and must be downloaded separately. Download it from the [EnergyPlus 9.1.0 release page](https://github.com/NREL/EnergyPlus/releases/tag/v9.1.0) and place it in the `energyplus/` directory before proceeding with setup.

## Setup on Myriad

### 1. SSH into Myriad and clone this repo

Log into Myriad and clone this repository into your Scratch directory. Scratch is the writable filesystem accessible from compute nodes.

```bash
ssh <YOUR_UCL_ID>@myriad.rc.ucl.ac.uk
cd ~/Scratch
git clone <your-repo-url> cosim
cd cosim
```

### 2. Extract EnergyPlus 9.1.0

EnergyPlus is the building energy simulation engine. Extract the Linux tarball included in this repo and make the executables runnable.

```bash
cd ~/Scratch/cosim/energyplus

tar -xzf EnergyPlus-9.1.0-08d2e308bb-Linux-x86_64.tar.gz
mv EnergyPlus-9.1.0-08d2e308bb-Linux-x86_64 EnergyPlus-9.1.0

chmod +x EnergyPlus-9.1.0/energyplus
chmod +x EnergyPlus-9.1.0/PostProcess/ReadVarsESO
```

### 3. Extract CONTAM 3.4 Linux binaries

CONTAM is the multizone airflow and contaminant transport solver. Two components are needed: the solver itself (`contamx3`) and the shared library (`ContamFMU.so`) that enables cosimulation with EnergyPlus via the FMI standard.

**a) contamx3 solver:**

```bash
cd ~/Scratch/cosim/contamx

tar -xzf contam-x-3.4.0.0-Linux-64bit.tar.gz
chmod +x contam-x-3.4.0.0-Linux-64bit/contamx3
```

**b) ContamFMU shared library:**

The shared library is what EnergyPlus calls during cosimulation to exchange data with CONTAM at each timestep. It must be named `ContamFMU.so` (NIST distributes it as `libContamFMU.so`).

```bash
cd ~/Scratch/cosim/contam_fmu

tar -xzf ContamFMU-3.4.0-Linux.tar.gz
mv ContamFMU-3.4.0-Linux/libContamFMU.so ./ContamFMU.so
chmod +x ContamFMU.so
```

### 4. Build a Linux-compatible blank FMU

EnergyPlus loads CONTAM through a Functional Mock-up Unit (FMU) — a zip file containing the solver binary and shared library in a specific directory structure. The NIST-provided FMU only has Windows binaries, so we need to build a new one with the Linux binaries from steps 3a and 3b.

```bash
cd ~/Scratch/cosim
mkdir -p blank-fmus/_build/binaries/linux64

# IMPORTANT: contamx3 must be named contamx3.exe inside the FMU —
# EnergyPlus looks for the .exe suffix even on Linux
cp contamx/contam-x-3.4.0.0-Linux-64bit/contamx3  blank-fmus/_build/binaries/linux64/contamx3.exe
cp contam_fmu/ContamFMU.so                          blank-fmus/_build/binaries/linux64/ContamFMU.so

cd blank-fmus/_build
zip -r ../ContamFMU-3400-linux64.fmu binaries/
cd ..
rm -rf _build

# Verify the FMU contains the correct files
unzip -l ContamFMU-3400-linux64.fmu
# Should show:
#   binaries/linux64/ContamFMU.so
#   binaries/linux64/contamx3.exe
```

### 5. Set up the test case

Copy all the files needed to run a cosimulation into a single self-contained `test/` folder. This includes the EnergyPlus building models (IDF), CONTAM airflow model (PRJ), the variable exchange file (VEF) that defines what data is passed between the two programs, the FMI model description (XML), a weather file (EPW), the blank FMU from step 4, and the Python runner script.

```bash
cd ~/Scratch/cosim

COSIM_MP="energyplus_contam_cosimulation_multiprocessing/run-cosim-pool-ep91-cx34"

mkdir -p test

cp "$COSIM_MP/test-fmu-cx-3400/"*.idf  test/
cp "$COSIM_MP/test-fmu-cx-3400/"*.prj  test/
cp "$COSIM_MP/test-fmu-cx-3400/"*.vef  test/
cp "$COSIM_MP/test-fmu-cx-3400/"*.xml  test/
cp "$COSIM_MP/epw-files/boston-logan.epw" test/
cp blank-fmus/ContamFMU-3400-linux64.fmu test/
cp "$COSIM_MP/run-cosim-pool.py" test/
```

### 6. Create config file

The config file tells the Python script where to find the EnergyPlus executable, the post-processing tool (ReadVarsESO, which converts EnergyPlus binary output to CSV), and the blank FMU template.

```bash
nano ~/Scratch/cosim/test/config.txt
```

Paste the following (replace `<YOUR_UCL_ID>` with your username, e.g. `ucbqca0`):

```
ePlus, /home/<YOUR_UCL_ID>/Scratch/cosim/energyplus/EnergyPlus-9.1.0/energyplus
readVarsESO, /home/<YOUR_UCL_ID>/Scratch/cosim/energyplus/EnergyPlus-9.1.0/PostProcess/ReadVarsESO
fileFmu, ./ContamFMU-3400-linux64.fmu
```

Save with `Ctrl+O`, `Enter`, `Ctrl+X`.

### 7. Create list file

The list file defines each cosimulation to run. Each line specifies five input files: the EnergyPlus model (IDF), weather data (EPW), CONTAM project (PRJ), variable exchange file (VEF), and the FMI model description (XML). The test case includes three variants of the same single-family house with different heating systems.

```bash
nano ~/Scratch/cosim/test/list.txt
```

Paste the following:

```
./sf-slab-gas.idf, ./boston-logan.epw, ./sf-slab.prj, ./sf-slab-contam.vef, ./sf-slab-modelDescription.xml
./sf-slab-elecres.idf, ./boston-logan.epw, ./sf-slab.prj, ./sf-slab-contam.vef, ./sf-slab-modelDescription.xml
./sf-slab-hp.idf, ./boston-logan.epw, ./sf-slab.prj, ./sf-slab-contam.vef, ./sf-slab-modelDescription.xml
```

Save with `Ctrl+O`, `Enter`, `Ctrl+X`.

### 8. Test run (login node - quick validation)

Before submitting a real job, do a dry run with the `-t` flag. This validates that all input files can be found and the config is correct, without actually running any simulations.

```bash
module unload gcc-libs
module load gcc-libs/10.2.0
module load python3/3.11

cd ~/Scratch/cosim/test
python3 run-cosim-pool.py -t config.txt list.txt
```

Check the generated `.log` file. It should show 3 simulations found with no errors.

### 9. Submit as a batch job

Create a job script that tells the Myriad scheduler (SGE) how many resources you need and what to run. The script requests 4 cores so the Python multiprocessing pool can run simulations in parallel.

```bash
nano ~/Scratch/cosim/test/run_cosim_job.sh
```

Paste the following (replace `<YOUR_UCL_ID>` with your username, e.g. `ucbqca0`):

```
#!/bin/bash -l

#$ -N cosim_test
#$ -l h_rt=2:00:00
#$ -l mem=4G
#$ -l tmpfs=15G
#$ -pe smp 4
#$ -wd /home/<YOUR_UCL_ID>/Scratch/cosim/test

# Unload default gcc-libs (4.9.2) and load a newer version —
# EnergyPlus 9.1 needs GLIBCXX_3.4.21+ which gcc-libs/4.9.2 doesn't provide
module unload gcc-libs
module load gcc-libs/10.2.0
module load python3/3.11

export LD_LIBRARY_PATH="${HOME}/Scratch/cosim/energyplus/EnergyPlus-9.1.0:${LD_LIBRARY_PATH:-}"

cd ~/Scratch/cosim/test
python3 run-cosim-pool.py -w ${NSLOTS:-4} config.txt list.txt
```

Save with `Ctrl+O`, `Enter`, `Ctrl+X`. Then submit:

```bash
qsub run_cosim_job.sh
```

### 10. Monitor and check results

SGE writes stdout and stderr to files in the working directory once the job completes. The cosimulation script also creates a timestamped `run_*/` directory containing numbered subdirectories (one per simulation), each with the EnergyPlus and CONTAM output files.

```bash
# Check job status
qstat

# Once complete, check stdout/stderr
cat cosim_test.o*
cat cosim_test.e*

# Check the cosimulation log
cat run_*.log

# Check output files in each simulation subdirectory
ls run_*/1/
ls run_*/2/
ls run_*/3/
```

Each subdirectory should contain CSV result files with the simulation outputs.

## Running Your Own Cosimulations

Once the test case works, you can run cosimulations with your own building models. This section explains the typical workflow and how to add your project to the runner.

### Workflow overview

The standard workflow for developing a CONTAM model into an EnergyPlus cosimulation is:

1. **Build and validate the CONTAM model** — Ensure the geometry is well defined in ContamW, along with zones, flow paths, pollutants, profiles, and air handling systems. Save as `your-building.prj`.

2. **Create a base EnergyPlus IDF with constructions** — Prepare an IDF file containing `Material` and `Construction` objects for the surfaces in your building (walls, floors, ceilings, windows). This is used as input to the 3D Exporter in the next step.

3. **Export using CONTAM 3D Exporter** — Run CONTAM3DExport, select the PRJ and the base constructions IDF, assign constructions to surface categories, choose the HVAC air loop option (Fan Only, Unitary Heat Cool, or Air to Air Heat Pump), and select the "Building Coupled with CONTAM" export option. This produces:
   - A **coupled IDF** with geometry, air loops, exhaust fans, and FMU-related objects
   - A **ContamFMU.fmu** containing the modelDescription.xml, contam.prj, contam.vef, ContamFMU library, and contamx3 solver

4. **Edit the exported IDF as required** — Modify HVAC settings, internal gains, schedules, setpoints, or any other EnergyPlus objects. The IDF must remain in EnergyPlus **9.1** format for compatibility with ContamFMU.

5. **Parametric preparation** — If running a parametric study, write a preparation script to generate IDF/EPW variants and `list.txt` (see [Parametric analysis](#parametric-analysis) below).

6. **Cosimulation runs and results processing** — Run on Myriad using the batch runner or array jobs, then process the output CSV/ESO files.

### Guidelines for building CONTAM models for cosimulation

When creating a CONTAM project in ContamW that will be coupled with EnergyPlus via the 3D Exporter, follow these rules. Getting these right avoids problems at export and runtime.

#### Geometry

Use ContamW's **pseudo-geometry mode** so that CONTAM3DExport can generate the correct 3D geometry for the EnergyPlus model. Each CONTAM zone maps to one EnergyPlus thermal zone.

#### Airflow paths

Airflow paths are grouped by the exporter to form infiltration rates (external paths) and inter-zone mixing rates (internal paths) in EnergyPlus. Multiple paths between the same pair of zones are combined into a single connection.

#### Windows

To create a window for thermal modelling, define an airflow path using a **two-way flow element whose name contains "wind"** (not case-sensitive). Place the path icon on the wall where you want the window centre. Set the bottom elevation via the path's Reference Elevation, and the height and width via the flow element properties. Make sure windows are fully contained within their wall and do not overlap. If you don't want airflow through the window during cosimulation, set the path multiplier to zero.

#### Air handling systems

An EnergyPlus air loop is created for each "normal" simple AHS in the CONTAM model. Each zone served by an air loop must have both supply and return terminals, and a zone can only be served by **one normal AHS** (i.e. one air loop). However, a zone can additionally be served by one exhaust-only and one HRV system.

AHS naming conventions control what the exporter creates:

| AHS name contains | System created in EnergyPlus |
|---|---|
| *(normal name)* | Full `AirLoopHVAC` with supply/return |
| **"exh"** | `Fan:ZoneExhaust` (no air loop) — should have no supply terminals |
| **"hrv"** | `ZoneHVAC:EnergyRecoveryVentilator` (no air loop) |

The exporter also offers three air loop options for normal AHS: Fan Only (fan with no heating/cooling), Unitary Heat Cool (`AirLoopHVAC:UnitaryHeatCool`), or Air to Air Heat Pump (`UnitaryHeatPump:AirToAir`).

#### Ducts

Ducts are **not supported** in the EnergyPlus coupling. The exporter does not check for this, so avoid using duct elements in models intended for cosimulation.

#### Controls (advanced)

Named control nodes can pass arbitrary data between CONTAM and EnergyPlus:

- **Constant (or Set) type controls** with a name receive input signals from EnergyPlus → creates `ExternalInterface:FunctionalMockupUnitImport:From:Variable` objects
- **Split (or Pass) type controls** with a name send output signals to EnergyPlus → creates `ExternalInterface:FunctionalMockupUnitImport:To:Schedule` objects

This enables things like demand-controlled ventilation based on contaminant levels or coordination of control strategies between the two programs. After adding or modifying controls, you must run a building check in CONTAM (Simulation → Run Building Check) to sequence the controls, then save the project.

### Post-export checklist

The IDF generated by CONTAM3DExport will run as exported, but it will not perform realistically without further editing. After export, review and add:

- **Internal gains** — occupancy, lighting, equipment (not created by the exporter)
- **Ground coupling** — ground temperature profiles and boundary conditions
- **HVAC sizing and setpoints** — the exporter creates the air loop structure but you will likely need to set the controlling zone/thermostat location, adjust coil and fan sizes, and define thermostat setpoints
- **Water-related items** — domestic hot water, plant loops if needed
- **Schedules** — occupancy, lighting, equipment, and thermostat schedules

Additionally, ensure the following before running:

- **Timestep and simulation dates must match** between the PRJ file (inside the FMU) and the IDF. If they differ, the cosimulation will produce incorrect results or fail.
- **The IDF and FMU must be in the same directory** at runtime. The `run-cosim-pool.py` script handles this automatically.
- **Restart file (optional)** — you can set the restart flag in the PRJ to use initial airflows and temperatures from a prior CONTAM run. Edit the PRJ's restart line to `1 Jan01 24:00:00` (with the date matching your simulation start). This can help with initial conditions but may be undesirable if you have contaminant sinks or filters that should start unloaded.
- **VEF/XML variable ordering** — the order of variables in the VEF file must match the `valueReference` numbers in the modelDescription.xml. The variable names do not need to match, but the ordering is critical. The 3D Exporter handles this automatically, but if you manually edit either file, take care to keep them in sync.

### Input files produced by this workflow

| File | Produced by | Purpose |
|------|-------------|---------|
| **IDF** | CONTAM 3D Exporter (step 3), then edited (step 4) | Building geometry, materials, HVAC, schedules, and `ExternalInterface:FunctionalMockupUnitImport` objects for data exchange with CONTAM |
| **FMU** | CONTAM 3D Exporter (step 3) | Contains contamx3 solver, ContamFMU library, PRJ, VEF, and modelDescription.xml — everything needed for the CONTAM side of the cosimulation |
| **EPW** | [EnergyPlus weather site](https://energyplus.net/weather) | Hourly weather data for the simulation location |

Note that the PRJ, VEF, and modelDescription.xml are all packed inside the FMU by the 3D Exporter. You do not need to manage these separately unless you need to modify them after export.

### How the cosimulation data exchange works

EnergyPlus and CONTAM run simultaneously and exchange data at each timestep via the FMI standard:

1. **EnergyPlus → CONTAM (inputs):** Zone air temperatures, humidity ratios, AHS supply/return flow rates, outdoor weather. Defined as `causality="input"` in the modelDescription.xml and as `I` lines in the VEF.

2. **CONTAM → EnergyPlus (outputs):** Infiltration rates, inter-zone mixing flow rates. Defined as `causality="output"` in the modelDescription.xml and as `O` lines in the VEF.

3. The **IDF** must contain `ExternalInterface:FunctionalMockupUnitImport` objects that reference the same variable names as the XML. The 3D Exporter creates these automatically.

### Rebuilding the FMU for Linux

The FMU produced by CONTAM 3D Exporter contains Windows binaries (ContamFMU.dll and contamx3.exe). To run on Myriad, you need to replace these with Linux equivalents. This is what steps 3–4 of the setup guide accomplish — building a blank FMU with `ContamFMU.so` and the Linux `contamx3.exe`. The `run-cosim-pool.py` script then repacks the PRJ, VEF, and XML from your exported FMU into the Linux blank FMU at runtime.

If you need to extract the VEF and XML from your exported FMU to use with the runner's `list.txt` format:

```bash
# Unzip the FMU (it's just a zip file)
unzip ContamFMU.fmu -d fmu_contents/

# Your files are inside:
# fmu_contents/modelDescription.xml
# fmu_contents/binaries/win32/contam.vef   (or similar path)
# fmu_contents/binaries/win32/contam.prj
```

### Adding your project to the runner

**1. Copy your input files into the test directory:**

```bash
cd ~/Scratch/cosim/test
cp /path/to/your-building.idf .
cp /path/to/your-building.prj .
cp /path/to/your-building-contam.vef .
cp /path/to/your-building-modelDescription.xml .
cp /path/to/your-weather.epw .
```

**2. Add a line to `list.txt`:**

```bash
nano ~/Scratch/cosim/test/list.txt
```

Add a new line for your simulation. Each line has five comma-separated paths (IDF, EPW, PRJ, VEF, XML):

```
./your-building.idf, ./your-weather.epw, ./your-building.prj, ./your-building-contam.vef, ./your-building-modelDescription.xml
```

You can add multiple lines to run multiple simulations in parallel (e.g. different HVAC variants or different weather files for the same building).

**3. Test first:**

```bash
module unload gcc-libs
module load gcc-libs/10.2.0
module load python3/3.11

python3 run-cosim-pool.py -t config.txt list.txt
```

Check the generated log file — it should list your simulation with no errors. This validates that all file paths are correct and the files have the expected extensions.

**4. Run:**

```bash
qsub run_cosim_job.sh
```

Or for an interactive test on the login node (single simulation only — be brief):

```bash
export LD_LIBRARY_PATH="${HOME}/Scratch/cosim/energyplus/EnergyPlus-9.1.0:${LD_LIBRARY_PATH:-}"
python3 run-cosim-pool.py -w 1 config.txt list.txt
```

### Understanding the output

Each simulation creates a numbered subdirectory inside a timestamped `run_*/` folder. For example, if your simulation is the 4th line in `list.txt`, its results are in `run_*/4/`. Inside you'll find:

| File | Description |
|------|-------------|
| `your-buildingout.csv` | EnergyPlus output variables as CSV (timestep-level data) |
| `your-buildingout.eso` | EnergyPlus raw binary output |
| `your-building.ach` | CONTAM air change rates |
| `your-building.lnk` | CONTAM link (flow path) results |
| `your-building.lfr` | CONTAM link flow results |
| `your-building.nfr` | CONTAM node flow results |
| `your-building.sim` | CONTAM simulation summary |
| `ContamFMU.fmu` | The FMU used for this run (contains your PRJ, VEF, XML packed in) |

The CSV file is typically what you want for analysis — it contains the EnergyPlus output variables at each reporting timestep.

### Tips

- The **config.txt** does not need to change between projects — it only points to the EnergyPlus executables and the blank FMU, which are the same for all simulations.
- You can mix different buildings in the same `list.txt`. Each gets its own numbered subdirectory.
- The `-w` flag controls how many simulations run in parallel. On Myriad, set it to match your `#$ -pe smp N` value or use `${NSLOTS}` as in the job script.
- If a simulation fails, check `run_*/<N>/eplusout.err` for EnergyPlus errors and the job's stderr file for CONTAM errors.
- If you manually edit the IDF or VEF/XML after using the 3D Exporter, variable name mismatches between the IDF and XML are a common source of errors — the names must match exactly (case-sensitive). When using the 3D Exporter without manual edits, these are generated consistently.

### Parametric analysis

For parametric studies — running the same building across multiple weather files, or varying IDF parameters like insulation thickness or infiltration rates — the recommended approach is to write a separate preparation script that generates the input files and `list.txt`, then run the cosimulation batch as a second step. This keeps the parametric logic cleanly separated from the simulation runner.

#### What can be varied

| What to vary | Which file changes | Approach |
|---|---|---|
| **Weather / location** | EPW only | Point each list.txt line at a different EPW file. No IDF or PRJ changes needed. |
| **HVAC system type** | IDF only | Create separate IDF variants (as in the test case: gas, elecres, hp). PRJ, VEF, and XML stay the same if the zone layout is unchanged. |
| **IDF parameters** (insulation, glazing, setpoints, schedules, etc.) | IDF only | Script modifies IDF text and writes out variants. PRJ, VEF, and XML stay the same. |
| **Airflow network** (leakage, vent openings, AHS sizing) | PRJ only | Modify the PRJ file. VEF and XML stay the same as long as the zone and AHS names don't change. |
| **Zone layout changes** (adding/removing zones) | PRJ + VEF + XML + IDF | All four files must be regenerated consistently. This usually requires going back to the CONTAM GUI. |

#### Example 1: Same building, multiple weather files

The simplest parametric case. You only need different EPW files — all other inputs are shared:

```
project/
├── prepare-weather-study.py
├── inputs/
│   ├── office.idf
│   ├── office.prj
│   ├── office-contam.vef
│   ├── office-modelDescription.xml
│   └── epw/
│       ├── london.epw
│       ├── manchester.epw
│       └── edinburgh.epw
└── (list.txt generated by script)
```

**`prepare-weather-study.py`:**

```python
#!/usr/bin/env python3
"""Generate list.txt for a multi-weather cosimulation study."""

import os

# Base input files (same for all runs)
idf = "./inputs/office.idf"
prj = "./inputs/office.prj"
vef = "./inputs/office-contam.vef"
xml = "./inputs/office-modelDescription.xml"

# Weather files to sweep
epw_dir = "./inputs/epw"
epw_files = sorted(f for f in os.listdir(epw_dir) if f.endswith(".epw"))

# Generate list.txt
with open("list.txt", "w") as f:
    f.write("# Auto-generated weather parametric study\n")
    for epw in epw_files:
        epw_path = os.path.join(epw_dir, epw)
        f.write(f"{idf}, {epw_path}, {prj}, {vef}, {xml}\n")

print(f"Generated list.txt with {len(epw_files)} simulations")
```

Run on Myriad:

```bash
cd ~/Scratch/cosim/test
python3 prepare-weather-study.py
python3 run-cosim-pool.py -t config.txt list.txt   # test
qsub run_cosim_job.sh                               # run
```

#### Example 2: Varying IDF parameters (e.g. insulation thickness)

For IDF-level parametric changes, the script reads a base IDF, modifies the relevant fields, and writes out variant IDFs. EnergyPlus IDF files are plain text, so string replacement works well for simple parameter sweeps.

```python
#!/usr/bin/env python3
"""Generate IDF variants with different wall insulation thicknesses."""

import os

base_idf = "inputs/office.idf"
prj = "./inputs/office.prj"
vef = "./inputs/office-contam.vef"
xml = "./inputs/office-modelDescription.xml"
epw = "./inputs/epw/london.epw"
output_dir = "./inputs/variants"

# Parameter sweep: insulation thickness in metres
thicknesses = [0.05, 0.10, 0.15, 0.20, 0.25]

# The string to find and replace in the IDF.
# Identify this by looking at the Material object for your insulation layer.
# For example, if the base IDF has:
#   Material,
#     WallInsulation,   !- Name
#     MediumRough,      !- Roughness
#     0.1,              !- Thickness {m}
# You would replace the thickness value.
search_str = "0.1,              !- Thickness {m}"

os.makedirs(output_dir, exist_ok=True)

with open(base_idf, "r") as f:
    base_content = f.read()

with open("list.txt", "w") as flist:
    flist.write("# Auto-generated insulation parametric study\n")
    for t in thicknesses:
        replace_str = f"{t},              !- Thickness {{m}}"
        variant_content = base_content.replace(search_str, replace_str, 1)

        variant_name = f"office-insul-{int(t*1000)}mm.idf"
        variant_path = os.path.join(output_dir, variant_name)

        with open(variant_path, "w") as fout:
            fout.write(variant_content)

        flist.write(f"{variant_path}, {epw}, {prj}, {vef}, {xml}\n")

    print(f"Generated {len(thicknesses)} IDF variants and list.txt")
```

#### Example 3: Combined sweep (multiple parameters × multiple locations)

For a full factorial design — e.g. 3 HVAC types × 5 cities — the script generates all combinations:

```python
#!/usr/bin/env python3
"""Generate a full factorial cosimulation study."""

import os
from itertools import product

# HVAC variants (separate IDF files, already created)
hvac_variants = {
    "gas":     "./inputs/office-gas.idf",
    "elecres": "./inputs/office-elecres.idf",
    "hp":      "./inputs/office-hp.idf",
}

# Weather files
weather_files = {
    "london":     "./inputs/epw/london.epw",
    "manchester": "./inputs/epw/manchester.epw",
    "edinburgh":  "./inputs/epw/edinburgh.epw",
    "cardiff":    "./inputs/epw/cardiff.epw",
    "belfast":    "./inputs/epw/belfast.epw",
}

# Shared CONTAM files (same zone layout across HVAC variants)
prj = "./inputs/office.prj"
vef = "./inputs/office-contam.vef"
xml = "./inputs/office-modelDescription.xml"

with open("list.txt", "w") as f:
    f.write("# Full factorial: HVAC type x weather location\n")
    n = 0
    for (hvac_name, idf), (city, epw) in product(
        hvac_variants.items(), weather_files.items()
    ):
        f.write(f"# {hvac_name} / {city}\n")
        f.write(f"{idf}, {epw}, {prj}, {vef}, {xml}\n")
        n += 1

print(f"Generated list.txt with {n} simulations "
      f"({len(hvac_variants)} HVAC x {len(weather_files)} cities)")
```

This generates 15 simulations. Request enough cores in your job script:

```bash
#$ -pe smp 15
```

And the runner will execute them all in parallel.

#### Keeping things organised

For larger studies, a recommended directory structure:

```
~/Scratch/cosim/
├── test/                          # Validated test case (keep as reference)
├── studies/
│   └── insulation-sweep/          # One folder per study
│       ├── prepare.py             # Generates variants and list.txt
│       ├── config.txt             # Same as test/ (copy or symlink)
│       ├── run-cosim-pool.py      # Same as test/ (copy or symlink)
│       ├── ContamFMU-3400-linux64.fmu   # Same blank FMU
│       ├── run_study.sh           # Job script
│       ├── inputs/                # Base files and variants
│       ├── list.txt               # Generated by prepare.py
│       └── run_*/                 # Output (created at runtime)
```

This way each study is self-contained, reproducible, and doesn't interfere with your test case or other studies.

#### Job script for parametric studies

If you have many simulations (e.g. 50+), you may want more cores and wall time:

```bash
nano ~/Scratch/cosim/studies/my-study/run_study.sh
```

```
#!/bin/bash -l

#$ -N cosim_study
#$ -l h_rt=6:00:00
#$ -l mem=4G
#$ -l tmpfs=30G
#$ -pe smp 16
#$ -wd /home/<YOUR_UCL_ID>/Scratch/cosim/studies/my-study

module unload gcc-libs
module load gcc-libs/10.2.0
module load python3/3.11

export LD_LIBRARY_PATH="${HOME}/Scratch/cosim/energyplus/EnergyPlus-9.1.0:${LD_LIBRARY_PATH:-}"

python3 prepare.py
python3 run-cosim-pool.py -w ${NSLOTS:-16} config.txt list.txt
```

Note that `prepare.py` runs first (generating `list.txt` and any IDF variants), then the cosimulation batch runs. Everything happens in a single job submission.

### Scaling to 1,000+ simulations with SGE array jobs

The single-node `smp` approach above works well for up to ~50 simulations. Beyond that, you're bottlenecked on one node's cores. For large-scale parametric studies (hundreds or thousands of simulations), use **SGE array jobs** to distribute work across the entire Myriad cluster.

#### Why array jobs?

| Approach | Nodes used | Max parallelism | 1,000 sims @ 15 min each |
|---|---|---|---|
| `#$ -pe smp 16` (single node) | 1 | 16 cores | ~16 hours |
| `#$ -t 1-1000` (array job) | up to 1,000 | 1,000 tasks | ~15 minutes* |

\* Assumes enough nodes are free. In practice, the scheduler starts tasks as resources become available. You can limit concurrent tasks with `#$ -tc 100` to be a good cluster citizen.

With an array job, each task is an independent job that runs on whatever node the scheduler assigns. SGE sets the `$SGE_TASK_ID` environment variable (1, 2, 3, ...) in each task, and you use that to pick which simulation to run.

#### Strategy 1: One simulation per array task (recommended)

Each array task runs exactly one cosimulation. A parameter file maps task IDs to input files. This is the simplest and most scalable approach.

**Step 1:** Run your `prepare.py` script to generate all input files and a parameter file called `params.txt`. Each line corresponds to one simulation (line 1 = task 1, line 2 = task 2, etc.):

```
# params.txt - one simulation per line
# IDF, EPW, PRJ, VEF, XML
./inputs/office-gas.idf , ./inputs/epw/london.epw , ./inputs/office.prj , ./inputs/office-contam.vef , ./inputs/office-modelDescription.xml
./inputs/office-gas.idf , ./inputs/epw/manchester.epw , ./inputs/office.prj , ./inputs/office-contam.vef , ./inputs/office-modelDescription.xml
./inputs/office-hp.idf , ./inputs/epw/london.epw , ./inputs/office.prj , ./inputs/office-contam.vef , ./inputs/office-modelDescription.xml
...
```

This is the same format as `list.txt` — one comma-separated line of 5 input files per simulation.

**Step 2:** Write a wrapper script that extracts one line from `params.txt` and runs a single cosimulation. Save this as `run-one-sim.sh`:

```bash
#!/bin/bash
# run-one-sim.sh - Run a single cosimulation for a given task ID
# Usage: ./run-one-sim.sh <task_id>
#
# Reads line <task_id> from params.txt, creates a temporary list.txt
# with just that one line, then runs the cosimulation.

TASK_ID=$1
STUDY_DIR=$(dirname "$0")

# Extract the line for this task (skip comment lines)
LINE=$(grep -v '^\s*#' "${STUDY_DIR}/params.txt" | sed -n "${TASK_ID}p")

if [ -z "$LINE" ]; then
    echo "ERROR: No simulation found for task ID ${TASK_ID}" >&2
    exit 1
fi

# Create a task-specific working directory
TASK_DIR="${STUDY_DIR}/task_${TASK_ID}"
mkdir -p "${TASK_DIR}"

# Write a single-line list file for this task
echo "$LINE" > "${TASK_DIR}/list.txt"

# Copy/symlink the runner and config
cp "${STUDY_DIR}/run-cosim-pool.py" "${TASK_DIR}/"
cp "${STUDY_DIR}/config.txt" "${TASK_DIR}/"
cp "${STUDY_DIR}/ContamFMU-3400-linux64.fmu" "${TASK_DIR}/"

cd "${TASK_DIR}"
python3 run-cosim-pool.py -w 1 config.txt list.txt

echo "Task ${TASK_ID} completed with exit code $?"
```

Make it executable:

```bash
chmod +x run-one-sim.sh
```

**Step 3:** Create the array job script. Save as `run_array.sh`:

```bash
#!/bin/bash -l

#$ -N cosim_array
#$ -l h_rt=2:00:00
#$ -l mem=4G
#$ -l tmpfs=15G

# Array range: 1 to N where N = number of non-comment lines in params.txt
#$ -t 1-1000

# Limit concurrent tasks to avoid overwhelming the cluster (optional but polite)
#$ -tc 100

#$ -wd /home/<YOUR_UCL_ID>/Scratch/cosim/studies/my-study

module unload gcc-libs
module load gcc-libs/10.2.0
module load python3/3.11

export LD_LIBRARY_PATH="${HOME}/Scratch/cosim/energyplus/EnergyPlus-9.1.0:${LD_LIBRARY_PATH:-}"

# SGE_TASK_ID is set automatically by the scheduler (1, 2, 3, ...)
./run-one-sim.sh ${SGE_TASK_ID}
```

**Step 4:** Submit:

```bash
qsub run_array.sh
```

SGE creates 1,000 individual tasks. Each gets its own `SGE_TASK_ID`, runs `run-one-sim.sh` with that ID, and produces output in `task_<ID>/run_*/`. Stdout and stderr for each task go to `cosim_array.o<JOBID>.<TASKID>` and `cosim_array.e<JOBID>.<TASKID>`.

#### Setting the correct array range

The `-t` range must match the number of simulations in `params.txt`. Count the non-comment lines:

```bash
NSIMS=$(grep -cv '^\s*#' params.txt)
echo "Number of simulations: $NSIMS"
```

Then set `#$ -t 1-${NSIMS}` in the job script (SGE requires a literal number, so replace it manually or use `qsub -t 1-${NSIMS} run_array.sh` on the command line to override).

#### Strategy 2: Batched array tasks (array with stride)

If each individual simulation is very short (under a few minutes), the overhead of scheduling 1,000 separate jobs can be wasteful. Instead, use a **strided array** where each task runs a batch of simulations:

```bash
#!/bin/bash -l

#$ -N cosim_batch
#$ -l h_rt=4:00:00
#$ -l mem=4G
#$ -l tmpfs=30G
#$ -pe smp 4

# 1,000 simulations in batches of 25 → 40 array tasks
#$ -t 1-1000:25
#$ -tc 50

#$ -wd /home/<YOUR_UCL_ID>/Scratch/cosim/studies/my-study

module unload gcc-libs
module load gcc-libs/10.2.0
module load python3/3.11

export LD_LIBRARY_PATH="${HOME}/Scratch/cosim/energyplus/EnergyPlus-9.1.0:${LD_LIBRARY_PATH:-}"

# SGE_TASK_ID is the start of this batch (1, 26, 51, 76, ...)
# SGE_TASK_STEPSIZE is the stride (25)
START=${SGE_TASK_ID}
END=$(( SGE_TASK_ID + SGE_TASK_STEPSIZE - 1 ))

# Don't exceed the total number of simulations
TOTAL=$(grep -cv '^\s*#' params.txt)
if [ $END -gt $TOTAL ]; then
    END=$TOTAL
fi

# Extract the batch of lines into a temporary list file
BATCH_DIR="batch_${START}_${END}"
mkdir -p "${BATCH_DIR}"

grep -v '^\s*#' params.txt | sed -n "${START},${END}p" > "${BATCH_DIR}/list.txt"

cp run-cosim-pool.py "${BATCH_DIR}/"
cp config.txt "${BATCH_DIR}/"
cp ContamFMU-3400-linux64.fmu "${BATCH_DIR}/"

cd "${BATCH_DIR}"
python3 run-cosim-pool.py -w ${NSLOTS:-4} config.txt list.txt

echo "Batch ${START}-${END} completed with exit code $?"
```

This creates 40 array tasks (1000 ÷ 25), each running 25 simulations in parallel on 4 cores. It's a good middle ground: fewer scheduler overheads than 1,000 individual tasks, but much faster than a single node.

#### Generating params.txt from prepare.py

Your existing `prepare.py` script just needs to write `params.txt` instead of (or in addition to) `list.txt`. Since the format is identical, you can simply rename the output or write both:

```python
#!/usr/bin/env python3
"""Generate params.txt for an array job study."""

import os
import itertools

# Base files
prj = "./inputs/office.prj"
vef = "./inputs/office-contam.vef"
xml = "./inputs/office-modelDescription.xml"

# Variants
idfs = ["./inputs/office-gas.idf", "./inputs/office-hp.idf", "./inputs/office-elecres.idf"]
epw_dir = "./inputs/epw"
epws = sorted(os.path.join(epw_dir, f) for f in os.listdir(epw_dir) if f.endswith(".epw"))

# Full factorial: every IDF × every EPW
with open("params.txt", "w") as f:
    f.write("# Auto-generated parameter file for array job\n")
    f.write("# IDF, EPW, PRJ, VEF, XML\n")
    for idf, epw in itertools.product(idfs, epws):
        f.write(f"{idf} , {epw} , {prj} , {vef} , {xml}\n")

nsims = len(idfs) * len(epws)
print(f"Generated params.txt with {nsims} simulations")
print(f"Use: #$ -t 1-{nsims}")
```

#### Monitoring array jobs

```bash
# Check overall status
qstat

# See which tasks are running/pending
qstat -t

# Check a specific task's output
cat cosim_array.o<JOBID>.<TASKID>
cat cosim_array.e<JOBID>.<TASKID>

# Count completed tasks
ls -d task_*/run_*/ 2>/dev/null | wc -l
```

#### Which strategy to choose

| Study size | Sim duration | Recommended approach |
|---|---|---|
| 1–50 | Any | Single `smp` job (section above) |
| 50–200 | > 5 min each | Array job, 1 sim per task (Strategy 1) |
| 200–5,000 | > 5 min each | Array job, 1 sim per task with `-tc` limit |
| 200–5,000 | < 5 min each | Strided array, 25–50 sims per task (Strategy 2) |
| 5,000+ | Any | Strided array with larger batches |

## Repository Structure

```
energyplus_contam_cosim_linux_hpc/
├── README.md
├── energyplus/                                        # EnergyPlus 9.1.0 Linux installer
│   └── EnergyPlus-9.1.0-08d2e308bb-Linux-x86_64.tar.gz
├── contamx/                                           # CONTAM 3.4.0.0 solver
│   └── contam-x-3.4.0.0-Linux-64bit.tar.gz
├── contam_fmu/                                        # ContamFMU shared library for Linux
│   └── ContamFMU-3.4.0-Linux.tar.gz
├── mz320_example/                                     # MZ320 analytical test case
│   └── MZ320-EPlus-91-CONTAM-34-fmu.zip
└── energyplus_contam_cosimulation_multiprocessing/     # NIST parametric runner
    ├── run-cosim-pool-ep91-cx34.zip                   # Original zip from NIST
    └── run-cosim-pool-ep91-cx34/                      # Extracted contents
        ├── README.md
        ├── run-cosim-pool.py                          # Multiprocessing cosim script
        ├── blank-fmus/
        │   └── ContamFMU-3400.fmu                     # Win32-only blank FMU
        ├── epw-files/
        │   ├── boston-logan.epw
        │   └── USA_MA_Boston-Logan.Intl.AP.725090_TMY3.epw
        └── test-fmu-cx-3400/                          # PNNL single-family test case
            ├── config.txt                             # Windows paths (needs adapting)
            ├── list.txt                               # Windows paths (needs adapting)
            ├── sf-slab-gas.idf                        # EnergyPlus model (gas heating)
            ├── sf-slab-elecres.idf                    # EnergyPlus model (electric)
            ├── sf-slab-hp.idf                         # EnergyPlus model (heat pump)
            ├── sf-slab.prj                            # CONTAM project file
            ├── sf-slab-contam.vef                     # Variable exchange file
            └── sf-slab-modelDescription.xml           # FMI model description
```

## Directory Layout on Myriad (after setup)

```
~/Scratch/cosim/                                       # This repo, cloned to Scratch
├── README.md
├── energyplus/
│   ├── EnergyPlus-9.1.0-08d2e308bb-Linux-x86_64.tar.gz
│   └── EnergyPlus-9.1.0/                             # Extracted (step 2)
│       ├── energyplus
│       └── PostProcess/ReadVarsESO
├── contamx/
│   ├── contam-x-3.4.0.0-Linux-64bit.tar.gz
│   └── contam-x-3.4.0.0-Linux-64bit/                 # Extracted (step 3a)
│       └── contamx3
├── contam_fmu/
│   ├── ContamFMU-3.4.0-Linux.tar.gz
│   ├── ContamFMU-3.4.0-Linux/                         # Extracted (step 3b)
│   └── ContamFMU.so                                   # Renamed from libContamFMU.so (step 3b)
├── blank-fmus/
│   └── ContamFMU-3400-linux64.fmu                     # Built (step 4)
├── mz320_example/
│   └── MZ320-EPlus-91-CONTAM-34-fmu.zip
├── energyplus_contam_cosimulation_multiprocessing/     # NIST source files
│   └── run-cosim-pool-ep91-cx34/
└── test/                                              # Self-contained test case (step 5)
    ├── run-cosim-pool.py
    ├── config.txt                                     # Created (step 6)
    ├── list.txt                                       # Created (step 7)
    ├── run_cosim_job.sh                               # Created (step 9)
    ├── ContamFMU-3400-linux64.fmu                     # Copied from blank-fmus/
    ├── boston-logan.epw
    ├── sf-slab-gas.idf
    ├── sf-slab-elecres.idf
    ├── sf-slab-hp.idf
    ├── sf-slab.prj
    ├── sf-slab-contam.vef
    └── sf-slab-modelDescription.xml
```

## Troubleshooting

### "ERROR: Unknown OS"

The Python script checks `sys.platform`. On Linux it should be `"linux"` or `"linux2"`. The patched `run-cosim-pool.py` handles both.

### GLIBCXX_3.4.21 not found

EnergyPlus 9.1 needs a newer C++ standard library than Myriad's default `gcc-libs/4.9.2` provides. You'll see an error like `GLIBCXX_3.4.21 not found`. Fix by loading a newer gcc-libs before running:

```bash
module unload gcc-libs
module load gcc-libs/10.2.0
```

Note: you must `unload` first because the default `gcc-libs/4.9.2` is auto-loaded and conflicts with loading a different version directly.

### GLIBC version errors from contamx3

If contamx3 fails with `GLIBC_2.28 not found` or similar, you are using contamx3 3.4.0.3 which requires glibc 2.34+. Myriad's RHEL 7.9 only has glibc 2.17. Download contamx3 **3.4.0.0** instead from https://www.nist.gov/document/contam-x-3400-linux-64bittargz — this older build is compatible with glibc 2.17.

### Library not found errors

If EnergyPlus reports missing shared libraries at runtime, make sure the EnergyPlus directory is on `LD_LIBRARY_PATH`:

```bash
export LD_LIBRARY_PATH=$HOME/Scratch/cosim/energyplus/EnergyPlus-9.1.0:$LD_LIBRARY_PATH
```

### contamx3.exe not found in FMU

If you see an error like `chmod: cannot access 'tmp-fmus/.../binaries/linux64/contamx3.exe'`, the contamx3 binary inside the FMU must be named `contamx3.exe` (with the `.exe` suffix). EnergyPlus looks for this exact filename even on Linux. Rebuild the FMU with the correct name (see step 4).

### FMU / ContamFMU errors

Make sure the FMU has the correct structure with `binaries/linux64/` containing both `ContamFMU.so` and `contamx3.exe`. The PRJ file gets copied into `binaries/linux64/contam.prj` by the script at runtime.

### Python multiprocessing on compute nodes

Request multiple cores with `#$ -pe smp N`. The script uses `$NSLOTS` (set by SGE) as the worker count.

### CONTAM download URLs change

If NIST URLs stop working, visit:
- [CONTAM solver downloads](https://www.nist.gov/el/energy-and-environment-division-73200/nist-multizone-modeling/software/contam/download)
- [ContamFMU / 3D Exporter](https://www.nist.gov/el/energy-and-environment-division-73200/nist-multizone-modeling/software/contam-3d-exporter)
- [Parametric Analysis Utilities](https://www.nist.gov/el/energy-and-environment-division-73200/nist-multizone-modeling/contam-parametric-analysis)

## References

- [NIST CONTAM Parametric Analysis Utilities](https://www.nist.gov/el/beed/nist-multizone-modeling/contam-parametric-analysis-utilities)
- [EnergyPlus 9.1.0 Release](https://github.com/NREL/EnergyPlus/releases/tag/v9.1.0)
- [EnergyPlus 9.1.0 Linux Direct Download](https://github.com/NatLabRockies/EnergyPlus/releases/download/v9.1.0/EnergyPlus-9.1.0-08d2e308bb-Linux-x86_64.tar.gz)
- [contamx3 3.4.0.0 Linux 64-bit (RHEL 7 compatible)](https://www.nist.gov/document/contam-x-3400-linux-64bittargz)
- [CONTAM 3D Exporter / ContamFMU Downloads](https://www.nist.gov/el/energy-and-environment-division-73200/nist-multizone-modeling/software/contam-3d-exporter)
- [Example: PNNL Single-family (EPlus 9.1 + CONTAM 3.4)](https://www.nist.gov/el/energy-and-environment-division-73200/nist-multizone-modeling/software/contam-3d-exporter) — `pnnl-sf-ep91-cx3400.zip`
- [Example: MZ320 Analytical Test Case (EPlus 9.1 + CONTAM 3.4)](https://www.nist.gov/el/energy-and-environment-division-73200/nist-multizone-modeling/software/contam-3d-exporter) — `MZ320-EPlus-91-CONTAM-34-fmu.zip`
- [UCL Myriad User Guide](https://www.rc.ucl.ac.uk/docs/Clusters/Myriad/)
- [UCL Installing Software on HPC](https://www.rc.ucl.ac.uk/docs/Software/Installing_Software/)

## License

This guide is provided as-is for research purposes. EnergyPlus and CONTAM are developed by NREL/DOE and NIST respectively.
