# G3: from a working prototype to a qualified diagnostic

The owner set G3 on 2026-09-23, after G2 was met (E75). G3 carries out
milestones M0 to M5 of [repo-operability-pathway.md](repo-operability-pathway.md)
on single columns, and ends with one ten-day sphere run at the chosen default.
The reasoning behind each item is in
[untapped-potential-assessment-extended.md](untapped-potential-assessment-extended.md).
M6 to M8, the GPU and a production campaign are not part of G3.

**Approved by the owner on 2026-09-23:** every job within this programme, and
agents as proposed (table below). Model code still goes to draft PRs that only
the owner merges. The parity rule of `AGENTS.md` holds for every change.

**Who does what.** A separate session runs the jobs and owns PR #95's fix, in
the worktrees `../ClimaAtmosResiDyn-upd` and `../ClimaAtmosResiDyn-upd-run`.
This session (worktree `ClimaAtmosResiDyn-exp`, branch `claude/g3-programme`)
owns this list, the evidence pipeline, the accounting work, the reviews and the
agents. Results go into FINDINGS as usual.

Marks: `[ ]` open, `[~]` under way, `[x]` done, `[!]` waiting for a decision.

## G3 is met when

The roadmap at the top of [OPERATIONAL_TODO.md](OPERATIONAL_TODO.md) places G3
within milestones M0 to M8. The criteria below are the pathway's acceptance
criteria, cut down to G3's slice. The numbers come from Q5 and are fixed before
the runs that test them.

| # | Criterion | Milestone | Status |
|:--|:--|:--|:--|
| 1 | The verifier recomputes every G3 headline number from runs stamped with a manifest, and the mutation tests pass. | M0 | tools built, tests pass, review (1.8) open |
| 2 | #95 is merged with a bounded exchange. The share-space, restart and file-based-initialisation tests run in CI. | M1 | R1 in `dbe7435c`, Q4 open |
| 3 | On D4 the energy budget of each accepted step closes to a named remainder, within a bound set beforehand. The gross accumulators pass their tests. | M2 | open |
| 4 | Each column case has a reference converged in time step, grid and Newton count, to a set fraction of the Q5 budget. | M3 | open |
| 5 | The chosen default meets the Q5 per-tag budgets on D4 and on the held-out columns. How often the bound acts, and the spread across other closures, are reported. | M5 | open |
| 6 | Startup and step time and peak memory are measured on CPU at 2, 8 and 32 tags, and the allocation gates pass. | M4 | open |
| 7 | Ten days on the sphere at the chosen default are compared with E75 through the verifier. | — | open |
| 8 | Every run with and without tags keeps the model's fields bit for bit. | standing | holds |

**Left out of G3,** for the goals after it:
 - M1's GPU and autodiff checks;
 - M2's contracts for tagged water and the stratospheric tracers, and EDMF in
   the parent-budget ledger;
 - M3's sphere cases, and a file-based run with a restart;
 - M4 on the production grid, the GPU and scaling;
 - M6 to M8.

## Decisions

 - [!] **Q4, how the plume is bounded (R1).** Recommended: the energy-weighted
   blend the job session committed as `dbe7435c` on 2026-09-23, with one change.
   Its single factor per cell is set by every tag, the source overlays
   included. In a scalar check an overlay holding 1e-6 of a cell's energy cut
   the region tags' mixing there from θ = 1 to 0.09. The factor should come from
   the partition only, and each overlay should get its own. The commit also
   says the environment's shares stay non-negative without clipping. That
   holds only when the subdomains' energies add up to the cell's; with a 1%
   mismatch the check gave −0.0001. Both points go to the review, 2.5.
 - [!] **Q5, the science error budget.** What the per-tag numbers are for, how
   accurate they must be, and whether a first-hour product is needed. Blocks
   phase 4.
 - [ ] **Q7, EDMF in the parent accounting.** Default unless overruled: the
   updrafts are a decomposition of the grid mean. An offline column budget
   comes first, and the ledger's EDMF verdict stays blocked.
 - [!] **Q8, a durable archive** for the minimal reference datasets, and its
   size budget. `$SCRATCH` is not durable. Blocks item 1.9 only.
 - [ ] Defaults unless overruled. Q9: the verifier, configs and alternative
   closures live on the experiment branch, and only general diagnostics go to
   `main`. Q10: closure variants that will never ship live as keys on a branch
   that never merges. Q11: the held-out columns are TRMM_LBA, RICO, GABLS and
   BOMEX with `tracerA`. Q12: CONDENSE_PLAN stays on hold, and the run
   register sits beside it.

