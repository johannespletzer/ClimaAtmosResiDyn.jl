# Common evidence validation and acceptance scoring

`score_acceptance.py` evaluates the optional `acceptance` section of the
existing submission manifest. It computes supported water and energy
metrics from named immutable artifacts and emits deterministic row results.
Each row separates applicability, data completeness, scientific verdict,
approved/proposed/reported status, reference eligibility, units, window,
normalization and remaining dependency. See [PART4.md](PART4.md) for the
reuse inventory, coverage and verification record.
The optional weighted-application path and its production gaps are recorded
in [PART5.md](PART5.md). Its offline implementation does not complete Part 5.
The independent water references, the producer of their declared
eligibility and their frozen development cases are documented in
[PART6.md](PART6.md). They do not complete physical water qualification.
The directed transfer references, the producer of their declared
eligibility and their development cases are documented in
[PART7.md](PART7.md). Actual PX14 and PX25 evidence remains unqualified.

The input is a separately identified extended manifest, not a second
submission record format. Attach a predeclared extension to an archived
manifest without changing the original:

```sh
python3 experiments/tag_closure/analysis/evidence/manifest.py \
  --attach-acceptance BUNDLE/submission.json \
  --acceptance BUNDLE/extension.json --out BUNDLE/manifest-new.json
python3 experiments/tag_closure/analysis/evidence/score_acceptance.py \
  validate BUNDLE/manifest-new.json --json BUNDLE/validation-new.json
python3 experiments/tag_closure/analysis/evidence/score_acceptance.py \
  score BUNDLE/manifest-new.json --json BUNDLE/score-new.json
```

All evidence paths in the extension are relative to the new manifest's
directory. Existing result paths are refused. Keep the original manifest,
scorer hash, score and interpretation. A corrected score is a new reanalysis,
not a simulation rerun. The legacy tools below retain their original CLIs
and historical algorithms.

## Independent water known-answer fixtures

Run the two complete frozen configurations into separate new directories
from the repository root:

```sh
python3 experiments/tag_closure/analysis/evidence/make_water_transport_fixture.py \
  NEW/analytic --config experiments/tag_closure/configs/water_transport_known_answers.json
python3 experiments/tag_closure/analysis/evidence/make_water_transport_fixture.py \
  NEW/numerical --config experiments/tag_closure/configs/water_transport_numerical_fixture.json
python3 -m unittest discover -s experiments/tag_closure/analysis/evidence \
  -p 'test_water_transport_reference.py' -v
```

Both output roots must be absent. The exit codes follow the scorer's. Exit 0
means every case's profile, prescribed exported-parent trajectory, partition
closure and wrong-origin checks passed against an eligible reference. Exit 1
records a failed fixture check. Exit 2 records missing, corrupt or
inconsistent evidence. Exit 3 records an ineligible selected reference. Its
candidate is not assessable, and no ranking or pass is inferred from it.
Exit 4 means nothing was evaluated: the output exists, the command line is
invalid or the driver raised an error. The analytic configuration has five
cases with constructed eligibility and exits 0. The numerical configuration
retains four ineligible upwind references and one eligible exchange
reference, so its expected exit is 3.

Each case directory contains the original `submission.json`, an existing-format
`extension.json` and `manifest.json`, a separate `manifest_origin_swap.json`,
the frozen design/resolved config and hashed evaluator sources, every native
rung archive, and `known_answer_results.json`. `suite_results.json` records
each case without hiding an ineligible result. All 21 numerical and 18
quadrature rungs remain available. Raw per-tag 1 h/24 h L1, specific Linf,
small/zero-tag absolute errors, parent/closure defects, conservation/boundary
accounts and executed Newton diagnostics are reported beside OD12 eligibility.

`water_transport_adapter.py` is the producing script of the declared
eligibility file. It reconstructs every archived rung from independent
equations, checks exact native faces/weights/time/dtype and
source/config/model identity, requires explicit zero arrays for excluded
processes, and measures every applicable floor in the same norm as OD3. It
then writes the producer's name and sha256, one floor per OD12 source,
`converged`, `mirrors_complete` and `jacobian_complete` into
`water_reference_evidence.json`, each with its basis. The manifest's
`reference.producer` names and hashes the same script. The scorer reads the
declaration through its own eligibility reader, unchanged, and does not
import the adapter. The driver reruns the adapter on the finished bundle,
which refuses a declaration that differs from its recompute, and requires
the scorer's reading to agree with it. Partition sums exclude source
overlays. A numerical reference's same-parent status follows actual
`rho`/`water_parent` bits, including fixed-parent inflow and exchange. Specific-profile agreement alone
cannot hide a changed prescribed parent trajectory or a broken partition sum.
The archived mutant must perform the registered origin swap while preserving
the initial state, parent and source overlays. Other origin-failing changes
do not verify that mutation.

The full production scorer continues to emit its other missing-prerequisite
rows. The driver does not manufacture those prerequisites. Its five labels
include two partition origins and overlay/tiny/zero source diagnostics. It
does not supply an eight-tag atmospheric reference or validate model parent
physics. PX1/PX8/PX7/PX11/PX24/PX12, copies' native residual/repair/mirror/
Jacobian/fallback and own-transport E gates, KI4-COPIES/UP1, accepted production
capture, physical restart/parity/device/cost and OD14 held-out evidence remain
required. The two-reservoir linear Newton test cannot establish the model's
nonlinear solver floor. Part 5's verified runtime-producer registry is empty.
No missing channel is inferred as zero outside these manufactured cases.

## Independent water-transfer fixtures

Run the two complete frozen configurations into separate new directories
from the repository root:

```sh
python3 experiments/tag_closure/analysis/evidence/make_water_transfer_fixture.py \
  NEW/transfer-exact --config experiments/tag_closure/configs/water_transfer_exact.json
python3 experiments/tag_closure/analysis/evidence/make_water_transfer_fixture.py \
  NEW/transfer-rk4 --config experiments/tag_closure/configs/water_transfer_rk4.json
python3 -m unittest discover -s experiments/tag_closure/analysis/evidence \
  -p 'test_water_transfer_reference.py' -v
```

Both output roots must be absent. The exit codes are those of the transport
fixtures above. Both configurations cover the nine cases of
[PART7.md](PART7.md) and retain 36 RK4 rungs and 28 pool diagnostic rungs.
Both exit 0. The other eight cases have eligible references, passing
candidates and verified origin controls. The zero-activity case covers no
rule by design (decision of 2026-10-09). The scorer reads its reference as
ineligible and its candidate stays not assessable. The driver counts it as
not applicable when its floors are eligible.

`water_transfer_adapter.py` is the producing script of the declared
eligibility file, as in Part 6. It reconstructs every rung, checks native
geometry, units, precision, physical times, the three compartments, the
separate rain and snow export owners, the pinned rates and the source
identities, and requires zero arrays for excluded processes. It writes
`independent_rules`, the producer's name and sha256, one floor per OD12
source, `converged`, `mirrors_complete` and `jacobian_complete` into
`transfer_reference_evidence.json`, each with its basis. The scorer reads
the declaration through its own reader and does not import the adapter.

The candidate's declared convention is the exact integrated interval. Its
application list is empty, and the reader rebuilds one applied mean share
per edge and interval from the native cumulative amounts. Water amounts must
reproduce the pinned rates. Endpoint changes must reconcile with the directed
amounts, and each edge's applied partition labels must sum to its applied
water. Each case's control keeps the totals and fails an origin row: a wrong
donor in the one-way case, an erased exchange in the opposing case, an
owner reset in the sedimentation case and an origin permutation in the
other six. Zero transfer activity is not donor-rule coverage.

The sedimentation case stores instantaneous upward-positive precipitation
apart from the exact integrated exterior amounts. Synthetic paired parent and
tag interval rates share the same accepted application, and Part 5's reader
checks them. The paired row stays reported accounting (WA-PRECIP). A
synthetic receipt cannot populate the empty verified-producer registry.

The [PX25 draft](../../configs/part7_px25_draft/README.md) is written by
`save_px25_draft` and is a draft pending the owner. A test checks that the
committed files are its output.

## Minimum evidence layout and extension

