# C's revision: the 30-day parity rerun

`design/NEGATIVE_PARENT_WATER.md`, sections 11.8 and 11.10 (question 8). Site
23 for 30 days, with and without tags, on the revision's run tree (`4d78b121`)
and on `main`'s (`03645b0e`). Both are the earlier trees with the record at
`bbc87207` merged in, so the model code is unchanged. Jobs `14005271`
(`cr_parity30_tags_rev`), `14005272` (`cr_parity30_untagged_rev`), `14005273`
(`cr_parity30_tags_main`), `14005274` (`cr_parity30_untagged_main`), 2026-09-29,
exit status 0. Run data: `$SCRATCH/tag_closure/output/cr_parity30_*/output_0000`.

  - `parity_output.txt`: `analysis/water/cr_parity.py`, every NetCDF file.
  - `state_output.txt`: `analysis/water/cr_parity_state.jl`, the state saved
    at day 30.

Commands, from the record worktree:

    python3 experiments/tag_closure/analysis/water/cr_parity.py \
        $SCRATCH/tag_closure/output cr_parity30 > output/cr_parity30/parity_output.txt
    julia --project=$SCRATCH/claude_work/crev_testenv \
        experiments/tag_closure/analysis/water/cr_parity_state.jl \
        $SCRATCH/tag_closure/output cr_parity30 30 > output/cr_parity30/state_output.txt

The Julia call needs `JULIA_DEPOT_PATH=$SCRATCH/julia-depots/terrabyte-cpu` and
`module load gcc/13.2.0 openmpi/4.1.8-gcc13`.

Result: every model field is bit for bit in all four pairs, and the water
region tags differ from `main`'s from day 11.5. See 11.8. A second scoring,
`$SCRATCH/claude_work/crev_parity30_rederive/rederive_parity30.py`, agrees.

No file over 2 MB is kept on scratch only. The largest run file is the
tagged `day30.0.hdf5` at 0.2 MB, and the tagged output directory is 13 MB in
all. So there are no checksums to record.
