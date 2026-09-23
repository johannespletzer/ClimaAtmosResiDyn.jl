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

## Decisions

 - [!] **Q4, how the plume is bounded (R1).** Recommended: the energy-weighted
   blend that the job session wrote on 2026-09-23 (uncommitted in
   `../ClimaAtmosResiDyn-upd`), with one change. Its single factor per cell is
   set by every tag, the source overlays included. In a scalar check an overlay
   holding 1e-6 of a cell's energy cut the region tags' mixing there from
   θ = 1 to 0.09. The factor should come from the partition only, and each
   overlay should get its own. Both must be settled before the D4 default runs
   are made again.
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
 - [x] Agent definitions in `~/.claude/agents/` (table below).
 - [ ] Commit the two assessment documents and this list. Re-pin their code
   links to PR #95's head once the fix is committed. The assessment pins
   `974f3e16`, and the head is now `e71430fb`.
 - [ ] Record the review's status: R3 to R6 closed at `e71430fb`; R1 being
   fixed (Q4); R2 open (the ladder, phase 4).
 - [ ] Merge this branch into the experiment branch at each gate, coordinating
   with the job session, which commits there.

## Phase 1: the evidence pipeline (M0, rank 2, insight D)

 - [ ] 1.1 A manifest written on the login node at submission. Compute nodes
   have no git, which is why provenance reads `commit_dirty: unknown`. The run
   worktree is in fact dirty (`.buildkite/Manifest-v1.11.toml`), and its
   `experiments/` is an untracked copy. It records the tree, the diff, the
   Manifest, the config, the driver and the command, with hashes. It ships as a
   standalone tool, and the job session adds one line to its submit path.
 - [ ] 1.2 A verifier to replace `analysis/increment/tag_correctness.py`. It
   takes explicit run directories, not "the latest". It requires every
   expected variable, identical times and identical coordinates. Its parity
   check is bitwise, so it sees signed zeros. Its metrics are named exactly
   (mass-weighted L1, peak-normalised L∞, absolute error) and use the grid's
   own cell weights.
 - [ ] 1.3 Five mutation tests: a missing variable, a shifted timestamp, a
   truncated run, a moved coordinate and a flipped signed zero must each be
   rejected.
 - [ ] 1.4 A machine-readable inventory of the runs on scratch, with a status:
   PR head, historical, superseded, failed or proposed.
 - [ ] 1.5 E73's table reproduced from its inputs (`v3_upd_default/output_0002`
   against `v3_upd_copies/output_0000`).
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
   budget whose remainder is named.

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

   The job session holds dt 60 and 30, Newton 2 and upwind (`eead88c3`),
   cancelled at 08:20 for the fix.
 - [ ] 4.5 A surface pulse, and convection switched on and off.
 - [ ] 4.6 Alternative placements of the increment correction, on a shared
   parent.
 - [ ] 4.7 Check that the tags accept the held-out columns, then run default
   and copies on each.
 - [ ] 4.8 Comparison tables through the verifier (`clima-analysis-builder`).
 - [ ] 4.9 A red team on the choice of default (`clima-numerics-reviewer`).
 - [ ] 4.10 The owner chooses the default.

## Phase 5: cost (M4, rank 7); finish before the sphere run

 - [ ] 5.1 A benchmark harness (`clima-analysis-builder`).
 - [ ] 5.2 Cold and warm timings and peak memory at 2, 8 and 32 tags.
 - [ ] 5.3 Precompile workloads.
 - [ ] 5.4 Moving the nested copies out of the large solver, only with a
   dependency proof (`clima-numerics-reviewer`) and a parity test.

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
