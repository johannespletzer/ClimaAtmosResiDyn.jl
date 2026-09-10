# Levante task list

Self-contained. Everything needed to pick the work up is here — the state, what
was found, what to run, and what is still open. Nothing below requires reading
another document first.

Branch `claude/tag-closure-experiments`. Written at `992b9d8`.

## Where things stand

14 of 25 runs are committed and analysed. Phase A is complete, C0 is complete.

**Decided by measurement.** Moving the water tags into the implicit solve is not
worth its Jacobian cost. The default van Leer ladder is flat, slope −0.011,
while both linear ladders converge (+0.255 and +0.464), and at `dt` 10 s the
fully linear reconstruction sits 13.8× lower. The residual is limiter-bounded,
not discretization-bounded, so implicit tags would remove the part that is not
there.

**Found, and now issue #64.** The water tags diverge to 1e130 on a one-day
sphere with the SEM limiter while `ρq_tot` stays bounded at 1.62e16 throughout,
and the run exits 0 reporting success. The existing integration test runs that
same configuration for one hour and the divergence starts between hours two and
three, so the test passes because it stops before the failure begins.

**Measured by C0.** The source-tag donor rule is inert over 96.7% of the DYCOMS
column and 43.276% of a moist sphere — the latter constant to the last digit
across 24 hours. Production accumulates without loss, and a source tag reaches
−209 J kg⁻¹ on the sphere with `e_src_res` showing nothing, because the residual
sums only the pure region tags.

**Open and unexplained.** The textbook internal energy at the DYCOMS surface
state is about +3.3e4 J kg⁻¹; the model's own field reaches −4.5e4. Nothing in
this repository overrides a thermodynamic reference, so whatever sets that
offset is in Thermodynamics.jl or the ClimaParams defaults. Task 1 settles it.

## Once per shell

```bash
cd ~/git/ClimaAtmosResiDyn.jl
git pull origin claude/tag-closure-experiments
export JULIA_DEPOT_PATH="$HOME/.julia/depots/levante-cpu"
```

The depot export matters. The runscripts use that depot, so an instantiate or a
script run under a different one will not be seen by a batch job. If
`.buildkite` has never been instantiated in it, do that first, on a login node,
because compute nodes have no outbound network:

```bash
julia +1.11 --project=.buildkite -e 'using Pkg; Pkg.instantiate(); Pkg.precompile()'
```

## 1. The thermodynamic reference

One command, and the highest value thing here. Do it before deciding anything
about C1.

```bash
julia +1.11 --project=.buildkite -e '
    import Thermodynamics as TD, ClimaParams
    tp = TD.Parameters.ThermodynamicsParameters(Float64)
    println(fieldnames(typeof(tp)))
    println("T_0      = ", tp.T_0)
    println("e_int_v0 = ", TD.Parameters.e_int_v0(tp))
    println("cv_d     = ", TD.Parameters.cv_d(tp))
    e = TD.internal_energy(tp, 288.3, TD.PhasePartition(0.00945))
    println("e_int(288.3K, 9.45g/kg) = ", e)
    println("ClimaParams at ", pkgdir(ClimaParams))'
```

Three things it decides.

  - **Which reading explains the offset.** If `T_0` is 273.16 and
    `internal_energy` still returns near `−5e4`, the convention differs from the
    textbook form and the definition is what to read. If `T_0` is not 273.16,
    that is the answer outright.
  - **The parameter's name.** The plumbing is already known to be reachable:
    `create_parameters.jl:75` builds the thermodynamic parameters entirely from
    the TOML dict and `Parameters.jl:602` forwards every field, so a config
    reaches them through the `toml:` key. What is missing is the name, and the
    field list gives it. **This means the reference shift is a configuration
    change, not a fork of Thermodynamics.jl.**
  - **Whether the shift is even constant.** `Parameters.jl:607` lists
    `e_int_v0` and `e_int_i0` as *derived* rather than as fields. If they are
    derived conventionally, moving the reference moves the latent-heat offsets
    with it and the shift becomes `ΔT·(cv_m + q_vap·R_v)` rather than `ΔT·cv`.
    The shifted parent would then be `e_tot + c(q)` and not `e_tot + c` — a
    premise both shift shapes rest on.

