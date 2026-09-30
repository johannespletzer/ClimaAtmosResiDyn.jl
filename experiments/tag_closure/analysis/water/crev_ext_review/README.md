# The review's replicas for design section 11.11

Small replicas that an agent's review of the draft of
`design/NEGATIVE_PARENT_WATER.md` section 11.11 used on 2026-09-30, and that
the revision reran. None of them runs the model. Each models one kernel or the
stepper on a few numbers, so each result bounds that case and no more.

| file                | what it replicates                                                                                     | used in           |
|:------------------- |:------------------------------------------------------------------------------------------------------ |:----------------- |
| `q5_passthrough.py` | `water_tag_pool_shares` and `water_tag_gross_flow_change`: the draft's empty pool against the kept one | 11.11.5           |
| `follower.py`       | `correct_water_tag_increment!` on one column: cases S1, S2 and the unshared loss                       | 11.11.3           |
| `follower_g.py`     | the same, with the revision's crossing give `g` by mask (cases S1, S2, S3)                             | 11.11.3           |
| `stages.py`         | ARS222 and ARS343 on one cell: the stage values and (I3)                                               | 11.11.4, 11.11.7  |
| `ratchet2.py`       | a source tag in 40 wet and dry cycles, rule A against the parent's gain                                | 11.11.4           |
| `f32.py`            | the error of `δL`, a difference of a cumulative ledger, in Float32 and Float64                         | 11.11.3           |
| `duals.jl`          | `G` and `w` on `ForwardDiff.Dual` with the fork's comparison overrides                                 | 11.11.2           |

Run the Python ones with `module load python/3.12` and `python3 <file>`.
`duals.jl` needs `ForwardDiff` (`Project.toml` here): with the scratch depot,
`JULIA_DEPOT_PATH=$SCRATCH/julia-depots/terrabyte-cpu julia +1.11 --project=. duals.jl`
after `Pkg.instantiate()`.