```text
BUNDLE/
  submission.json           # original manifest.py output
  extension.json            # acceptance schema_version: 1
  manifest-new.json         # original fields plus acceptance extension
  resolved.yml / TOML / Manifest / machine records
  candidate.npz or explicit native NetCDF/CSV artifacts
  reference.npz / reference-submission.json / reference-eligibility.json
  untagged.npz / untagged-submission.json
  exact checkpoint artifacts and segment records, when used
```

The extension records these fields:

| Field | Meaning |
|:--|:--|
| `artifacts` | Map of every named bundle-relative artifact to its SHA256. Hashes prove identity, not physical sufficiency. |
| `experiment_commit`, `scorer_commit`, `planning_commit` | Keep experiment/config, analysis implementation and planning-tree identities distinct from original `head_sha`. An unpublished scorer uses `local-uncommitted` plus exact file hashes. `planning_commit` is recorded information. The scorer does not verify it. |
| `scorer_files`, `approved_numbers_sha256` | Exact scorer file hashes and the sha256 of the scorer's named approved numbers as a stable table, as returned by `local_identities()`. A changed approved number invalidates the manifest. An edit to the planning files, DECISIONS.md included, does not. |
| `submission_files` | Original config and recorded environment/untracked names mapped to archived artifacts. Hashes must match submission identities. |
| `resolved_settings`, `precision`, `process_count` | Declared solver, seed, physics, diagnostics, tag definitions and environment scope. Do not fill unavailable legacy facts with guesses. |
| `claim`, `case`, `geometry_kind`, `end_seconds` | Family (`water`, `energy_source`, `radiation_record`), declared use, native column/sphere geometry and physical duration. No count/time/device scope promotion. |
| `pilot_first_hour` | `true` declares the TRMM 0M 6 h pilot (2026-10-07): a water run that ends after 1 h and before 24 h. Only the first-hour origin rows are scored, labelled low power. The 24 h origin rows are not applicable, and closure and the named remainder are reported at the run's end. |
| `excluded_criteria` | Criteria the owner excluded for this `case`, such as `[5, 6]` on D4-W under option D. The scorer accepts only approved exclusions and makes every row of those criteria not applicable. Any other declaration fails the evidence row. |
| `runs` | Candidate/reference/untagged field inventories. Reference/untagged runs name separately hashed submission manifests and matching model/config identities. |
| `tags`, `compartments` | Named kind (`region`/`source`) and partition membership. Source overlays never enter pure-region closure. Compartments are `total` or complete `N,R,S`. |
| `required_parent_fields`, `parent_capture_scope` | Frozen required-state inventory. `exported` parity is reported but cannot pass full parent parity. `all-state` requires the actual complete capture inventory from the relevant model setup. |
| `accepted_step_seconds`, `throughput_accumulation` | Step cadence for deriving cell-step ledger variation. Exact stored Θx identifies `accepted_step` accumulation independently of output cadence. |
| `reference`, `active_rules` | Named, scope-specific eligibility artifact and its `producer` (`script` and `sha256`). The file names the same producer and declares tested independent rules, convergence, `floors` with one entry per OD12 source (`source_injection`, `initialization`, `parent_solve`, `contamination`, `reference_discretization`), active mirrors/Jacobian and copies refinement. A single scalar floor or a missing producer fails the eligibility row as a data failure. The row records "eligibility as declared by <producer> <hash>". Active-rule coverage is reported and gates nothing until OD9. |
| `record_processes`, `expected_record_processes` | Complete predeclared process roster. A missing active record cannot be silently skipped. Duplicate process names are rejected. |
| `correction_accounting` | Versioned required-channel/coverage table, finalized trial receipt, native application arrays and optional directed leg pairs. Missing/unsupported channels remain explicit. |
| `precipitation_applications` | Paired parent and every partition tag at identical accepted applications/weights/bounds/native surface. Signed fluxes are integrated before cancellations. |

A field descriptor names `path`, `key`, `units`, `representation`, `sampling`,
`dimensions` (native dimensions excluding time), and `weight_units`.
It also declares an output `cadence` or exact `expected_times` (interval
fields may instead supply contiguous bounds). Missing/extra samples cannot
be hidden by taking a common prefix.
Native NPZ exports include `time`, `time_units="s"`, `geometry`, `weights`,
`weight_units`, and each field's embedded `KEY__units`, `KEY__representation`,
`KEY__sampling`, `KEY__dimensions`. Arrays have time first, then native cells.
Scalar integrated amounts use one weight of 1 and `weight_units="1"`. Extra
geometric weighting is rejected. The required 1 h and 24 h origin rows remain
present even when an optional `profile_times` list is empty.
Alternative time/geometry/weight keys may be explicitly named.

Existing NetCDF reading uses named dimensions, finite unmasked values, exact
physical-second time units, native coordinates and a named native weights
variable. It requires the verifier environment's existing `netCDF4`. No
dependency is added here. A remapped sphere grid cannot replace native
volume integrals. There is no implicit centre/face reconstruction, remapping,
interpolation, extrapolation or common-prefix truncation.

CSV scalar columns name a pinned `metadata_source` for their units and
sampling convention. Do not relabel a rate as an amount. Interval averages
also name exact contiguous bounds. Cumulative scalar gross fields name
their `accumulator_kind`. Ratios are not cumulative amounts. Paired
precipitation is integrated only from applied-flux interval averages or
accepted applied accumulators. Hourly snapshots remain instantaneous reports.

`segments` in a run declare unique IDs, parent ID, input/output checkpoint
SHA256 and their corresponding `_artifact` paths, per-field artifact
overrides, cadence and accumulator continuation/reset metadata. Shared
endpoint values must agree exactly before deduplication. A reset amount or
density accumulator requires an explicit native-cell offset. Reset specific
ledgers must be reconstructed to density before stitching. Attempted and
retained fields remain distinct. A reader test does not prove model restart
equivalence.

## Weighted applications and cancellation

For one fixed mechanism/tag/compartment and native volume, signed window S is
the integral of the endpoint ledger difference. Retained H sums the absolute
native-cell ledger changes at every accepted step. Accepted A sums absolute
weighted native-cell contributions at every accepted application. Absolute
value precedes cells, applications and compartments for A. A complete additive
decomposition satisfies abs(S) <= H <= A up to a reported rounding allowance.
The reader also matches every native-cell accepted-step sum to the real ledger,
reconstructing density times specific output at each endpoint. That consistency
allowance is not a scientific activity tolerance.
It uses per-step/native-cell quantities with the same density units and the
least precise native dtype, including the sum of absolute weighted
contributions before cancellation. This covers native addition roundoff
between opposing stages. An unrelated dense cell or atmospheric density
cannot enlarge another cell's correction allowance.
Below the native normal range, the allowance also includes the local loss
when a weighted contribution rounds to its native dtype. Specific-ledger
export has a separate half-subnormal quantum at each endpoint, converted to
density units with that endpoint's density. Density ledgers receive no export
floor. Exact all-zero input still has zero allowance, and an omitted
representable subnormal update into a zero density ledger is rejected.

An application is a final additive contribution with its integration weight.
The receipt pins `unconstrained_imex_ark`, `ClimaTimeSteppers` version,
`b_exp`, `b_imp` and `implicit_diagonal`. Explicit/implicit tendency weights
are dt times the corresponding accepted b coefficient. Post-Newton map
increments use b_imp/gamma. Final accepted maps have weight 1. Nonadditive
pre-solve stage observations are refused. A distinct final evaluation ID must
replace repeated Newton evaluations. Rejected/superseded evaluations cannot
enter A. `attempted_coefficient` is optional: supply it only for an actual trial
update. An unweighted tendency evaluation has no physical attempted amount.

The extension uses this shape inside the existing `acceptance` object:

```json
{
  "correction_accounting": {
    "schema_version": 1,
    "required_channels": ["fix.pbl.total", "negative.pbl.total"],
    "receipt": "application_receipt.json",
    "coverage": [
      {"id": "fix.pbl.total", "mechanism": "fix", "tag": "pbl",
       "compartment": "total", "status": "observed",
       "ledger": "application_ledger_fix_pbl_total",
       "applications": {"path": "applications.npz", "prefix": "fix_pbl_total",
                        "quantity": "water_increment", "units": "kg m^-3"}},
      {"id": "negative.pbl.total", "mechanism": "negative", "tag": "pbl",
       "compartment": "total", "status": "missing", "reason": "no accepted producer"}
    ]
  }
}
```

