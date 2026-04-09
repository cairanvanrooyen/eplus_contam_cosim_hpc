---
name: EnergyPlus CONTAM cosimulation project
description: GitHub repo providing guide and scripts for running EnergyPlus+CONTAM cosimulation on UCL Myriad HPC
type: project
---

Repo purpose: step-by-step guide and scripts for installing and running EnergyPlus 9.1 + CONTAM 3.4 cosimulation on UCL Myriad HPC (Linux).

**Why:** The bundled ContamFMU only has win32 binaries; Linux setup requires building a custom FMU with linux64 binaries. Also EnergyPlus 9.5+ breaks compatibility with ContamFMU, so version 9.1 is required.

**How to apply:** All scripts/guides must target EnergyPlus 9.1.0 and CONTAM 3.4 specifically. Instructions must account for no-sudo user-space installs on Myriad.

Prior conversation already produced: GUIDE_UCL_MYRIAD.md, setup_cosim.sh, run_cosim_job.sh, run-cosim-pool.py (Linux-patched). These need to be integrated into the repo structure.
