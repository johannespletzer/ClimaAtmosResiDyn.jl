# Levante task list

What to run next, in order, with the commands. Written against
`claude/tag-closure-experiments` at `655cb5f`.

Tasks 1 to 4 run on a login node and take seconds to minutes. Task 5 is two
batch jobs. Task 1 is the one to do first: it could change what C1 is for, and
it costs one command.

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

Highest value, one command. It settles two open questions in
[C1_reference_shift.md](C1_reference_shift.md) and may raise a third.

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

What to look for:

  - **The textbook form gives `e_int` about `+3.3e4` J kg⁻¹ at the DYCOMS
    surface state. The model's own field reaches `−4.5e4`.** If `T_0` is 273.16
    and `internal_energy` still returns something near `−5e4`, the convention
    differs from the one assumed and the definition itself is what to read. If
    `T_0` is not 273.16, that is the answer outright.
  - **The field list** says whether the reference is a field, and therefore
    settable from a TOML file through the `toml:` config key. The parameter
    plumbing is already known to be reachable; what is missing is the name.
  - **Whether `e_int_v0` is derived rather than a field.** If it is, moving the
    reference moves the latent-heat offsets with it and the shift becomes
    `ΔT·(cv_m + q_vap·R_v)` rather than `ΔT·cv`. The shifted parent would then
    be `e_tot + c(q)` and not `e_tot + c` — a premise both shapes in the memo
    rest on.

There is a third possibility worth holding in mind. If the initialisation is
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

Also never run. Every magnitude argument in
[C1_reference_shift.md](C1_reference_shift.md) turns on the structure of the
negative region, and only its minimum has been seen so far.

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

After each: check the job's exit status rather than only the log, because a
crashed solve returns `:simulation_crashed` and the driver's non-zero exit is
what makes that visible.

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
trimmed `run.log`.

## Not yet

**Phase B.** B1 is ten simulated days on a sphere with a limiter, which is the
regime that diverged to 1e130 in three hours in A5 — see issue #64. Until that
is understood, phase B risks buying expensive noise. B2 is dry and unaffected if
the phase has to start somewhere.

**C1.** It needs a code change, the owner's approval, and a shift shape that has
not been chosen. Tasks 1 and 4 both bear on that choice, and task 1 could change
what C1 is for.

## What to expect

Tasks 3 and 4 have never executed. Every first run in this series has failed
once, and every one of those failures has been in the tooling rather than in the
science. Send the error rather than working around it.