The required roster is the declared accounting scope. It must cover every
active mechanism/tag/compartment needed for the claim, not a convenient subset.
It is checked against the runtime validation's active-roster evidence before a
production completeness pass. `inactive` requires a reason and pinned evidence.
`unsupported`/`missing` block completeness and never receive a zero. Every
observed channel must have an applied record at every accepted step, including
an explicit measured zero. Empty rosters cannot pass.

The receipt has `schema_version: 1`, `semantics:
"weighted_final_additive_updates"`, `kind: "runtime_capture"` or `"synthetic"`,
the model commit and dirty-diff SHA256, the integrator pin, and a `steps` list.
Each step names its unique ID, start/end seconds, exactly one `accepted_trial`,
all finalized `trials` (`accepted`/`rejected`), and its `applications`.
Each application names `channel`, unique `record_id`, `trial`,
`application_id`, `evaluation_id`, `disposition`
(`applied`/`rejected`/`superseded`), `role`, final `coefficient`,
`coefficient_units` (`1`/`s`), and stage where needed. Bounds must be contiguous
and exactly match the complete accepted-step ledger, never hourly interpolation.

An NPZ application artifact contains `weights`, `geometry`, `weight_units`
and, for each prefix, `PREFIX__values` (native Float32/Float64 record x cell),
`__record_ids`, embedded `__quantity`/`__units`, native `__event_scale` and
integer arrays `__fallback`, `__bound`, `__clamp`, `__zero_normalization`.
Missing counters are data failures. Values are density increments or density
tendencies as explicitly named. Final coefficients are applied before absolute
value. The event convention is a stored native node per element per weighted
application above max(1e-12,16 eps(native dtype)) times the absolute value of
`__event_scale`, the writer's own scale. That scale differs by writer, as
[PART5.md](PART5.md) lists.
Existing retained cell-step and attempted cache-count conventions stay separate.

Optional `directed_transfers` pairs name an `id`, a `donor` channel (the giving
leg) and a `receiver` channel.
The reader requires identical applications/native cells and equal opposite
legs. It reports transfer Q once and summed leg activity 2Q. Aggregate signed
closure is never used as a substitute for either amount or an origin bound.
Fine energy sources remain separate from OD4's accepted-step partition source
variation. No retained tolerance is transplanted onto A.

For `precipitation_applications`, use `schema_version: 1`, a receipt,
`channels` keyed by `parent` and every partition tag, and
`sign_convention: "upward_positive"`. Each channel descriptor names a native
`precipitation_flux` in kg m^-2 s^-1. Identical parent/tag application/evaluation/
trial/coefficient identities are required. Column amounts use one unit-weighted
surface. Native sphere amounts use m^2 area weights. Signed downward, positive
downward and negative downward amounts are reported separately. Instantaneous
precipitation diagnostics remain available. No reference for the giving pool
or precipitation accuracy tolerance is supplied by this arithmetic. The row
stays reported accounting. An unverified producer is a stated limitation and
never turns the row into a not-assessable one.

Production completeness additionally needs a pinned `lifecycle_evidence`
artifact of kind `runtime_validation`, exact model/diff identity, producer
source, and PASS checks with commands/environment/hashed logs for accepted
weights, rollback, Newton replacement, complete active roster, parent bitwise
parity and all-channel checkpoint/restart. The producer ID, source hash and
timestepper version must match the implementation's verified-producer
registry. The gate then reads the producer's own output, as its registry
entry declares:

  - the roster: the producer writes the channels it instrumented into its
    receipt under the entry's `roster_key`. That roster must equal the one the
    reader evaluated. A roster in the submitted manifest or proof is not read.
  - inactive channels: each one's evidence file must hold
    `<channel>__<values>` with every entry an explicit zero, or
    `<channel>__<mark>` with every entry 1, or both. Its hash alone is not
    enough. The channel ID's dots become underscores.
  - check logs: each check's log must record the check by name as PASS,
    read with the entry's `check_log_pattern` (groups `check` and `result`).
    A log that is merely present, or that names the check otherwise, is
    refused.

`register_producer` refuses an entry without these three declarations, and
the gate refuses such an entry too. The registry is empty, so no submission
clears the gate today ([PART5.md](PART5.md)).

The scorer scores completeness in `COMMON.ACCEPTED_APPLICATION_ACTIVITY` and
reports each window's activity in `COMMON.APPLICATION_ACTIVITY.<window>`, a
reported row that never passes.

The cancellation example is reproducible and separate from all historical runs:

```sh
python3 experiments/tag_closure/analysis/evidence/make_correction_fixture.py /tmp/correction-example
python3 experiments/tag_closure/analysis/evidence/score_acceptance.py \
  validate /tmp/correction-example/manifest.json --json /tmp/correction-example/validation.json
python3 experiments/tag_closure/analysis/evidence/score_acceptance.py \
  score /tmp/correction-example/manifest.json --json /tmp/correction-example/score.json
python3 -m unittest discover -s experiments/tag_closure/analysis/evidence -p test_correction_accounting.py -v
```

Every hour applies +1 and -1 in each of two unit-thickness cells. Over 24 h
S=0, H=0 and A=96 kg m^-2. Production completeness stays NOT ASSESSABLE.
Scoring exits 3 for the remaining scientific gates. No simulation is run.

## Reproducible analytic example and tests

These commands create a **synthetic fixture**, with separate candidate,
reference and untagged artifacts. They do not run ClimaAtmos:

```sh
python3 experiments/tag_closure/analysis/evidence/make_acceptance_fixture.py /tmp/acceptance-example
python3 experiments/tag_closure/analysis/evidence/score_acceptance.py \
  validate /tmp/acceptance-example/manifest.json --json /tmp/acceptance-example/validation.json
python3 experiments/tag_closure/analysis/evidence/score_acceptance.py \
  score /tmp/acceptance-example/manifest.json --json /tmp/acceptance-example/score.json
python3 -m unittest discover -s experiments/tag_closure/analysis/evidence -p test_acceptance.py -v
```

The example has genuine calculated PASS rows for exact water closure, tag
norms, comparator checks, parent parity and ledger ratios. It also reports:

```text
COMMON.SCOPE_APPROVAL: NOT ASSESSABLE / COMPLETE
  qualification stays at eight tags on the approved rows (WA-SCOPE)
COMMON.ACCEPTED_APPLICATION_ACTIVITY: NOT ASSESSABLE / COMPLETE
  missing accepted application/leg accounting
WATER.PRECIP_INTEGRATED.established: NOT ASSESSABLE / DATA FAILURE
  snapshots are insufficient for paired integrated precipitation
qualification: NOT QUALIFIED, exit 3
```

The precipitation data gap is outside this inventory-only fixture's required
claim, so its scientific blockers select exit 3. The exit codes:

| Exit | Meaning |
|:--|:--|
| 0 | No required row failed or is blocked. A score cannot reach it today: the convergence, refinement, accepted-application, restart, held-out and scope rows stay blocked until their parts deliver. Validation exit 0 means bundle integrity only. |
| 1 | A measured required approved row failed. |
| 2 | Required evidence is missing, corrupt or inconsistent. A water row with a data failure fails, labelled DATA FAILURE, and so does the evidence row. An energy row with absent data is not assessable (G4 section 5). |
| 3 | A required scientific approval, reference or prerequisite is unavailable. Failed or exported-only parity blocks the origin rows only. Closure and intervention rows are scored with `parent_parity` recorded. A missing or zero-length OD2 window is not applicable and blocks nothing. |
| 4 | Nothing was evaluated: the result path exists, the command line is invalid, or the scorer raised an error. A scorer error is not a data failure. |

Required failures are never averaged across tags/windows. Proposed
thresholds and reported-only quantities never become scientific passes.

## Converting model output: convert_output.py

