# Levante task list

Self-contained. The state, what was found, what to run, and what is still open.
Nothing below requires reading another document first.

Branch `claude/tag-closure-experiments`. Written at `270c043`.

## Where things stand

16 of 25 runs are committed and analysed. Phase A is complete, C0 is complete,
and all three analysis scripts have now run on real data.

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
column and 43.276% of a moist sphere. Production accumulates without loss, and a
source tag reaches −209 J kg⁻¹ on the sphere while `e_src_res` shows nothing,
because the residual sums only the pure region tags.

**The negative region is the troposphere.** `where_negative.jl` settled the
structure. On the sphere every level from 250 m to 11.0 km is 100% negative and
every level from 15.5 km up is 0% negative — no mixed level anywhere. The sign
change sits between them, and `0.43276 × 30 km = 12.98 km` places it there
exactly. The vertical structure is geopotential as it should be: `e_tot` swings
212 kJ kg⁻¹ between 250 m and 26.9 km against `gz` = 264 kJ kg⁻¹ over the same
span. The column is negative at all 30 levels, −41.0 to −45.4 kJ kg⁻¹, with a
clean step at 825 m where the DYCOMS inversion is. **The shape is right; what is
wrong is an offset.** Smallest shift that would make the field positive: 45.4 kJ
kg⁻¹ on the column, 100.4 kJ kg⁻¹ on the sphere.

**Open and unexplained.** The textbook internal energy at the DYCOMS surface
state is about +3.3e4 J kg⁻¹; the model's own field reaches −4.5e4. Nothing in
this repository overrides a thermodynamic reference, so whatever sets that
offset is in Thermodynamics.jl or the ClimaParams defaults. Task 1 settles it,
and it is now the only thing standing between here and a decision on C1.

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

One command, and now the only blocker on C1.

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

  - **Which reading explains the offset.** The textbook form gives `e_int` about
    `+3.3e4` J kg⁻¹ at the DYCOMS surface state; the model's field reaches
    `−4.5e4`. If `T_0` is 273.16 and `internal_energy` still returns near
    `−5e4`, the convention differs from the textbook form and the definition is
    what to read. If `T_0` is not 273.16, that is the answer outright.
  - **The parameter's name.** The plumbing is already known to be reachable:
    `create_parameters.jl:75` builds the thermodynamic parameters entirely from
    the TOML dict and `Parameters.jl:602` forwards every field, so a config
    reaches them through the `toml:` key. **That makes the reference shift a
    configuration change, not a fork of Thermodynamics.jl.** What is missing is
    the name, and the field list gives it.
  - **Whether the shift is even constant.** `Parameters.jl:607` lists
    `e_int_v0` and `e_int_i0` as *derived* rather than as fields. If they are
    derived conventionally, moving the reference moves the latent-heat offsets
    with it and the shift becomes `ΔT·(cv_m + q_vap·R_v)` rather than `ΔT·cv`.
    The shifted parent would then be `e_tot + c(q)` and not `e_tot + c` — a
    premise both shift shapes rest on.

**The outcome forks the work.** If the offset is a convention, the shift is
legitimate, `c` must clear the tropospheric minimum at about 100 kJ kg⁻¹ on a
sphere, and the suppression cost below applies at full strength. If instead the
initialisation is wrong, then the troposphere should not be negative at all,
C1 would be treating a symptom, and C0's 43.276% is a fact about this model's
initial state rather than about the energy reference — which would mean
rereading the C0 learning entry and the memo's Part 3 source bullet. Neither was
edited, because the evidence does not force it. This command decides.

## 2. C3, the fallback reading

One batch job. It needs no code change and no approval, and after C0 it is the
most informative run left.

```bash
CONFIG=experiments/tag_closure/configs/c3_column_record.yml \
    sbatch experiments/tag_closure/runscripts/phase_c.sh
```

C3 reads the energy process record on a configuration where the source tags'
own donor rule is not running. The record measures energy *added by each process
since t = 0*, which is reference-independent and therefore immune to everything
task 1 is about. If it reads well here, the alternative that
`energy_source_tags.md` names is viable regardless of how C1 turns out, and C1
matters less than it currently appears to.

From a tcsh login shell use `env CONFIG=... sbatch ...` instead; that is the
only thing the login shell changes.

## 3. After the job: check, reduce, commit

Check the exit status rather than only the log, because a crashed solve returns
`:simulation_crashed` and the driver's non-zero exit is what makes that visible:

```bash
sacct -j <jobid> -o JobID,State,ExitCode
```

Reduce before copying anything back, because the operator residual and the
process record live in the NetCDF and the NetCDF stays on scratch:

```bash
julia +1.11 --project=.buildkite \
    experiments/tag_closure/analysis/reduce_run.jl output/c3_column_record/output_active
```

Five files into `experiments/tag_closure/output/c3_column_record/`: the family's
`*_tag_closure.csv`, the reduced tables, `<run>.yml`, `provenance.txt`, and a
trimmed `run.log`. The analysis refuses any run whose `provenance.txt` records
`commit: unknown`.

Then the phase analysis, which will draw the two-readings panel for the first
time with real data:

```bash
julia +1.11 --project=.buildkite experiments/tag_closure/analysis/phase_c.jl
```

## 4. The timing controls

Cheap, and they are what the tag-cost numbers get measured against. Nothing has
measured what the tags cost yet.

```bash
for c in a1_dt10_notags c0_column_notags; do
  CONFIG=experiments/tag_closure/configs/$c.yml \
      sbatch experiments/tag_closure/runscripts/phase_a.sh
done
```

Take `sypd` and `wall_time_per_timestep` from each log and compare with the
tagged run at the same configuration. `a1_dt10` reported `sypd 3.012` and 9 ms
per timestep.

## Downgraded, and why

**`c0_sphere_deep`, the 60 km depth control.** It was written to separate a
domain artifact from a property of the reference. `where_negative.jl` has
already answered that: the sign change is at the tropopause, not at the domain
top, so doubling the depth adds positive levels above and lowers the fraction
without changing anything physical. The docs' framing that the non-positive
parent follows from shallow domains is wrong in a specific way — **the negative
region is the troposphere**, which is where the weather is and where source
tracing is worth doing. The run is now a confirmation rather than a
discriminator. Worth doing eventually; it should not gate C1.

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
The remaining shape is a change of the thermodynamic reference constant, not an
offset added to the state; adding to the state shifts `e_int`, and therefore
temperature and pressure, which is a different atmosphere rather than a change
of reference.

One cost is now firm rather than conditional. The shift must clear the
*tropospheric* minimum, so `c` is about 100 kJ kg⁻¹ on a sphere and cannot be
made small. The discriminating part of a source tag's share is proportional to
`1/(e+c)`, so at that magnitude the donor rule is several times less
discriminating than it is today in the cells where it already works — the family
would partly succeed by becoming more like the mask-weighted energy tags it was
meant to improve on.

**A3's companion.** A3 differs from `a1_dt10` in two keys,
`microphysics_model` and `vert_diff`, so the gap between them is not the 1M
mismatch alone. Separating it cleanly needs one extra 0M column run with
`vert_diff` on. The config is deliberately not written.

## What to expect

Every script here has now run at least once on real data, `where_negative.jl`
and `phase_c.jl` both on first execution. The remaining first-time paths are the
two-readings panel with real process-record data in task 3, and the timing
controls in task 4, which take the `family = nothing` route through the loader.
Send the error rather than working around it.
