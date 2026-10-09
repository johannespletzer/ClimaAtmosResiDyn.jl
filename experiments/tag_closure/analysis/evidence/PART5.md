# Correction accounting: coverage and implementation design

Base: the reviewed Part 4 scorer at `f206018f4` on plan-rev2, with the
decisions of 2026-10-07. This note records the inventory before
implementation. Runtime completion and physical qualification
are separate from the offline evidence path.

## Existing writer coverage

All native water ledgers below are density amounts in kg m^-3. Energy ledgers
are density amounts in J m^-3. Output may divide by atmospheric density, so
each endpoint must be reconstructed with its own density. A native column
integral uses thickness and has kg m^-2 or J m^-2. A sphere uses volume and
has kg or J. Event totals count each stored native node once per element,
without quadrature weighting. `tag_event` counts a change above
max(1e-12,16 eps(dtype)) times the absolute value of its writer's own scale.
That scale differs by writer: the positive part for partition repair, the
updraft's q_tot for the EDMF rescale, ρq_tot for the precipitation follower,
and the water or energy total for throughput. The reader takes it as the
exported `__event_scale` array. Existing event conventions must stay named.

| Family / mechanism                                          | Writer and call sites                                                                                                                                 | Existing observations / cancellation boundary                                                                                                                                                                                                                 | Part 5 disposition                                                                                                                                                                                                          |
|:----------------------------------------------------------- |:----------------------------------------------------------------------------------------------------------------------------------------------------- |:------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |:--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Water rescale / empty                                       | `tagged_water.jl`: `_rescale_water_tags!`, `_apply_water_tag_rescale!`. Limiter and state constraint                                                  | Signed per-tag fixes. Absolute cache twin/count at each tag correction. Partition mechanisms `q_tag_led_rescale/empty`. Before/after attempt snapshot can cancel within a call.                                                                               | Retained/attempted covered. Accepted applications at stage/final maps missing.                                                                                                                                              |
| Water partition repair / net zeroing                        | `tagged_water.jl`: `_repair_water_tag_partition!`, `_apply_partition_repair!`. State constraint                                                       | `q_tag_led_repair` uses a half-gross transfer convention. `repairnet` keeps net-zeroing. Per-tag signed `led_fix`, cache leg gross/count.                                                                                                                     | Preserve transfer vs both-leg convention. Missing accepted per-tag/compartment decomposition.                                                                                                                               |
| Water precipitation follower / rescale / part repair        | `tagged_water_precipitation.jl`: `_follow_water_tag_precipitation!`, `_apply_part_follow!`, `_repair_water_tag_precip_parts!`. Limiter and constraint | N/rain/snow shifts update the existing gross twin by 2 abs(shift), but the total tag signed ledger is unchanged. Attempted mechanism snapshot can miss it.                                                                                                    | Missing accepted directed N/R/S legs. EDMF/copies with these parts currently unsupported.                                                                                                                                   |
| Water closing step in PR #146                               | PR #146, merged on main at `12377fb88` on 2026-10-07. `_close_water_tag_precipitation!`, signed `q_tag_led_close`                                     | The closing channel is absent from this base. Its signed ledger can cancel opposite rain/snow corrections before retained measurement. The decision of 2026-10-07 accepts the dedicated ledger provided the closure table sums it with the rescale's ledgers. | Unsupported on this base. Inventory only. When the channel enters this base, Part 5 checks that summation and adds `q_tag_led_close` to the intervention row (G3_PLAN 6.1.5). Do not port physics or presume zero activity. |
| Water copies repair / updraft filter                        | `tagged_water_edmf.jl`, `q_tag_led_uprepair/upfilter`, `water_upfix` cache twins                                                                      | Aggregate mechanisms and per-tag attempted cache gross/count exist. Updraft/copy compartment identity is lost after aggregation.                                                                                                                              | Conditionally active with copies. Accepted per-tag copies repair/filter missing.                                                                                                                                            |
| Water follower / negative allocation                        | `tagged_water_increment.jl`: `correct_water_tag_increment!`, `add_attempted_per_tag!`, `q_tag_inc_left/moved/negative`. Post-Newton hook              | Stage dt gamma attempted amount. Per-tag and mechanism tendency ledgers integrated into state. It is not the final b_i dt weight. Repeated Newton rate evaluations are not applications.                                                                      | Accepted weighted stage/application hook missing. Bounds and fallback counts incomplete.                                                                                                                                    |
| Water withheld negative gain / diffusion correction         | Attributed processes in `tagged_water.jl`, precipitation microphysics, leak correction. `q_tag_exp_negative*`, `led_leak*`                            | Tendency-ledger signed state/retained output. Explicitly no attempted total for repeated evaluations.                                                                                                                                                         | Conditionally active. Accepted finer source/leg activity missing. Do not classify evaluations as physical attempts.                                                                                                         |
| Water normalization of the giving pool / bounds / fallbacks | Pointwise shares, microphysics pool/fallback rules, follower guards on the giving pool                                                                | Clipped shares and guarded transfers are implemented. There is no complete per-mechanism accepted event/count inventory.                                                                                                                                      | Explicit missing channels, never zero. No PP-SUB activation without PX8 materiality.                                                                                                                                        |
| Energy repair / repairnet                                   | `energy_source_tags.jl`: `_repair_energy_source_tags!`, `_apply_energy_source_repair!`. State constraint                                              | Per-tag cache signed/gross/count and `e_src_led_repair/repairnet`, optional per-tag `led_fix`. Stage-weighted state and accepted cell-step gross.                                                                                                             | Retained/attempted covered. Accepted application decomposition missing.                                                                                                                                                     |
| Energy follower / leftovers                                 | `energy_source_tags.jl`: `correct_energy_source_increment!`, post-Newton hook, `led_inc`                                                              | Stage dt gamma attempted increments. Accepted cell-step variation of final integrated ledger.                                                                                                                                                                 | Accepted b_i dt contributions and bounds/fallback events missing. Follower remains a refinement observable.                                                                                                                 |
| Energy source applications                                  | Applied-update events of `attribute_energy_source_tags!` and `e_src_led_src_*`. Explicit/implicit tendency paths                                      | OD4 integrates abs of each partition source-tag accepted-step ledger change. Opposing sources inside a tag/step cancel. Residual/overlays/transport are excluded from OD4.                                                                                    | Preserve OD4 exactly. Finer accepted sources reported separately, no new tolerance.                                                                                                                                         |
| Energy plume bounds / zero normalization                    | Energy shares in proportion to what each tag holds, `_partition_blend_factor`, plume supply clipping                                                  | Existing typed guarded rules. No complete accepted application/count record.                                                                                                                                                                                  | Conditionally active. Unsupported measurements block completeness.                                                                                                                                                          |
| Paired precipitation                                        | Parent/tag instantaneous surface fluxes in `microphysics_diagnostics.jl` and `water_tag_precipitation_flux!`. TRMM parent-only average                | No paired same-update accepted parent/tag stage flux accumulators on this base. 0M grid/updraft pathways and 1M rain/snow need separate coverage.                                                                                                             | Production pairing missing. Strict offline signed paired application integration can be implemented without calling snapshots applied flux.                                                                                 |