There is a third possibility worth holding in mind. If the *initialisation* is
what is off rather than the reference, then C0's headline result — 43.276% of a
sphere where the donor share is undefined — is a fact about this model's initial
state and not about the energy reference. That would mean rereading the C0
learning entry and the memo's Part 3 source bullet. The evidence does not force
that yet, which is why neither was edited, but this command is what decides.

## 2. Re-run the phase A analysis

`summary_a.csv` predates `a3_1m` and does not contain it, and the plot scaling
has changed since the figures were made.

```bash
julia +1.11 --project=.buildkite experiments/tag_closure/analysis/phase_a.jl
```

The ladder figure should now show flat as flat: at least a full decade on the
y-axis, reference slopes 1 and 2, and x ticks at 2.5, 5 and 10 rather than
powers of ten. Commit the regenerated `summary_a.csv` and the PNGs.

## 3. Run the phase C analysis

**This has never been executed.** The C0 learning entries were written from the
raw tables. There is no `summary_c.csv` and there are no phase C figures.

```bash
julia +1.11 --project=.buildkite experiments/tag_closure/analysis/phase_c.jl
```

## 4. Where `e_tot` is negative

Also never run. Every magnitude argument about the shift turns on the structure
of the negative region, and only its minimum has been seen so far.

```bash
julia +1.11 --project=.buildkite \
    experiments/tag_closure/analysis/where_negative.jl output/c0_column/output_active
julia +1.11 --project=.buildkite \
    experiments/tag_closure/analysis/where_negative.jl output/c0_sphere/output_active
```

It reports the fraction negative by level, the minimum by level, the height at
which the sign changes, whether the negative region is contiguous, and the
smallest constant that would make the whole field positive. Commit the CSVs it
writes.

## 5. Two batch runs

```bash
CONFIG=experiments/tag_closure/configs/c3_column_record.yml \
    sbatch experiments/tag_closure/runscripts/phase_c.sh

CONFIG=experiments/tag_closure/configs/c0_sphere_deep.yml \
    sbatch experiments/tag_closure/runscripts/phase_c.sh
```

From a tcsh login shell use `env CONFIG=... sbatch ...` instead; that is the
only thing the login shell changes.

  - **C3** reads the energy process record on a configuration where the source
    tags' own donor rule is not running. It measures the alternative that
    `energy_source_tags.md` names, and needs no code change or approval.
  - **`c0_sphere_deep`** is `c0_sphere` on the 60 km grid. C0 measured 43.276%
    non-positive at 30 km while the docs attribute the non-positive parent to
    shallow domains. Doubling the depth separates a domain artifact from a
    property of the reference.

After each, check the job's exit status rather than only the log, because a
crashed solve returns `:simulation_crashed` and the driver's non-zero exit is
what makes that visible:

```bash
sacct -j <jobid> -o JobID,State,ExitCode
```

Then reduce before copying anything back, because the operator residual lives in
the NetCDF and the NetCDF stays on scratch:

```bash
julia +1.11 --project=.buildkite \
    experiments/tag_closure/analysis/reduce_run.jl output/<run>/output_active
```

Five files per run into `experiments/tag_closure/output/<run>/`: the family's
`*_tag_closure.csv`, the reduced tables, `<run>.yml`, `provenance.txt`, and a
trimmed `run.log`. The analysis refuses any run whose `provenance.txt` records
`commit: unknown`.

## Not yet, and why

**Phase B.** B1 is ten simulated days on a sphere with a limiter, which is the
regime that diverged to 1e130 in three hours in A5. Until issue #64 is
understood, phase B risks buying expensive noise. B2 is dry and unaffected if
the phase has to start somewhere.

**C1.** It needs a code change, the owner's approval, and a shift shape that has
not been chosen. Of the two shapes in the memo, shifting only the share's
denominator should be dropped rather than costed: the region tags sum to
`ρe_tot` and not to `ρe_tot + c`, so wherever `e < 0` the shares sum to a
negative number and the loss adds energy instead of removing it, diverging as
`e` approaches `−c` — over exactly the region the shift was introduced to fix.
Tasks 1 and 4 both bear on the remaining choice.

**A3's companion.** A3 differs from `a1_dt10` in two keys, `microphysics_model`
and `vert_diff`, so the gap between them is not the 1M mismatch alone.
Separating it cleanly needs one extra 0M column run with `vert_diff` on. The
config is deliberately not written.

## What to expect

Tasks 3 and 4 have never executed. Every first run in this series has failed
once, and every one of those failures has been in the tooling rather than in the
science. Send the error rather than working around it.