`convert_output.py` builds the bundle that the scorer reads from a run's
output directories. Each directory is one `output_XXXX`: the NetCDF files the
model wrote, the merged config `*.yml`, `provenance.txt`, the closure and
audit tables, and the `manifest.json` from `manifest.py`.

```sh
python3 experiments/tag_closure/analysis/evidence/convert_output.py --family water \
  --candidate RUNS/default/output_0000 --reference RUNS/copies/output_0000 \
  --untagged RUNS/untagged/output_0000 --period 30m --pilot-first-hour --same-parent \
  --planning-commit SHA --scorer-commit SHA [--git-repo CLONE] --out NEW_BUNDLE
python3 experiments/tag_closure/analysis/evidence/score_acceptance.py \
  score NEW_BUNDLE/manifest.json --json NEW_BUNDLE/score.json
```

The candidate's submission manifest becomes the bundle's record, with the
`acceptance` extension added. The fields go into `<role>.npz` bit for bit,
time first. `conversion.json` (also `acceptance.conversion`) lists each
logical name with its model variable and whether it resolved, and pins the
converter's and the name table's hashes. The tags come from the candidate's
config. The reference must list the same tags. `--git-repo` reads a
submission file from git at the submission commit when its worktree is gone.
It is kept only if its hash matches the record.

**Weights.** A column's weight is the cell thickness Δz in m. The faces are
rebuilt from the `z` centres, `z_f[0] = 0` and `z_f[k+1] = 2 z_c[k] - z_f[k]`,
as `compare_runs.py` does. The top face must match the config's `z_max` to
1e-9. The density enters through `rho`, which the scorer multiplies in, so
the integrand weight is ρ Δz (ρ_ref Δz at a profile row, G3_PLAN 6.1.1).
A table column is already a domain integral and has one unit weight. A
sphere needs a native cell-area variable in the output (`cell_area` in m^2).
Its weight is then area × Δz in m^3.

**The name table.** `<tag>` is each configured tag, `<process>` each entry of
`energy_process_record`. Native fields are on the model's levels with Δz
weights. Table columns and surface fields are column scalars with a unit
weight. Amounts are kg m^-2 or J m^-2 on a column, and kg or J on a sphere.

| Logical name | Model variable | Units | Native geometry | Weight source |
|:--|:--|:--|:--|:--|
| `rho` | `rhoa` | kg m^-3 | levels | Δz |
| `water_parent` | `hus` | kg kg^-1 | levels | ρ Δz |
| `temperature` | `ta` | K | levels | Δz |
| `tag_<tag>` (water) | `q_tag_<tag>` | kg kg^-1 | levels | ρ Δz |
| `parent_R`, `parent_S` (rain and snow key) | `husra`, `hussn` | kg kg^-1 | levels | ρ Δz |
| `tag_N_<tag>`, `tag_R_<tag>`, `tag_S_<tag>` | `q_ntag_<tag>`, `q_rtag_<tag>`, `q_stag_<tag>` | kg kg^-1 | levels | ρ Δz |
| `led_fix_<tag>`, `led_inc_<tag>` (water) | `q_tag_led_fix_<tag>`, `q_tag_led_inc_<tag>` | kg kg^-1, cumulative | levels | ρ Δz |
| `led_fix_<tag>_applicable`, `led_inc_<tag>_applicable` | same columns of the audit table | 1 | column scalar | one |
| `negative_water_void` | `negative_water_void`, water closure table | 1 | column scalar | one |
| `repair_retained`, `repair_attempted` (water candidate) | `led_repair_retained`, `led_repair_attempted`, water audit | amount, cumulative | column scalar | one |
| `repair_retained`, `repair_attempted` (copies reference) | `led_uprepair_retained`, `led_uprepair_attempted`, water audit | amount, cumulative | column scalar | one |
| `precip_parent`, `precip_<tag>` (partition) | `pr`, `pr_tag_<tag>` | kg m^-2 s^-1 | surface | one |
| `tag_<tag>` (energy) | `e_src_<tag>` | J kg^-1 | levels | ρ Δz |
| `residual` | `e_src_res` | J kg^-1 | levels | ρ Δz |
| `led_src_<tag>`, `led_fix_<tag>`, `led_inc_<tag>` (energy) | `e_src_led_src_<tag>`, `e_src_led_fix_<tag>`, `e_src_led_inc_<tag>` | J kg^-1, cumulative | levels | ρ Δz |
| `source_partition_valid` | `source_partition_valid`, energy closure table | 1 | column scalar | one |
| `throughput` (Θx) | `source_throughput`, energy closure table | amount, cumulative | column scalar | one |
| `repair_retained`, `repair_attempted` (energy) | `led_repair_retained`, `led_repair_attempted`, energy audit | amount, cumulative | column scalar | one |
| `record_<process>` | `e_prc_<process>` | J kg^-1, cumulative | levels | ρ Δz |
| `export_<name>` | every other instantaneous field that is not a tag's | as written | as written | Δz or one |

The audit's `*_retained` and `*_attempted` amounts are taken only where its
`ledger_cadence_step` is 1 at every row, so they are exact per accepted step.
The `export_<name>` fields, with `rho`, `water_parent` and `temperature`, are
the exported parent fields compared bit for bit with the untagged twin
(`parent_capture_scope: exported`).

No model variable holds these, so they are always recorded as missing:
`parent_N`, the water `copy_residual` (`q_tag_copy_res` is per unit mass of
updraft air), `named_remainder`, `energy_parent`, `newton_error`,
`process_amount` and `process_share`.

**What it refuses**, writing nothing: a config other than `column` or
`sphere`, topography other than `NoWarp`, a non-positive rebuilt thickness, a
top face that differs from `z_max`, native fields with different `z`, a
sphere without a native cell-area variable, a deep-atmosphere sphere, several
output periods without `--period`, a run without `manifest.json` or with
other than one `*.yml`, a candidate without tags, and a reference with
different tags. An existing `--out` exits 4.

**What it does not do.** A missing file, column or variable, wrong units or
fill values are recorded as missing with the reason. The field is left out of
the bundle, never zero-filled, so the scorer names it as a data failure. The
converter does not interpolate, sum cells, derive differences, or stitch
restart segments. It exits 2 when anything is missing and 0 otherwise.

`test_convert_output.py` checks the table row by row, the bit copies, the
weights on a stretched column and a sphere, each refusal and the named
failures on synthetic runs. It also converts archived real output, W58's
TRMM 0M pilot and E87's D4 process budget, when present
(`TAG_CLOSURE_OUTPUT_ROOTS` overrides where it looks), and skips with the
reason otherwise. On both, the rebuilt Δz reproduce the model's own column
integrals to 1e-15.

## The part 8 pilot: part8_pilot.py

`part8_pilot.py` is the glue of the TRMM 0M 6 h baseline
([design](../../design/PART8_BASELINE.md), [record](PART8.md)). It uses the
converter and the scorer unchanged and adds no threshold. It imports every
limit from `score_acceptance.py`, or from `closure_verdict.py` as the scorer
does.

```sh
python3 experiments/tag_closure/analysis/evidence/part8_pilot.py w58 \
  experiments/tag_closure/output/g3base/data experiments/tag_closure/output/g3base/g3base_scores.csv
python3 experiments/tag_closure/analysis/evidence/part8_pilot.py od2 TWIN/output_0000 --period 10m
python3 experiments/tag_closure/analysis/evidence/part8_pilot.py tables RUN/output_0000 default --json T.json
python3 experiments/tag_closure/analysis/evidence/part8_pilot.py rank --mode default \
  --score BUNDLE/score.json --tables T.json --newton 4.10e-3 --newton-source "FINDINGS W57, prior" --out RANK.csv
```

`w58` recomputes W58's TRMM rows R4, R5 and R8 from the closure and audit
tables with `g3base_score.py`'s arithmetic. On the repository's tables it
reproduces all 18 recorded rows bit for bit and exits 0. With `--prefix p8`
it reads the rerun's tables from each run's `output_0000` under the output
root and lists each row that differs, with exit 1. A missing input exits 2.
`od2` reads OD2's boundary on the untagged twin at a named output period.
`tables` writes one run's table rows with the limit ID each cites. `rank`
builds one mode's ranked table of error terms from the scorer's JSON and the
table rows. Its rule is the design's section 7. A term the scorer marks NOT
ASSESSABLE, such as a first-hour origin before PX12, is listed without a
rank.