`tag_throughput.jl` initializes `prev` from restored state and checkpoints
cache signed/gross/count, retained cell/column gross/events, attempts and
negative-water amount/events. Missing all old accumulators starts a warned
new segment. Partially missing is refused. Negative-water history has its
own missing-all/partial policy. Checkpoint latches are also carried by
`tag_closure_checkpoint.jl`. A new evidence consumer must distinguish segment
coverage from a whole-run zero and check every declared continued channel.

## Acceptance lifecycle and bounded implementation

The existing `parent_budget/adapter.jl` pins unconstrained IMEX-ARK hook order,
accepted b_exp/b_imp weights, dt gamma and final-map roles. It meters parent
triples, not a full tag/compartment/process decomposition. Pre-solve maps
affect later nonlinear solves and are stage observations, not independent
additive final updates. Post-Newton map contributions have b_imp/gamma.
Final-map changes have unit weight. Writer call counts and call timestamps
cannot establish these roles. General accepted tag instrumentation would need
a separately verified tag producer using that lifecycle pin. No such producer
is present, and Julia/cluster runtime verification is unavailable here.

The implemented first layer extends the existing offline manifest/readers/scorer
with a narrow applied-delta reader and analytic tests. It does not narrow the
full Part 5 objective or replace the required native runtime hooks. A receipt
names the trial/step, disposition, application and evaluation
identity, final integration coefficient and quantity before weighting. It
admits only final additive contributions, keeps rejected/superseded work
separate, and verifies the sum against the actual accepted-step ledger. Fixed
native geometry and channel/tag/compartment identity prevent spatial or leg
cancellation before absolute value. Do not retain every channel's application
arrays: process the current channel or directed pair, and the parent plus
current precipitation tag. The existing bundle reader still caches its native
fields. Do not introduce an event database or new prognostic state.

