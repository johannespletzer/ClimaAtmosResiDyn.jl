# P-8+8 at `d3c5e42f`: where the 8 + 8 excess sits (design/WP9_COST.md section 12.1)

Model `main` `d3c5e42f`, record `84d03ff68`. Two exclusive jobs, four points
each on one node: untagged, 8 water, 8 energy, 8 + 8, all on D4, default
mode. `analysis/wp9_profile_driver.jl` with 50 warm-up steps and a 20 s time
profile. The `*_alloc_type.csv` files (up to 21 MB) stay on scratch, in
`$SCRATCH/tag_closure/output/wp9_profile_d3c5/`.

| job        | id       | node            | state               |
|:-----------|:---------|:----------------|:--------------------|
| `prof88_a` | 14125920 | `hpdar07c05s08` | COMPLETED           |
| `prof88_b` | 14125921 | `hpdar09c05s05` | COMPLETED, 02:22:49 |

`excess.md` is `analysis/wp9_excess.py output/wp9_profile_d3c5 --frames`.
`--frames` (the innermost frame in `src/`, from section 8's top-80 tables) was
added after the first job was read. It is post hoc, and is marked so.

## The excess

`excess = (8 + 8) - (8 water) - (8 energy) + (untagged)`, in ms per step of
each job's timed block (one block of 20 steps):

| job | untagged | water | energy | 8 + 8 | excess    | bytes excess |
|:----|---------:|------:|-------:|------:|----------:|-------------:|
| a   | 4.829    | 7.036 | 5.609  | 14.094 | 6.277    | 2.20 MB      |
| b   | 6.993    | 10.018 | 11.204 | 22.340 | 8.111   | 2.21 MB      |

These single blocks are the profile's, not section 11's cost measure. Their
ratios (8 + 8: 2.92 and 3.19) differ from it.

## Where it is recorded

  - **By hook (pre-registered):** implicit tendency 1.30 and 1.92 ms (20.7%
    and 23.7%), explicit tendency 1.04 and 1.26 ms (16.6% and 15.5%), and
    `other` 3.11 and 4.05 ms (49.6% and 49.9%). The call table did not
    resolve below the hook: its first frame inside the hook is a
    `macro expansion` frame.
  - **Tag code:** at most 3.5% of the excess is in a frame under
    `tagged_tracers/`. 96.5% and 97.5% is not.
  - **By innermost frame (post hoc):** six frames in `src/utils/` that walk
    or filter tuples of tracer names hold 3.21 and 5.13 ms of excess, 51% and
    63% of the timed excess: `sedimenting_tracer_names` and
    `sedimenting_mass_names` (`tracer_processes.jl:138`, `:153`), the
    closure in `foreach_gs_tracer` (`variable_manipulations.jl:242`),
    `gs_tracer_names`, `microphysics_tracer_names` and `sgs_tracer_names`.
    None of them is in the top 80 frames of the untagged point or of either
    half, where the 80th frame holds at most 0.012 ms. They also hold 1.0 MB
    of the 2.2 MB of excess allocation per step. Of the rest,
    `advection.jl:124` holds 0.49 MB, and the two tag sedimentation blocks of
    the Jacobian 0.23 MB each.
  - **`other` / `(outside src)`:** about 51% of the samples at every point
    of both jobs. They match a second Julia thread's samples. The review
    found the thread after the jobs (`threads_check.txt`, from
    `analysis/wp9_profile_threads.jl` on a login node): `import ClimaAtmos`
    in the run tree's environment leaves `Threads.maxthreadid()` at 2, and
    `Profile` samples both threads, half each. So the ms above are about half
    the stepper's. `excess_stepper.md` (`analysis/wp9_excess_stepper.py`,
    post hoc) reads the stepper's half: implicit tendency 41% and 47%,
    explicit 33% and 31%, Jacobian 29% and 30%, tag code at most 7.0% and
    5.0%, and the six walks 102% and 126% of the timed excess.
  - **Mechanism (inferred, FINDINGS E90):** ClimaCore's
    `propertynames(::DataLayout)` filters a tuple with `Base.filter`, which
    runs at run time from 32 entries on. The 8 + 8 point's `Y.c` has 38.

A profile locates where the cost is recorded. The profile alone does not
say why the walks cost time only when both families are on. The mechanism
above is read from the code.