`test_part8_pilot.py` checks the reproduction and that a changed value or
verdict is found, the table rows and the OD2 reading on hand-made runs, the
ranking on hand-made inputs, the trio's configs against W58's and the cost
table in `submit_wp9.sh`. It runs copies of both job scripts beside stubs,
so the sbatch lines and the dry-run default are checked without Slurm. Its
last tests read W58's output where it is present, and skip with the reason
otherwise. The scorer-level W58 test is `test_w58_pilot_first_hour` in
`test_convert_output.py`.

## Legacy G3 phase 1 evidence pipeline

Four standalone tools (`compare_runs.py`, `test_compare_runs.py`,
`manifest.py`, `inventory.py`), built for G3_TODO.md phase 1, items 1.1-1.5,
then extended for G3 WP0 (`review/agent_reviews/phase1_tools_review_2026-09-23.md`)
to cover the water family, B1/B2's mutation-testing and non-finite-value
gaps, and S1-S5/S10's should-fix findings. Background:
`../../reference/untapped-potential-assessment-extended.md`, "New insight
D" — the old comparator, `../increment/tag_correctness.py`, picks the latest
`output_0*` by glob, compares only the common-length prefix of `ta` and
`rhoa`, takes the reference's time index for both runs without checking
timestamps, and calls `np.array_equal` "bit for bit" although it does not
see a signed-zero difference. `compare_runs.py` replaces it; the old script
is left in place, untouched, for its own callers.

All four need `python/3.12` (numpy, netCDF4, stdlib only):

```sh
source $MODULESHOME/init/zsh
module load python/3.12
```

## compare_runs.py

```sh
python3 compare_runs.py --reference DIR --run DIR [--hours 1,6,12,24] \
                         [--tags rad,sfc,...] [--parent ta,rhoa,...] \
                         [--family water|energy] [--expect-parity] \
                         [--allow-missing NAME ...] [--judge] \
                         [--bitwise-tags] [--closure-remainder-fields NAME,...] \
                         [--ladder-share] [--parity-only] [--json PATH]
```

`DIR` must be an explicit `output_XXXX` directory (an absolute or relative
path to one). `output_active` and a bare run root (e.g. `v3_upd_default`
itself) are both refused: either can point at a different run, and a
different code version, tomorrow. See `e73_reproduction.txt` for a real
demonstration of that hazard against the old script's glob. `--reference`
and `--run` resolving to the same directory is refused too (S2 of the
phase-1 review).

Checks, each failure exiting nonzero and naming the variable and the
problem:

  - (a) every requested variable's file exists in both runs (default tags:
    every tag listed in the reference's own merged-YAML tag block --
    `energy_source_tags` or `water_tracers`, per `--family`, see below --
    excluding the ledger entries; `rhoa` is always required too, since the
    weights need it even when `--parent` leaves it out of the parity
    report; `--judge` also requires the family's total field, `hus` for
    water);
  - (b) `time` and `date` are exactly equal, and their `units` attributes
    (the epoch) agree. If the two runs have different lengths, this fails
    unless `--hours` was given on the command line *and* every requested
    hour is present in both runs at exactly `h*3600` seconds — only then is
    the common-length prefix compared, with an explicit `NOTICE:` line.
    `--hours` accepts a fractional hour (e.g. `0.1` for a 360s output, the
    V-W0a 2h configs' cadence), matched at exactly `h*3600` s like a whole
    hour; a whole-number entry still parses to a plain `int`, so existing
    JSON keys, the printed table and every existing caller are unchanged;
  - (c) `z` is exactly equal, and its `units` agree (its dimension is found
    by name, never by position, so a file with dimensions written
    `(time, z)` is still read correctly);
  - (d) the column geometry (dimensions `z` + `time`, or `time` alone for a
    surface field such as `pr`) is supported; anything else is refused as
    "unsupported geometry";
  - (e) every value read for a compared field is finite and is not the
    variable's `_FillValue` (or netCDF's default fill for its dtype) --
    B2 of the phase-1 review. A run that blew up, or was cut short
    mid-write, is refused by name, dimension names and index, not silently
    averaged into an L1 of `1.8e33` or a `nan` that a naive budget check
    (`L1 > 0.02`) would let through. `--json` writes with `allow_nan=False`
    as a second line of defence.

Two kinds of report follow. Parent-state parity is not a hard failure by
itself unless `--expect-parity` is given; per-tag metrics are always
reported, and `--judge` turns them into a pass/fail verdict.

**Parent-state parity (S1).** The default set is the *union* of both runs'
variables, excluding tags, process records and the derived `qv_tag_`/
`pr_tag_` diagnostics (`q_gas_`, the passive tracer, is **kept**, since it
must be bit for bit like any other model field) -- `--parent` overrides. A
variable present in only one run is now a **hard failure**, naming it,
unless listed with `--allow-missing NAME` (repeatable): the old
intersection-based default silently compared fewer fields than it looked
like, with exit 0. Each variable is compared **bit pattern by bit pattern**:
same dtype and shape required, then `a.view(uintN) == b.view(uintN)`
element-wise (`uintN` matches the dtype's own width, e.g. `uint64` for
`float64`). This is what "bitwise identical" means throughout this
pipeline: not `==`, which treats `+0.0` and `-0.0` as equal and so cannot
see the difference. For each variable the report gives:

  - `bitwise identical`, or
  - the count of differing elements out of the total,
  - the largest absolute difference (`max|Δ|`),
  - the largest relative difference among elements where the reference is
    nonzero (`n/a (ref zero)` if the reference is all zero there),
  - how many of the differing elements are **signed-zero-only**: the bit
    patterns differ, but both values equal zero (i.e. one is `+0.0`, the
    other `-0.0`),
  - whether plain `np.array_equal(a, b, equal_nan=True)` would have called
    the pair equal (it does, for a signed-zero-only difference — that is
    exactly the old script's blind spot).

`--expect-parity` makes *any* parity break a hard failure (exit nonzero),
for a pair that claims bitwise agreement (e.g. criterion 3's default-vs-tags
pair). Without it, a break is reported, not fatal -- the intended use for a
pair that legitimately differs, such as `w0a_0m_newton1` vs.
`w0a_0m_newton10` (Newton count only).

**Pairing (S2).** Both runs' `provenance.txt` (if present; a `NOTICE` if
not) are read and recorded in the JSON. `--expect-parity` also refuses the
pair outright, naming every mismatch, when: `machine` or `ntasks` differ
between the two `provenance.txt`s; `FLOAT_TYPE` differs between the two
YAMLs; `use_krylov_method` or `use_newton_rtol` is `true` in either YAML
(breaks the bitwise-parity contract by construction); or any top-level YAML
key differs outside an explicit allowlist (the mode key
`energy_source_tag_updraft_copy`/`water_tag_updraft_copy`, `diagnostics`,
`output_dir`, and `toml`, which is instead compared by the sha256 of the
files it names, since each run's own parameter-file path differs by
construction). Without `--expect-parity` these are `NOTICE:` lines, not
failures -- a Newton-count pair like `w0a_*` legitimately differs there.

**Per-tag, per-hour metrics.** Weights are `w_k = ρ_ref,k · Δz_k`: the
reference's own `rhoa` at that hour, for both runs (stated explicitly in the
printed output). `Δz` is rebuilt from the `z` cell centres as faces,
`z_f[0] = 0`, `z_f[k+1] = 2 z_c[k] - z_f[k]`; a non-positive resulting
thickness, or a top face that disagrees with the run's own YAML `z_max` by
more than a relative `1e-9` (skipped with a notice if the YAML has no
`z_max`), is a hard failure. For each tag and hour:

  - `integral_ref` = Σ `e_ref` `w` — the reference's own column integral,
    not a difference;
  - `integral_run_ref_weighted` = Σ `e_run` `w` -- the run's field
    integrated with the **reference's** weights, named for what it is
    (S3): when `rhoa` is not bitwise identical between the two runs (they
    do not share one atmosphere -- the ladder, a Float32 twin, a restart
    pair), a `NOTICE:` says so and `integral_run_own_atmosphere` (Σ `e_run`
    · `ρ_run,k Δz_run,k`) is added alongside it;
  - `rel_integral_change` = `(integral_run_ref_weighted - integral_ref) /
    integral_ref`;
  - `L1_mass_weighted` = Σ`|Δe| w` / Σ`|e_ref| w` — a mass-weighted mean
    relative error, not a plain column mean;
  - `Linf_peak_normalized` = `max|Δe| / max|e_ref|` — the largest pointwise
    error over the reference's largest value, not a maximum pointwise
    relative error;
  - `max_abs_error` = `max|Δe|` (pointwise, not mass-weighted);
  - `abs_L1` = Σ`|Δe| w` (R4) -- the absolute form the small-tag budget uses.