For each complete decomposition, report signed S, retained H and accepted A,
positive/negative accepted amounts, named event counts and separate trial
activity. Verify abs(S) <= H <= A with a dtype/scale-based rounding allowance,
and stronger native-cell step equality between receipt contributions and the
retained ledger. Different groupings must never share that inequality.
Directed transfer Q is reported once. Its giving and receiving leg activity is 2Q.

Completeness requires the declared scope's entire roster, accepted
step/window coverage, complete counters and checkpoint history, actual
production lifecycle evidence and consistent native arrays. The verified
producer registry is empty, so synthetic inputs and declared metadata cannot
pass the production completeness gate today. The last row of the table below
says what the gate checks.
Absent/inactive/unsupported/conditionally applicable channels remain explicit.

The scorer scores completeness in `COMMON.ACCEPTED_APPLICATION_ACTIVITY` and
reports each OD2 window's activity in `COMMON.APPLICATION_ACTIVITY.<window>`.
The window rows are reported and never pass. A zero-length window gives them
a not-applicable row. Both rows record the parent parity state beside them,
like the other intervention rows. Malformed accounting metadata is a data
failure.

Paired precipitation uses parent and every partition tag at identical accepted
application indices, coefficients, native surface, units and bounds. Report
signed downward, positive and negative amounts, with optional native sphere
area integration. Preserve instantaneous outputs. Paired fixture arithmetic
cannot substitute for the missing 0M/1M production flux producer or Part 7's
independent references for the giving pool. The paired row stays reported
accounting (WA-PRECIP). An unverified producer is a stated limitation, so
declaring paired evidence never turns that reported row into a
not-assessable one. Malformed paired evidence is a data failure.

## Boundaries and remaining runtime work

No runtime field, diagnostic, default, checkpoint, parent arithmetic,
dependency, CI, approved threshold or historical output is changed in this
scope. PP-SUB/materiality remains OD13-gated. Absolute application amounts
have no scientific tolerance. The completeness row carries a condition, not a
tolerance. For water, complete cancellation-safe accounting of applied
corrections and compartment legs is a condition of a qualified claim
(WA-GATES (a), in force since 2026-10-07). For energy, the G4 contract's
intervention row leaves the full intervention claim not assessable while
activity is missing. Complete cancellation-safe accounting is a condition of a qualified
energy claim too (WA-GATES (a) extended to energy, in force since 2026-10-08). Physical qualification, origin correctness and
propagated error bounds remain separate. The required real producer,
Float32/Float64 on/off parent bitwise parity, continuous/restarted all-channel
accounting, device/distributed checks and cost must be run in the prepared
Julia environment before the complete Part 5 obligation can close.

## Recovered runtime-hook feasibility and blockers

The exact-base adapter and its nearby tests were inspected again after the
offline review fixes. Additional source blobs were read by Git SHA, including
the applied-update event, package compatibility, parent module and implicit/
restart tests. This is source evidence, not a runtime test result.