## Phase 0: re-baseline

 - [x] Branch `claude/g3-programme` from the experiment branch at `eead88c3`.
 - [x] Agent definitions in `~/.claude/agents/` (table below). They load when a
   session starts. Until then an agent runs as `general-purpose` with the
   definition's model and rules in its prompt.
 - [x] Commit the two assessment documents and this list (`6096d103`).
 - [x] The roadmap at the top of OPERATIONAL_TODO.md, and G3 as the current
   goal there. The two assessment documents carry a "Frozen record" header and
   keep their old pins. Current commits are named here and in the roadmap.
 - [x] The review's status: R3 to R6 fixed in `e71430fb`; R1 in `dbe7435c`, with
   the points of Q4 open; R2 open (the ladder, phase 4).
 - [x] OPERATIONAL_TODO's open items matched to milestones, so that the roadmap
   replaces the old list rather than running beside it. See the roadmap's
   "Where the open items below go". An agent read them, and this session
   checked the doubtful ones.
 - [ ] Merge this branch into the experiment branch at each gate, coordinating
   with the job session, which commits there.

## Phase 1: the evidence pipeline (M0, rank 2, insight D)

 - [~] 1.1 A manifest written on the login node at submission. Compute nodes
   have no git, which is why provenance reads `commit_dirty: unknown`. The run
   worktree is in fact dirty (`.buildkite/Manifest-v1.11.toml`), and its
   `experiments/` is an untracked copy. The manifest records the tree, the
   diff, the Manifest, the config, the driver and the command, with hashes.
   Built as `analysis/evidence/manifest.py`, and it detects that dirty
   Manifest. Open: the one line in the job session's submit path that calls it.
 - [x] 1.2 A verifier to replace `analysis/increment/tag_correctness.py`:
   `analysis/evidence/compare_runs.py`.
     - It takes explicit run directories, not "the latest".
     - It requires every expected variable, identical times and identical
       coordinates.
     - Its parity check is bitwise, so it sees signed zeros.
     - Its metrics are named exactly (mass-weighted L1, peak-normalised L∞,
       absolute error) and use the grid's own cell weights.
 - [x] 1.3 Mutation tests: a missing variable, a shifted timestamp, a truncated
   run, a moved coordinate and a flipped signed zero are each caught.
   `test_compare_runs.py`: 6 of 6 pass, rerun by this session.
 - [~] 1.4 A machine-readable inventory of the runs on scratch, with a status:
   PR head, historical, superseded, failed or proposed.
   `runs_inventory.csv` lists 93 output directories. The statuses are not set
   yet.
 - [x] 1.5 E73's table reproduced from its inputs (`v3_upd_default/output_0002`
   against `v3_upd_copies/output_0000`). `e73_reproduction.txt`: all 32 rows
   match exactly. The old script's glob now picks `output_0003`, a later
   commit's run.
 - [ ] 1.6 The Float64-twin helper (synergy 2).
 - [ ] 1.7 A retrospective test of the early-warning probe (synergy 1): does
   `increment_left` flag V2's one-iteration collapse before the model top
   fails, against the two-iteration run? First check that the data are still
   on scratch.
 - [ ] 1.8 This session reviews phase 1, then writes a FINDINGS entry. Gate:
   from here on every headline number goes through the verifier.
 - [ ] 1.9 Checksummed minimal datasets for E73 and later headline tables
   (after Q8).

