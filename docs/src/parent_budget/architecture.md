# Parent Budget: Architecture

The parent budget is an opt-in conservation audit. It checks whether air mass,
total water and total energy changed over each accepted time step by what the
accepted step applied, within a declared tolerance. It is off by default. Set
`parent_budget_mode` to `summary` or `audit` to switch it on. It writes
`parent_budget_report.yaml` and changes no model field. With it on, every model
field that exists without it stays bit for bit as in the same run with it off,
under the default solver settings. Only its own fields and output are added. The
[fork parity contract](https://github.com/johannespletzer/ClimaAtmosResiDyn.jl/blob/main/docs/clima_atmos_specific.md#fork-parity-with-upstream)
gives the limits.

This page owns the data flow and the code map. The [contract](contract.md) owns
the rules and the [vocabulary](vocabulary.md) defines the terms. The
[coverage registry](coverage.md) owns the list of paths. The
[implementation plan](plan.md) is a development record, not a rule.

Two constraints drive the design. A global integral is a collective, and a
four-stage IMEX method with dozens of instrumented paths cannot afford one per
leg. When the budget fails to close, the evidence must tell a missing leg from
a duplicated one and from a mismatched pair.

## Data flow

```
configuration ──▶ schema: what must be collected
                    │       quantities, control volumes, channels, final maps,
                    │       transfer events, reservoirs, required legs
                    ▼
per accepted step

  state Y ──▶ local accumulation (accounting precision)
  events  ──▶ applied updates, per process and stage
                    │
                    ├── endpoint slots      ┐
                    └── leg slots           ├──▶ one packed buffer, fixed layout
                                            ┘         │
                                                      ▼
                                        one global collective per step
                                                      │
                                                      ▼
                            unpack ──▶ endpoints + legs, with per-component
                                       status and evidence
                                                      │
                        ┌─────────────────────────────┼─────────────────────────┐
                        ▼                             ▼                         ▼
                  parent residual            attribution residual       transfer residual
              (endpoints vs envelopes    (envelope vs its classified   (legs of one event
               and final maps)            events)                       across a view)
```

The three residuals come from the same journal and are never combined. Each is
also checked against the schema, so a term that was expected and never recorded
is a blocked result, not a missing row. The code is in `src/parent_budget/`.

| File                                       | Role                                                                                       |
|:------------------------------------------ |:------------------------------------------------------------------------------------------ |
| `integrals.jl`                             | The three parent quantities and their local integrals.                                     |
| `schema.jl`, `coverage_registry.jl`        | What a configuration must produce, and the rows it is built from.                          |
| `reduction.jl`                             | The packet layout and the one collective.                                                  |
| `journal.jl`, `transaction.jl`             | Components, evidence and legs. The journal, the transaction and the three reconciliations. |
| `transfer_legs.jl`                         | Each transfer leg from its own quadrature.                                                 |
| `checkpoint.jl`                            | The restart transition and `ReadOnlyCallback`.                                             |
| `calibration.jl`, `kappa_calibration.yaml` | The κ table and its protocol.                                                              |
| `adapter.jl`                               | Everything that depends on the timestepper.                                                |
| `report.jl`                                | `parent_budget_report.yaml`.                                                               |

## The schema comes first

A schema built from the model configuration declares what must be collected
before the first transaction opens. It names the quantities, the control
volumes, the expected channels and final maps, and the transfer events with
their topology. It also names the modeled reservoirs, the required legs and the
components expected to be provably zero.

The journal stores what happened, and reconciliation compares the two in both
directions. A declared term that no entry covers blocks, and an entry the schema
does not declare is refused. Deriving the expected set from the entries would
let a process that never reported remove itself from its own audit. The schema
also fixes the packet layout and each slot's applicability, so a rank can tell an
inapplicable slot from an unwritten one without asking another rank.

## One journal, three parent quantities

One journal holds every leg of an accepted step. A leg carries a mass, a water
and an energy component together, because the three must stay coordinated
across a coupled exchange. One deposition event moves water out of the
atmosphere, the mass with it and the energy the water carried.

**Status and evidence are per component, never per leg.** One event can measure
energy, prove a mass zero and say nothing about water. The evidence names the
method or proof, the adapter or registry entry, and the precision and reduction
route.

Two things stay out of the summable set. A **stage observation** is a raw
before and after difference on an intermediate stage array. It has its own
structure and no projection iterates it. A **residual** has no representation
at all. It is produced by subtraction at reconciliation, so it cannot be
written into the journal as a balancing entry.

## Collection: local, then packed, then global

**Accounting precision comes first.** `Fields.local_sum` accumulates in the
element type of the expression it is given, so converting after a `Float32`
reduction recovers nothing. The conversion is part of the reduced expression, a
lazy `Broadcasted` over the field. The accumulation runs in the accounting type
and no copy is materialized.

**Local and global are separate.** `Base.sum(field)` is `local_sum` followed by
a `ClimaComms.allreduce!`, so it is one collective per call. The parent budget
accumulates locally into one number per slot, writes the numbers into a
fixed-layout buffer, reduces the whole buffer with one collective per accepted
step, and unpacks endpoints and legs from the result. Only the reduction
communicates.

**The layout is fixed.** It is computed from the schema, the hook template and
the mode, not from the order events are recorded in. Every rank builds the same
layout, a residual is reproducible, and per-step storage does not grow with run
length.

**A slot is unset, measured or not applicable.** Not applicable means the
configuration says there is nothing to write, as for the surface water of a
model with no surface reservoir. One "no value" flag would make a forgotten
measurement look like a deliberate omission. Slots start unset, and no default
value stands in for a measurement. A slot is written once, so a second write
fails where it happens. Marking a slot inapplicable is a positive act with a
configuration behind it. Reduction is refused while any slot is unset, and so is
reading one.

**The whole packet is one collective.** Values and any validity flags are
reduced together. A rank that throws on a missing slot while its peers enter the
collective hangs the run, so checks that could differ between ranks run before
the step, where the schema is identical everywhere, or after the reduction.

**What the packet carries.** In both modes it holds the endpoint slots, the
envelope slots of the three channels in every reservoir they write, and the
slots of the final maps that some configured path writes. `audit` mode adds,
per implicit stage, the solve defect, the post-implicit correction and the
folded hooks. It also adds one slot group per measured process row and stage,
one per transfer leg and stage, and one per intermediate hook firing. A channel
the schema declares but the adapter does not collect has no slot, and its
absence is a named blocker. A slot nobody writes would refuse the reduction on
every rank, which is the wrong failure for a term that is only uncollected.

**Endpoint reuse.** The closing endpoint of step `n` is the opening endpoint of
step `n+1`. The adapter reuses it, which halves the endpoint reductions. Only
the first transaction of a run or restart segment measures its opening
endpoint. Reuse gives up the continuity comparison that would catch something
mutating `Y` between the two readings. It is sound while no supported callback
mutates `Y`, which the coverage registry and the `ReadOnlyCallback` rule below
establish.

## Transactions

One transaction covers one accepted step. It opens on the finalized endpoint of
step `n`, collects legs and closes on the finalized endpoint of step `n+1`.

**The commit is atomic.** Every reconciliation is computed into temporaries and
validated before the journal is touched. Only then are the cumulative totals
advanced. A failure part way through otherwise leaves a journal that half-counted
a step.

**Ordering is deterministic.** Each recording carries an execution identity of
reservoir, channel, event, leg, step, stage and occurrence. A path that fires
several times in one step stays legible, and one that fires twice by mistake is
refused at the second recording.

**Per-step memory is bounded.** Legs are cleared on commit. `audit` mode keeps
every commit and `summary` mode keeps only the latest.

## Restarts and callbacks

A restart restores a state that no transaction produced, so the report is
segmented at every restart. The cumulative totals start again in each segment,
and the report names the restart it began from. The restoration is checked as
a zero-duration transition. The checkpoint callback runs after the parent budget's, so the
endpoint the open transaction opened on is the endpoint of the state being
written. `save_state_to_disk_func` writes it as attributes beside the model
hash. A restarted run reads them before the adapter is built, and
`initialize_parent_budget!` compares the measured state with them component by
component, exactly. The amounts are the same integrals of the same state in the
same arithmetic, so they are equal or the state changed on the way. A
difference is a change nobody accounted for, and the run is refused. A
checkpoint written with the parent budget off carries no endpoints and restarts
the history as unverified. The code is `checkpoint.jl`.

A discrete callback that writes `Y` between two transactions is also a change
nothing accounts for. With the parent budget on, a custom callback is accepted
only inside a `ReadOnlyCallback` declaration. `audit` mode reads the parent
integrals of the state before and after every `affect!`, locally and without a
collective, and a firing that moved them is an error. It does not see a change
that leaves those integrals unchanged, such as one to momentum, and it does not
wrap the callback's other functions. `summary` mode trusts the declaration. A
callback that supplies its own accounting is refused. The
[contract](contract.md) states the rule.

## The timestepper adapter

All timestepper-specific knowledge lives in `adapter.jl`. The transaction code
knows nothing about ClimaAtmos processes and the journal knows nothing about
tableaus. The adapter owns the channels and what an accepted envelope is for
each, the accepted stage weights, which hooks are folded into the effective
implicit increment, and the algebraic solve defect with its sign and weight. It
accepts unconstrained IMEX-ARK algorithms only. A `TimestepperPin` records the
`ClimaTimeSteppers` version, the algorithm and the weights, and the report
carries it. The trace test in `test/parent_budget/envelope_tests.jl` fixes the
stage construction and hook order the adapter assumes, so a change in the
stepper fails a test instead of silently changing every implicit leg.

**During the step** the adapter sits behind the `lim!`, `dss!`,
`constrain_state!`, `initialize_imp!` and `T_post_imp!` hooks as meters. They
read the state before and after each call and never write it. Position in the
step decides which call is which, never time, because the last stage and the
final assembly share the same `t`. A **hook template** gives the positions. It
is built from the tableau, the constraint cadence and the wired hooks, and it
mirrors `step_u!` of `ClimaTimeSteppers`: the limiter and DSS on each assembled
stage value, the initialiser, DSS, Newton solve, correction and post-Newton DSS
of each implicit stage with the constraint firings the cadence selects, and the
final limiter, DSS and constraint.

The meters check the stepper against the template as it runs, and one firing
more or fewer is an error. The last firing of each state-writing hook is the
final map. A post-Newton firing is folded into the stored implicit tendency and
enters the accepted update with weight `b_imp[i]/γ`. Every other firing is a
stage observation. In `audit` mode the correction hook is also where the solve
defect is measured, because the Newton-solved stage is visible there with a
matching cache. This costs one extra implicit tendency evaluation per stage.

**After the step** the adapter runs as the first discrete callback, so it reads
the finalized accepted state before any other callback. Each channel's envelope
is the sum of the stage tendencies the stepper cache holds, `T_exp`, `T_lim` and
the stored effective `T_imp`. The sum uses the cache's own tableau weights and
the step, and it is widened to the accounting type first. The endpoints,
envelopes, final maps, process rows and meter readings go into one packet and
one collective. Then the legs are recorded, the transaction is committed and the
next one opens on the closing endpoint. The callback's initialisation reads `B⁰`
after the integrator has refreshed its cache and before any other callback.

### The applied-update event

Every process that writes a parent field with a net integral the registry does
not prove zero is delimited by `open_applied_update!` and `close_applied_update!`,
under the label the registry names. The code is in
`src/prognostic_equations/applied_update.jl`. The tag families and the process
records read the event for the labels they know, and the parent budget reads it
for every label. The implicit path calls `open_parent_budget_event!` and
`close_parent_budget_event!` directly, beside the tag calls. A process added
without an event lands in the attribution residual, which is how the omission is
found.

In `audit` mode each event copies the parent tendency fields when it opens. When
it closes it integrates the positive and negative parts of what the process
added, read pointwise, so the rounding error is the size of the update and not of
the accumulated tendency. The amount is the sum of the parts and the arithmetic
magnitude is their difference. Under `parent_budget_attribution: gross` the
parts are kept beside the leg. Each stage's update enters the accepted step with
the stage's weight, `dt b_exp[i]` for an explicit channel and `dt b_imp[i]` for
the implicit one. A row whose quantities the registry proves zero, or declares
not applicable, needs no event and is booked from the registry in both modes.

The same events measure the transfer legs, in `transfer_legs.jl`. A leg that an
event isolates is that event's own total. A leg that an event lumps with others
is read from the flux field its tendency reads, and the event's total is kept
beside their sum as a check that no identity reads. A leg is never the negation
of its counterpart, so a coupled exchange whose two sides disagree fails its
cancellation. Each leg is recorded under the channel the schema applies it
through. [Coverage](coverage.md) lists which legs are which.

The adapter refuses an event whose label the registry does not know, one opened
inside another, one opened twice in an evaluation, one closed out of order and
one left open at the end of an evaluation. Outside a metered evaluation, which
covers every Newton iteration and every `summary` mode step, an event costs a
field access and a comparison. An event that did not fire at a weighted stage
leaves its row unknown, and the row blocks by name.

## The report

A successful run writes `parent_budget_report.yaml` into its output directory
and logs a short summary. `report.jl` builds it. The report is versioned. It
holds the configuration the parent budget ran under, the backend, the rank count
and the state and accounting float types. It holds the timestepper and adapter
versions, the supported-scope classification, the tolerances and where they came
from, and the restart segmentation. For every control volume and quantity it
holds the parent verdict with its cumulative totals, and the attribution and
transfer verdicts of the last accepted step, each with what blocks or fails it.
It reads the last commit and the cumulative totals and adds nothing to them.

The tolerances come from the committed κ table, `kappa_calibration.yaml`. At
setup `calibration.jl` reads the row for the run's backend, float type and rank
count, unless the caller brings its own tolerances. The protocol that fills a
row is stated in that file, and the tests re-measure the serial row. The
[contract](contract.md) defines the tolerance model.