Where the reference is identically zero at that hour (e.g. `mp` in the D4
configs, which is always zero), the ratio metrics have no defined value: the
table prints `ref zero (run zero|nonzero)` instead of a stray `0` or `NaN`.
`integral_ref`, `abs_L1` and `max_abs_error` are still printed as real
numbers in that case — they do not depend on dividing by the reference.

**Units and the tag list (S4, S5).** Every compared variable's `units`
attribute must agree between the two runs (a tag's units are also checked
against its family's expected unit -- `kg kg^-1` for water, `J kg^-1` for
energy -- with a `NOTICE`, not a hard failure, if they do not, since a
config could legitimately change it). The tag list, and which tags are
region tags vs. source tags (R2: a tag's YAML entry has a `region` key, a
`source` key, or both -- both counts as a source tag), comes from the
reference's own merged-YAML tag block, and the two runs' YAMLs must list
exactly the same tags with the same region/source split, or the comparison
is refused by name.

`--json PATH` writes every number above, the resolved input paths, both
runs' `provenance.txt`, the sha256 of every input file this run actually
read, and the sha256 of `compare_runs.py` itself, with `allow_nan=False`, so
a reported table can be checked against exactly what produced it.

### `--family water|energy`

Selects the family table (R1), which is kept in one place in the code
(`FAMILY_TABLES` in `compare_runs.py`) so WP3 (copies) and WP4b (rain, snow,
precipitation) can add their real output names there once those parts
exist. Default: autodetected from which of the reference YAML's two tag
blocks (`energy_source_tags`, `water_tracers`) is actually non-empty (a
merged config always writes both keys; the unused one is `~`). Both
non-empty, or both empty, is refused; pass `--family` explicitly then.

### `--judge`: G3_PLAN.md section 6.1's budgets (R5, R7; water only)

Judges every tag at hour 1 and hour 24 (both must be in `--hours`) against
the budgets below, and closure (R7), and exits nonzero if any fails. The
verdict, the budget table, and the commit of `G3_PLAN.md` the budgets came
from (`git log -1 --format=%H -- G3_PLAN.md`) are all written to the JSON
under `"judge"`. Energy has no family-wide total field to compute a share
from, so `--judge` refuses a non-water `--family`.

| When   | Region tag           | Source tag            |
|:-------|:----------------------|:-----------------------|
| 24 h   | L1 ≤ 2%, L∞ ≤ 5%      | L1 ≤ 2%, L∞ ≤ 5%      |
| 1 h    | L1 ≤ 1%, L∞ ≤ 25%     | L1 ≤ 10%, L∞ ≤ 25%    |
| Small tag (share `S` < 1%, or the reference is zero here) | `abs_L1 ≤ 2e-4 · total_ref` replaces both L1 and L∞ (relative numbers still reported) | same |

`S = integral_ref / total_ref` at that hour, `total_ref = Σ hus_ref · ρ_ref
Δz`. **These definitions -- S from the reference at the same hour, the
small-tag rule, a region+source tag counting as source, a non-finite value
or missing hour as a failure, and 6h/12h reported but not judged -- were
proposed by the phase-1 review and accepted by the owner on 2026-09-23**;
`G3_PLAN.md` section 6.1 records the same text. The JSON's `judge.definitions`
field says so explicitly.