## Phase 2: close M1 on PR #95 (the job session codes, this session reviews)

 - [ ] 2.1 Q4 decided.
 - [ ] 2.2 One blend factor over the partition, and one per source overlay.
 - [ ] 2.3 Unit tests in share space:
     - the review's counterexample;
     - unequal subdomain energies, and energies that do not add up (the
       environment's share may dip only to a stated tolerance);
     - a scarce overlay that leaves the partition's mixing alone;
     - near-empty tags and vanishing subdomains;
     - Float32 and Float64;
     - the zero sum under every `edmfx_sgsflux_upwinding` choice.
 - [ ] 2.4 An audit column that says how often the bound acts: the fraction of
   cells with θ < 1, and the smallest θ.
 - [ ] 2.5 An adversarial review of the diff (`clima-numerics-reviewer`,
   xhigh), saved in `review/agent_reviews/`.
 - [ ] 2.6 The test groups at the new head: `infrastructure`,
   `tagging_source`, `tagging_source_edmf`, `tagging_source_increment`,
   `tagging_source_updraft` and `restarts`. CI green.
 - [ ] 2.7 The D4 default run again at the new head, G1 criterion 4 measured
   again (L1 ≤ 2%, L∞ ≤ 5% against the copies), and E73 marked superseded.
   The copies runs stay valid: copies mode runs neither the donor flux nor the
   exchange.
 - [ ] 2.8 The owner merges #95.
 - [ ] 2.9 A file-based column with the tags on. First check that the tags
   accept `prognostic_edmfx_tv_era5driven_column` (0M, initial state and
   forcing from a file). Then run it briefly: it must start with finite tags
   and pass the first accepted step's checks. The rebuild of `92e9ac26` has
   only a unit test so far.
 - [ ] 2.10 A real checkpoint round trip, default and copies: the continuous
   run against the restarted one, with the prognostic state bit for bit. Also
   a clear error when the tag list changes across a restart (U5).
 - [ ] 2.11 D1 with D3: PR #95's user guide covers D3's caveats. Those are the
   `c·Δρ` no bracket reaches, `e_src_fix` restarting at zero, the choice of
   `c`, ice passing provenance upward, and untested ground. D1 closes when
   #95 merges.

## Phase 3: accounting (M2, ranks 3 and 4, insight C, synergy 6)

 - [ ] 3.1 An inventory of every process and state-writing hook in the
   envelope (`clima-inventory-explorer`).
 - [ ] 3.2 One claim contract per family: tagged water, signed energy tags,
   energy source tags, process records, stratospheric tracers and the
   parent-budget ledger.
 - [ ] 3.3 A design note for the gross accumulators:
     - absolute repair throughput and an event count;
     - `|m_left|` per step;
     - the positive and negative loss, for τ;
     - accepted-step semantics, attempted against retained changes, and
       restart segments.
 - [ ] 3.4 The accumulators as a draft PR. Tests: alternating-sign
   corrections, invariance under the output interval, restart stitching, and
   the model's fields unchanged.
 - [ ] 3.5 Its review (`clima-reviewer`, high).
 - [ ] 3.6 One D4 run with every process record and the increment ledger.
 - [ ] 3.7 `analysis/increment/process_budget.py`, and an offline EDMF column
   budget whose remainder is named. Every process term includes `c Δρ`. The
   tags' repair is never booked as a parent energy source, since it moves
   energy between tags only.
 - [ ] 3.8 The residual report completed. It gains:
     - the residual's rate over a stated interval, and where it would settle,
       as a range (synergy 4);
     - its vertical and local maxima;
     - the headroom of the positive total (U9);
     - where an overlay is negative, and where a member exceeds its group's
       sum (A5).
 - [ ] 3.9 Warnings, abort rules and acceptance thresholds kept apart, in the
   configuration and in the guide. A small aggregate residual never passes a
   per-tag test. The runaway warning's tolerance per transport is calibrated
   from V2 and V3 (U2, OPERATIONAL_TODO item 11).

## Phase 4: reference suite and choice of closure (M3 and M5; ranks 1, 5, 6)

 - [ ] 4.1 Q5 decided.
 - [ ] 4.2 A pre-registered design with budgets, drafted by `clima-reviewer`
   and signed by the owner before the runs.
 - [ ] 4.3 Manufactured source-free mixing tests, as unit tests: uniform
   composition, and sharp and smooth interfaces with known answers.
 - [ ] 4.4 The D4 ladder, one axis at a time, default against copies:
     - dt 120, 60 and 30 s;
     - Newton 1, 2, 4 and 10;
     - grids of 30, 60 and 120 levels;
     - first-order upwinding;
     - a Float64 twin.

   Each setting's wall time is recorded, which also answers R5: what a
   converged Newton solve costs.

   The job session holds dt 60 and 30, Newton 2 and upwind (`eead88c3`),
   cancelled at 08:20 for the fix.
 - [ ] 4.5 A surface pulse, and convection switched on and off.
 - [ ] 4.6 Alternative placements of the increment correction, on a shared
   parent.
 - [ ] 4.7 Check that the tags accept the held-out columns, then run default
   and copies on each.
 - [ ] 4.8 Comparison tables through the verifier (`clima-analysis-builder`).
   Startup and later windows are reported separately. Where the reference is
   small, the absolute error is given as well.
 - [ ] 4.9 A red team on the choice of default (`clima-numerics-reviewer`).
 - [ ] 4.10 The owner chooses the default.
 - [ ] 4.11 Two more reference cases, each with an untagged twin: the cold
   precipitating column (T5's test, run long enough for its ice to last) and a
   forced column without EDMF.
 - [ ] 4.12 A sweep of the offset `c` within the range where every total stays
   positive, one offset per run and per restart lineage. It reports the tags'
   change in J as well as the normalised residual, and it feeds U8.
 - [ ] 4.13 A check that says when a run leaves the tested regime, for example
   when composition changes faster than the plume adjusts.

## Phase 5: cost (M4, rank 7); finish before the sphere run

 - [ ] 5.1 A benchmark harness (`clima-analysis-builder`).
 - [ ] 5.2 Cold and warm timings and peak memory at 2, 8 and 32 tags. The
   allocation gates still pass: at most 8 bytes for the exchange, and at most
   24 for the donor flux with the exchange.
 - [ ] 5.3 Precompile workloads.
 - [ ] 5.4 Moving the nested copies out of the large solver, only with a
   dependency proof (`clima-numerics-reviewer`) and a parity test.
 - [ ] 5.5 P2 (the share norm once per evaluation) and P3 (a string allocation
   per tracer under the audit), taken up only if 5.2's profile shows them.

## Phase 6: G3's sphere run

 - [ ] 6.1 Ten days at the chosen default, as `g2_v2_sphere_mix`, compared
   with E75 through the verifier.
 - [ ] 6.2 G3's closing entry, and the question of what comes next.

## Agents

Defined in `~/.claude/agents/`. None of them submits jobs, pushes or merges;
the sessions do that. Reports go to `review/agent_reviews/`.

| Definition | Model, effort | Used for |
|:--|:--|:--|
| `clima-numerics-reviewer` | Opus, xhigh | 2.5, 4.9, 5.4 |
| `clima-reviewer` | Opus, high | 3.5, 4.2 |
| `clima-analysis-builder` | Sonnet, medium | 1.1 to 1.5, 4.8, 5.1 |
| `clima-inventory-explorer` | Sonnet, medium, read-only | 3.1 |
