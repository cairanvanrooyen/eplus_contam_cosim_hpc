# Batchrun — Ready-to-use cosimulation folder

This folder is pre-configured to run EnergyPlus-CONTAM cosimulations on Myriad.

## What to do

1. **Add your input files** to this directory:
   - `.idf` — EnergyPlus model (must be v9.4 format)
   - `.epw` — weather file
   - `.prj` — CONTAM project file
   - `.vef` — variable exchange file
   - `.xml` — modelDescription.xml

2. **Edit `list.txt`** — add one line per simulation:
   ```
   ./my-building.idf , ./my-weather.epw , ./contam.prj , ./contam.vef , ./modelDescription.xml
   ```

3. **Edit `run_cosim_job.sh`** — replace `USERNAME` in the `#$ -wd` line with your UCL username.

4. **Submit the job:**
   ```bash
   qsub run_cosim_job.sh
   ```

## What's already here

| File | Purpose |
|------|---------|
| `run-cosim-pool.py` | NIST cosimulation runner (copied by setup.sh) |
| `config.txt` | Points to EnergyPlus and the blank FMU (set by setup.sh) |
| `list.txt` | Template — add your simulations here |
| `ContamFMU-3400-linux64.fmu` | Linux blank FMU (built by setup.sh) |
| `run_cosim_job.sh` | SGE job script with TMPDIR pattern |

## Notes

- The job script copies everything to `$TMPDIR` (fast local node storage) before running, then copies results back to Scratch.
- Adjust `#$ -pe smp N` for more parallel workers and `#$ -l h_rt` for longer runs.
- Results appear in `run_<timestamp>/` subdirectories after the job completes.