Closure (R7), when the run's `<tag_prefix>res` file exists: `G(t) = Σ
|q_tag_res| w / total_ref(t)`, budget `G(24h) ≤ 0.002`; "the second 12h add
no more than the first" is `G(24) - G(12) ≤ G(12) - G(0)` (only checked when
hours 0, 12 and 24 are all present); the remainder after named parts is `≤
1e-6 · total_ref` at 24h, where "the named parts" is the list passed with
`--closure-remainder-fields NAME,...` (already-existing field stems in the
run, no prefix added) -- empty by default, since WP3/WP4b have not named
these fields (leaks, ledgers, the 10-Newton one-iteration part) yet; without
it, this one check is skipped with a `NOTICE`. These three formulas are also
the owner's 2026-09-23 decision (G3_PLAN.md 6.1).

**Left proposed, not yet implemented against real fields**, since WP3/WP4b
have not fixed their output names: R8 (the copies' own residual, weighted
by updraft mass `ρaʲ Δz`) and R9 (rain/snow closure against `husra`/`hussn`,
and `Σ pr_tag = pr`, which needs averaged or accumulated precipitation
output, not hourly instantaneous snapshots -- M5 of the phase-1 review).
Both are out of scope for this pass; see "Left open" below.

### `--bitwise-tags` (R11)

Also compares every tag field bit for bit, like the parent fields (written
to `tag_bitwise` in the JSON). For criterion 11 ("the restart carries the
tags bit for bit"): compare the tag files of the two segments directly with
this flag once S6's restart-alignment work exists (left open, see below).

### `--ladder-share` (R12)

A separate mode (skips every other check in this file) for comparing a
tag's share of the total, `φ = q_tag / q_tot`, between two rungs of the
convergence ladder that may use different `z` grids or time lengths (60 vs.
120 levels). Each run's own hour lookup and own faces/`Δz` are used. States
which formula it used in the output and the JSON (`"mode"`):

  - **same `z` grid**: the level-wise share metric, `L1_φ = Σ|φ_run - φ_ref|
    · q_tot,ref · w / Σ φ_ref · q_tot,ref · w`, plus the parent's own change
    (`hus`, `rhoa`) reported beside it, since each rung is a different
    atmosphere;
  - **different `z` grids**: only the column-integrated share,
    `φ = (∫q_tag) / (∫q_tot)` on each run's own atmosphere, and the plain
    difference of the two scalars -- the parent's own change is not
    reported here (it would need one grid too).

### `--parity-only` (criterion 3: a tagged run against its untagged twin)

Another separate mode (skips family detection, the tag list, per-tag
metrics, `--judge`). Today's default flow needs a family and a tag block in
both runs; the untagged twin (`w0c_d4w_untagged`) has neither, so
`--family` autodetection dies with "cannot autodetect --family" and
`--expect-parity` cannot be used for this pairing at all. `--parity-only`
is the fix:

  - the parent set is the *union* of both runs' fields, minus a fixed,
    family-agnostic list of tag-family output prefixes (`q_tag_`,
    `qv_tag_`, `e_src_`, `e_tag_`, `e_prc_`, `q_prc_`, `pr_tag_` --
    `q_tag_res` and `q_tag_fix_*` are covered by the plain `q_tag_` prefix,
    not listed separately, since prefix matching already catches them);
  - a field present in only one run must itself be a tag-family output (by
    that same prefix list) -- reported, per side, under
    `tag_only_fields` in the JSON, and *not* compared. Any other
    one-run-only field is a hard failure (S1's fix, without needing
    `--family`);
  - every remaining common field is compared bit for bit,
    **unconditionally fatal** on any break (this mode's whole point is a
    parity claim, so there is no `--expect-parity` opt-in here);
  - the S2 pairing checks (`provenance.txt`, `FLOAT_TYPE`, the YAML-diff
    allowlist) still run, widened with the tag family's own config keys,
    which legitimately differ between a tagged run and its untagged twin:
    `water_tracers`, `water_closure_check`, `water_process_record`,
    `energy_tracers`, `energy_closure_check`, `energy_source_tags`,
    every `energy_source_tag_*` key, `energy_source_closure_check`,
    `energy_process_record` (plus `diagnostics`, already allowed).

Tried on the real pair: reference `w0c_d4w_untagged/output_0000`, run
`w1_d4w_grid_tags/output_0000` -- 37 fields bit for bit (25 outputs), 11
tag fields (`q_tag_*`, `q_tag_fix_*`, `q_tag_res`) reported as run-only,
exit 0, matching a by-hand check of the same pair.

## test_compare_runs.py

```sh
python3 test_compare_runs.py            # or: python3 -m unittest test_compare_runs -v
```

55 tests (about 15s, mostly the E73 fixture rebuild and the synthetic
netCDF writes), in four
groups:

  1. **`CompareRunsCLIMutationTests`** -- the original six mutation tests
     (a real energy run pair copied from `v3_upd_copies/output_0000`, on
     scratch when reachable, else the archive's durable copy under
     `~/git/Clima/ClimaAtmosResiDyn-archive/scratch_tag_closure/`, mutated
     with netCDF4 in `r+` mode, run through the real CLI as a subprocess),
     plus four more: a within-run time shift in a **non-`rhoa`** file
     (kills the "RunCoords disabled" mutant, which a shift in `rhoa` alone
     cannot), `output_active`/a bare run root/the same directory twice
     refused, and a run written with another output period
     (`_5m_inst.nc`, not `_1h_inst.nc`) still read correctly, with a
     mismatched pair (one run renamed, one not) refused by name. `--tags
     sfc,rad,mp` pins these to the three tag files actually copied, since
     the tag list now defaults to *every* tag in the YAML (8, for this
     config).
  2. **`AnalyticMetricTests`** (B1) -- pure calls into `compare_runs.py`'s
     own functions (`compute_faces_and_dz`, `tag_row_metrics`, `bit_compare`,
     `parse_tag_block`, `detect_family`), no subprocess, no files. A
     **nonuniform grid** (centres 25, 100, 250 m → faces 0, 50, 150, 350 m →
     `Δz` = 50, 100, 200 m, a different value at every level) with `ρ` and
     `q` chosen so every metric has a closed form, checked to the numbers'
     own float64 precision (`delta=1e-9` to `1e-12`, not just "close") --
     this kills both the `np.gradient(z)` and the `Δz = 1` mutants. Also: a
     perturbation placed only at the top level and the last of several hours
     (kills "lowest level"/"first hour" mutants), the `ref_zero` case, a
     signed-zero `bit_compare`, a dtype mismatch, and the region/source/both
     tag-block parsing (R2).
  3. **`SyntheticRunTests`** -- full synthetic run pairs built with netCDF4
     (never derived from any real run), through the real CLI: the
     nonuniform grid end to end; `ρ` differing between runs while `q` is
     identical (kills "weights from the run's `rhoa`" directly, not just in
     isolation); non-column geometry, a transposed `(time, z)` file, a top
     face disagreeing with `z_max`, a date change -- all refused; S1 (a
     parent field in only one run, a surface field's parity, `--expect-parity`
     on any break); S2 (a YAML key outside the allowlist -- `NOTICE` without
     `--expect-parity`, refused with it; the mode key and `toml` allowed to
     differ); S3 (the own-atmosphere integral appears when `rhoa` parity
     breaks); S4 (a variable's units, and the time epoch); S5 (a tag renamed
     in one run's YAML); B2 (a NaN, a fill value, and that `--json` never
     writes a bare `NaN`); `--judge` (pass on identical runs, fail on a
     broken budget, the small-tag share boundary at 1% built so the
     perturbation would fail L1/L∞ but must pass the absolute bound,
     `--judge` refusing a non-water `--family`); `--bitwise-tags`;
     `--ladder-share` on two different `z` grids (3 vs. 5 levels), checking
     it falls back to the column-integrals-only mode and does not attempt a
     level-wise comparison; `--parity-only` (a synthetic untagged/tagged
     pair: passes and reports the tag-only fields, fails unconditionally on
     a bitwise break with no `--expect-parity` needed, fails on a
     non-tag-family field present in only one run, refuses the same
     directory twice); and fractional `--hours` (a 360s-cadence pair,
     `--hours 0.1,0.2` matched and JSON-keyed as `"0.1"`/`"0.2"`, an
     all-integer `--hours` still parsing to plain `int`s and keyed
     `"0"`/`"1"`/... as before, and a fractional hour absent from the data
     refused by name).
  4. **`E73RegressionTest`** (B1) -- rebuilds the E73 fixture
     (`fixtures/e73/`, five hours × 30 levels × 12 variables, as `.npz`
     arrays plus the two real `.yml` files, **not** `.nc`/`.json`, which
     the repo's `.gitignore` ignores everywhere) into real
     `<var>_1h_inst.nc` files in a scratch tmp dir, runs the CLI, and checks
     every tag/hour/metric and every parity verdict against
     `fixtures/e73/expected_e73.py`, frozen from a run that reproduced
     `e73_reproduction.txt` character for character (`fixtures/make_e73_fixture.py`
     is the one-off tool that built the fixture from
     `v3_upd_copies/output_0000` and `v3_upd_default/output_0002` on
     scratch; `fixtures/e73/data.py` explains the `.npz` round trip).

### mutation_check.py

```sh
python3 mutation_check.py
```

Automates the phase-1 review's own by-hand check: copies
`analysis/evidence/` into a scratch tmp dir per mutation, applies one
textual mutation to the copy's `compare_runs.py` (wrong weights, `Δz = 1`,
an unweighted L1, a pointwise-not-peak-normalized L∞, an off-by-one hour
index, `RunCoords` disabled, `==` instead of bit patterns, the date check
removed, `output_active` accepted, a transpose skipped, the top-face check
disabled, the dtype check disabled, a flipped sign, `np.gradient(z)`, the
lowest level only, S1's union check disabled, B2's finiteness check
disabled), and runs the copy's `test_compare_runs.py` against it.
**16 of 16 mutations are now caught** (the phase-1 review's original table,
against the six original tests only, caught 2 of 19; one mutation from the
review's table, disabling the `output_active` special case, is not listed
here since `resolve_output_dir`'s `OUTPUT_DIR_RE` check refuses that name
independently -- confirmed by running the mutant directly -- so it no
longer represents a live defect, only a worse error message). Re-run this
after any change to `compare_runs.py`'s metrics or checks.

## Left open

  - **S6 (restart pairs).** Aligning two run segments by exact time value
    (not position) and differencing cumulative ledgers within one segment
    only was judged not cheap enough for this pass; `--hours` still expects
    one contiguous run directory. `--bitwise-tags` is ready to compare two
    segments' tag fields once the alignment exists.
  - **R8 (copies) and R9 (rain/snow/precipitation).** WP3 and WP4b have not
    named their output fields yet, so nothing in `compare_runs.py` reads
    them; `FAMILY_TABLES` and the module docstring are the place their real
    names go in. `--closure-remainder-fields` and `--ladder-share` are
    ready and tested against synthetic files, but the true G3 budget
    checks (R8's copies residual and repair, R9's rain/snow/`pr_tag_`
    closure) wait on those fields existing.
  - **Criterion 3's final-checkpoint comparison** (the HDF5 restart file,
    field by field, bit for bit) is not implemented; `--expect-parity`
    today only compares the hourly `_1h_inst.nc` snapshots.
  - **S6, S7-S9, S10, S11 as inventory/manifest/submit-path items** are
    owned by another session's changes to `manifest.py`, `inventory.py`,
    `runs_inventory.csv`, `submit_g3.sh` and `tag_closure_common.sh` (see
    those files' own sections above); this pass touched only
    `compare_runs.py`, its tests and this file.

## manifest.py

```sh
python3 manifest.py --repo WORKTREE --config YML [--driver FILE] \
                     [--extra FILE ...] [--julia BIN] [--julia-channel +1.11] \
                     [--command "..."] --out PATH.json
