#!/bin/tcsh -f
#SBATCH --job-name=tag-closure-c
#SBATCH --account=bd1062
#SBATCH --partition=shared
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=16
#SBATCH --mem=64G
#SBATCH --time=12:00:00
#SBATCH --output=tag-closure-c-%j.out
#SBATCH --error=tag-closure-c-%j.err
#SBATCH --mail-type=FAIL

# Phase C, the energy source tag runs -- the tcsh variant of phase_c.sh.
#
# The bash script beside this one is the documented default and does the same
# work. This exists as a fallback for a site where bash is not wanted.
#
# The job script's interpreter and the login shell you submit from are separate
# choices. sbatch exports the submitting environment whatever the job script is
# written in, so phase_c.sh works perfectly well when submitted from tcsh --
# only the command line differs. From a tcsh login shell, VAR=value before a
# command is not valid syntax, so use one of:
#
#     env CONFIG=experiments/tag_closure/configs/c0_column.yml \
#         sbatch experiments/tag_closure/runscripts/phase_c.tcsh
#
#     setenv CONFIG experiments/tag_closure/configs/c0_column.yml
#     sbatch experiments/tag_closure/runscripts/phase_c.tcsh
#
# Submit from the repository root. The #SBATCH block matches phase_c.sh
# exactly; everything below is in tag_closure_common.tcsh, which explains what
# tcsh forces to be different.

set SCRIPT_NAME = "phase_c.tcsh"

# ---------------------------------------------------------------------------
# Locate the repository, then hand over to the shared body.
#
# This cannot live in the shared file: sbatch copies this script to the node's
# spool directory before running it, so $0 is /var/spool/slurmd/job<id>/... and
# its directory holds nothing of ours. SLURM_SUBMIT_DIR, where sbatch was
# invoked, is the repository root for the documented submit line.
# runscripts/xmodel.1gpu locates itself the same way.
# ---------------------------------------------------------------------------

set SHARED = "experiments/tag_closure/runscripts/tag_closure_common.tcsh"

if (! $?ROOT) then
    set ROOT = ""
endif

if ("$ROOT" == "") then
    set candidates = ()
    if ($?SLURM_SUBMIT_DIR) then
        set candidates = ($candidates "$SLURM_SUBMIT_DIR")
        set candidates = ($candidates "$SLURM_SUBMIT_DIR/..")
        set candidates = ($candidates "$SLURM_SUBMIT_DIR/../..")
    endif
    set candidates = ($candidates "$cwd")
    foreach candidate ($candidates)
        if (-r "$candidate/$SHARED") then
            set ROOT = `cd "$candidate" && pwd`
            break
        endif
    end
endif

if ("$ROOT" == "") then
    echo "ERROR: could not locate the repository." >> /dev/stderr
    if ($?SLURM_SUBMIT_DIR) then
        echo "  SLURM_SUBMIT_DIR=$SLURM_SUBMIT_DIR" >> /dev/stderr
    else
        echo "  SLURM_SUBMIT_DIR=unset" >> /dev/stderr
    endif
    echo "Submit from the repository root, or set ROOT explicitly:" >> /dev/stderr
    echo "  env ROOT=/path/to/ClimaAtmosResiDyn.jl CONFIG=... sbatch ..." >> /dev/stderr
    exit 1
endif

source "${ROOT}/${SHARED}"