| Required native capture             | Acceptance fact available on this base                                                                                                                                                                 | Implementation and verification still required                                                                                                                                                                                                                                                               |
|:----------------------------------- |:------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |:------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Explicit source/process application | `ExplicitMeter` obtains a stage from `HookTemplate`. `row_weight` uses the stepper cache's accepted `dt*b_exp`. `open_applied_update!` and `close_applied_update!` surround each process.              | A tag listener must read each actual per-tag source contribution before another source changes the same ledger, and retain native cells. Parent triple integrals do not contain it. An explicit source-only prototype cannot cover repair, follower, copies or implicit applications.                        |
| Implicit source and follower        | `PostImplicitMeter` distinguishes the solved-stage audit evaluation from Newton evaluations. The stored effective implicit tendency includes correction and folded maps.                               | The extra audit evaluation is an observation. It cannot be relabelled an actual Newton application. Capture the final rate/correction actually used by the accepted solve, replace superseded evaluations and reconcile its native ledger.                                                                   |
| Limiter/repair state maps           | The hook template distinguishes stage/pre-solve/post-init observations, post-Newton maps with `b_imp/gamma`, and final maps with unit weight. The last stage and final assembly can share a timestamp. | Instrument each writer before per-tag/part cancellation, carry the adapter's positional role and preserve N/R/S and grid/updraft/copy identities. Sampling cumulative attempted totals or whole-hook before/after net changes cannot recover opposite internal legs.                                         |
| Paired applied precipitation        | Parent transfer-leg capture can read modeled flux legs during selected evaluations. Tag diagnostics expose current surface fluxes.                                                                     | Parent and every partition tag need the same actual accepted application, native surface, signed coefficient and units, separately for supported 0M and 1M rain/snow paths. Snapshot rates and the parent-only TRMM average do not supply this producer.                                                     |
| Rejected trials and restart         | `commit_step!` runs after the accepted endpoint and clears step storage. Native tag checkpoints already carry retained/attempted history and latches.                                                  | The materialized adapter supplies no finalized trial/rejection IDs or rollback protocol. Add an explicit supported lifecycle for the actual solver, checkpoint every new numerator/count/latch and verify continuous versus restarted native history. Do not infer whole-run zeros from a restarted segment. |
| Production completeness gate        | Implemented, as the owner decided on 2026-10-08. The gate reads the producer's roster from its receipt, each inactive channel's arrays for zeros or marks, and each check log's named result.          | Each registry entry declares its roster key, inactive arrays and log pattern, or `register_producer` refuses it. The registry is empty, so no submission clears the gate until a producer passes its runtime validation.                                                                                     |

The parent-budget configuration guard explicitly refuses every `AbstractEDMF`.
Forcing its audit mode on for copies/TRMM would violate that declared scope.
Its internal tableau and hook-template helpers are reusable lifecycle evidence.
Its parent-only schema and measurements cannot be presented as full tag or
EDMF capture. No scope guard has been widened.

The base's `Project.toml` permits `ClimaTimeSteppers` 0.10.4 and 1, while this
materialization has no installed Julia, prepared package environment or
resolved runtime version. Therefore a runtime producer cannot yet be bound to the
actual package/cache behavior or verified locally. Native read-only meters are
feasible at the additive sites above. Wiring them to every writer requires a
tag listener and native buffers, not a manifest declaration. No runtime hook
has been installed merely on the assumption that every supported package
version, cadence, Newton path and device behaves identically.

The first execution gates for that implementation are the real stage trace and
accepted-envelope tests in `test/parent_budget/envelope_tests.jl` and the implicit
folded-map tests in `test/parent_budget/implicit_attribution_tests.jl`, followed
by the affected `tagging_water_increment`, `tagging_water_precipitation`,
`tagging_water_edmf*`, `tagging_source_increment`, `tagging_source_float32` and
restart tests. Every parent center/face/surface field must be compared by its
bits, including signed zero, with capture off/on at Float32 and Float64. The
new accumulator history, counts and latches must match continuous versus
restarted runs. Supported devices/ranks and hot-path allocations require
actual measurements. These gates are unavailable here, not recorded as passes
or model failures. Existing OD4 and retained tolerances stay unchanged.