python3 manifest.py --verify PATH.json
```

Run on the login node (compute nodes have no git, which is why a run's
`provenance.txt` reads `commit_dirty: unknown` today). Records the
worktree's actual `HEAD` sha, branch (or `detached`), and every remote ref
that contains `HEAD` (`head_on_remote`; empty means a detached HEAD reachable
from no ref, which is lost once the worktree is removed and git garbage
collection runs); every `git status -z` entry, both as readable
`status_lines` and, for untracked files, the individual path and sha256 of
each one (`untracked.files`) plus a combined hash (`untracked.sha256`); the
diff itself (`git diff HEAD --binary --no-ext-diff --no-textconv`, both its
sha256 and its full text, so a dirty worktree that is later cleaned can
still be rebuilt from the manifest, not just proven dirty); the sha256 of
`.buildkite/Project.toml`, `.buildkite/LocalPreferences.toml` and every
`.buildkite/Manifest-v*.toml` present, not just the 1.11 one; the sha256 of
the config/driver/extra files given; every path a config itself names
(`restart_file`, `external_forcing_file`, `toml`, `era5_*`), resolved to a
real path with its sha256 (or size and mtime, for anything over 200 MB) --
refused outright if such a path goes through `output_active`, since that
link moves when the run it names is rerun; the Julia binary and channel the
job will actually use (`--julia`/`--julia-channel`, else `$JULIA`/
`$JULIA_CHANNEL`, else `julia`/`+1.11` -- the same order
`runscripts/tag_closure_common.sh` resolves them in) and its `--version`
output; the loaded modules (`$LOADEDMODULES`); `$JULIA_DEPOT_PATH` and the
other Julia/CliMA env vars that can change whether a run is bitwise
reproducible; the hostname, the UTC time and the command string. Every git
call goes through `git --no-optional-locks`, so running this tool never
itself modifies the worktree it is inspecting.

`--verify PATH.json` re-reads a written manifest, recomputes every git fact
and hash fresh against the same repo and files, and prints `unchanged` or
`CHANGED: was ... now ...` per field; exits nonzero if anything changed.
Fields this tool added after a manifest was written have no counterpart in
that old manifest, so `--verify` reports their current value as
`(new field, not in old manifest)` rather than comparing them -- the four
manifests already under `experiments/tag_closure/output/w*/manifest.json`
still verify cleanly.

Tried read-only against `../../../../ClimaAtmosResiDyn-upd-run` (config
`experiments/tag_closure/configs/v3_upd_default.yml` inside that worktree):
correctly reports `.buildkite/Manifest-v1.11.toml` as ` M` in `status_lines`
(the worktree is genuinely dirty there, as G3_TODO.md 1.1 says), and
`--verify` on the resulting manifest reports every field unchanged
immediately afterwards.

## runscripts/submit_g3.sh

The manifest's place in the submit path (S9 of the phase-1 review): stamp,
then submit, so the two cannot drift apart.

```sh
CONFIG=experiments/tag_closure/configs/<run>.yml \
    [DRIVER=...] [SCRIPT=experiments/tag_closure/runscripts/phase_c.sh] \
    experiments/tag_closure/runscripts/submit_g3.sh [--dry-run] \
        --account=hpda-c --partition=hpda2_test --time=02:00:00 \
        --cpus-per-task=2 --mem=48G \
        --output=<scratch>/tag_closure/logs/%x-%j.out \
        --error=<scratch>/tag_closure/logs/%x-%j.err
```

Writes the manifest to `$SCRATCH/tag_closure/manifests/<job_id>.<timestamp>.json`
*before* calling `sbatch`, and exports that exact path to the job as
`MANIFEST_PATH`. `tag_closure_common.sh` copies it into
`output_XXXX/manifest.json` and records its path in `provenance.txt`, so a
run's own manifest travels with its other small files without needing git on
the compute node. Every other argument passes straight through to `sbatch`
unchanged. `--dry-run` writes the manifest and prints the `sbatch` line it
would run, without submitting -- no Slurm access needed, so this is how the
wrapper itself is tested. Once `sbatch` returns a job id, the wrapper adds a
symlink `<job_id>.<slurm_id>.json` next to the manifest for a human to find
it by job id; it does not rename the file itself, because the job's
environment already has the original path baked in at submission time, and a
job can sit queued for hours before it runs.

## inventory.py

```sh
python3 inventory.py [--root ROOT] [--repo REPO] [--register CSV] --out runs_inventory.csv
```

Walks `ROOT/*/output_*/` (default: the tag-closure output root on scratch)
and writes one row per `output_XXXX` directory found there, plus one row for
every run in the register (`review/register/runs.csv`) that has no matching
directory on scratch today (its data may be gone, or it may live on another
machine) -- so the CSV covers every run `RUNS.md` lists, not only what
happens to still be on this scratch root. `output_active` itself never gets
a row; it is only read to set the `is_active` flag of the directory it
points to.

The key is `(machine, run, output_index)`, not `run` alone: two machines
have used the same run name for two different commits and jobs
(`c0_sphere_audit`, found by the phase-1 review). `machine` comes from the
row's own `provenance.txt`.

Beyond the facts the first version gathered (`commit`, `commit_dirty`,
`started`, `finished`, `exit_status`, `slurm_job_id`, `partition`, `ntasks`,
`float_type`, `n_times`, `last_time`), this version adds:

  - `outcome`: `complete`/`failed`/`unknown` from `exit_status`, or
    `no_provenance` if the run never wrote one. It does not attempt
    `truncated` (comparing `n_times` against an expected count) -- the
    output period is not parseable uniformly enough across this series'
    configs to guess right, so it is left open rather than guessed wrong.
  - `stop_file_present` and `graceful_exit_value`: `graceful_exit.dat` is
    created holding `0` at the *first* step of every run
    (`src/callbacks/callbacks.jl`), so its mere presence is not a graceful
    exit -- an OOM-killed run has it too. The old `graceful_exit` column
    conflated the two; this reports them separately.
  - `commit_status`: whether the row's commit is on `main`, on a remote
    branch, reachable but on no ref, or not in this repo at all, checked
    with `git merge-base --is-ancestor` and `git for-each-ref --contains`
    against `--repo` (default: this worktree). Best-effort: a repo that
    cannot see the commit reports `unknown`, not an error.
  - `geometry`, `family`, `updraft_copy_mode`, `config_sha256`: read from
    the run's own merged YAML copy (`h_elem:` marks a cubed sphere;
    `water_tracers:`/`energy_source_tags:` mark the tag family).
  - `superseded_by`: the newest `output_XXXX` of the same `(machine, run)`,
    for every earlier index.
  - `renamed_hint`: `yes` if the run name ends `_superseded` or `_oom_<id>`.
  - `restart_of`: the run's own `restart_file` value, if its YAML has one
    (unresolved; `manifest.py` resolves and hashes it at submission time).
  - `register_purpose`, `register_finding_ids`, `register_status`: joined
    from `review/register/runs.csv` on `run`.
  - `register_commit_mismatch`: set when the register's own commit for that
    `run` disagrees with this row's -- the same collision `commit_status`
    exists to catch, seen from the register's side.
  - `manifest_path`: `output_XXXX/manifest.json` if `submit_g3.sh` wrote one
    for this run, else the path `provenance.txt`'s `manifest_path` names.
  - `status`: still mostly `unclassified`, for a person to set
    (`pr_head`/`historical`/`superseded`/`failed`/`proposed`). Seeded to
    `failed` or `superseded` only where the columns above already make it
    unambiguous.

The CSV's first line is a `#`-prefixed header with the generation time, the
root, the register path and the tool's own sha256 -- skip it, or regenerate
the CSV, rather than trust a stale copy. Read-only: never writes under the
output root, and never writes to the git repo or the register it reads.

## Bitwise identical, and the parity contract

"Bitwise identical" in this pipeline is the same standard
`docs/clima_atmos_specific.md` sets under "Fork parity with upstream":
compare the parent arrays with something that does *not* treat a signed
zero, or two different `NaN` payloads, as equal — the doc names `isequal`
in Julia; `compare_runs.py`'s bit-pattern view (`a.view(uintN) == b.view
(uintN)`) is the numpy equivalent. That contract only holds **within one
machine, one Julia and `Manifest`, one float type and one process count** —
comparing across any of those needs a numerical tolerance instead, not a
bitwise check. `manifest.py` exists to pin down which of those a given run
actually used, so a later comparison can tell whether it is entitled to
expect bitwise agreement at all.
