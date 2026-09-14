# Review of the remaining-tasks list, 2026-09-14

An Opus agent reviewed a draft of the list of remaining tasks against the
repository, read-only, at the owner's request. Its findings are folded into
[OPERATIONAL_TODO.md](OPERATIONAL_TODO.md). Before folding them in, the session
checked findings 1, 2, 4 and 8: `energy_source_tag_transport` appears only on
#72's branch; #70's `docbuild` failed at 35 minutes and `docs-required` fails;
#63 merged on 2026-09-11; the stale lines are as cited. Line numbers refer to
the tree at `10607630`. The report follows as the agent wrote it.

---

The draft is mostly accurate, but three things are wrong. The suggested order does not work, because #72 has to merge before C1b and C2. Nothing in the list runs Float32 or more than one process before the GPU step. And the validation runs never test the shipped EDMF setting. Findings, most important first:

**1. #72 has to merge before C1b and C2 (§2 items 3–4; order steps 5, 6, 9).**
- **Wrong:** C1b is to be built "under both transports", and C2 writes "the transport" into the checkpoint. The key `energy_source_tag_transport` exists only in #72. `git grep` finds it at `530a3658` and not at `4c274aed` (#70), `0ae408d8` (#69) or `origin/main`. The order still finishes #72 at step 9, after C1b and C2.
- **Change:** move #72's docs, undrafting and retargeting to step 3, right after #69 and #70 merge.

**2. Float32 and multi-process runs are ranked too low for a GPU Float32 sphere (§3 V3, T2; §4 U6, C6).**
- **V3:** no Float32 tag run exists (OPERATIONAL_TODO.md:40, FINDINGS.md:1498).
- **Records:** they are FT fields that accumulate from the start of the run and are never reset (process_record.jl:22-25). Float32 rounding will grow in long runs.
- **Multi-process:** every run was single-process (`climacomms_context: SINGLETON` in output/c7_sphere_mp/provenance.txt, `--ntasks=1` at phase_c.sh:6). Yet the closure callback uses collective reductions (tagged_tracers.jl:770-790).
- **Change:**
  - Make V3 and T2's Float32 part B.
  - Add a B item: a 2–4 rank CPU sphere with tags, records and the check, before the GPU step.
  - Rank U6 and the "Float32 rounding floor" again once V3 is back.

**3. No run validates B4 (§2 item 3).**
- **Gap:** D4 and D5 both set `edmfx_vertical_diffusion: false` (d4_column_edmf.yml:50, d5_column_edmf_ice.yml:46). Every shipped EDMF config uses `true` (FINDINGS.md:889-890).
- **Change:** add a D4 variant with `true`. Make T6 and V2 use `true` explicitly. Also say what D4 must show after B. Its pre-B role as a baseline (OPERATIONAL_TODO.md:202-209) is silently dropped.

**4. The PR stack's CI is not all green (§2 item 1).**
- **#69:** all checks pass.
- **#72:** all checks pass.
- **#70:** `docbuild` hit its 30-minute limit, so the required `docs-required` check fails (run 34593320376).
- **Change:** re-run #70's docs job before merging.

**5. Tolerances cannot be calibrated before the long runs (order step 7 before step 8).**
- **Wrong:** A3's threshold comes "from a five-day pair" (OPERATIONAL_TODO.md:170-171). U2 is "calibrated per transport". Both need production-config runs.
- **Change:** split each into "implement the switch" (step 7) and "calibrate" (after V2 and V3).

**6. P4 needs more than one staged run, and its status is stale (§0, §2 item 2).**
- **Scope:** one staged run of `p4_edmf_tags` gives a breakdown but cannot show which stage grows faster than the field count. `c0_column_notags` is not an EDMF baseline. Also stage `d4_column_edmf_notags` (18.5 min) and `p4_edmf_two_tags` (27 min), both from E44b.
- **Status:** the retest is not running. It finished at 11:54 with exit 0 (scratchpad `p4_smoke2.log`), with non-zero stage times. "First step" still takes 37.5 s after each piece was called, so part of the compile is still unattributed.
- **Size:** P4-fix's size is unknown until E44c. Mark it M–L.
- **Dependencies:** T6 adds an EDMF compile to CI, where `tagging_energy` already takes up to 56 min, so T6 depends on P4-fix. "Blocks every EDMF run" holds only within `hpda2_test`'s two-hour cap (NEXT_SESSION.md:198-201). C1b's code can be written alongside P4-fix; only its validation waits.

**7. Other priority labels.**
- **V5 (S):** production runs restart, and step 6 already pairs V5 with C2 (B). Make it B.
- **V1 (B):** it is a 0M, Float64-style sphere, not production physics. Either merge it into V2 and V3 as a 10-day Float32 run, or make it S.
- **U1 (B):** it could be S if T4's example config and the guide always set the offset. That is the owner's call.

**8. Missing items.**
- **D2:** it omits guide fixes 5, 7 and 9 (USER_GUIDE_DRAFT.md:427-441). Its citation `tracer_config.jl:564-569` is stale; the docstring is now at `tracer_config.jl:605`.
- **Housekeeping misses the three known defects** at LEVANTE_TASKS.md:458-467.
- **Housekeeping misses these stale records:**
  - NEXT_SESSION.md:49-52 says `docs/src/` is on open PR #63. #63 was merged on 2026-09-11, so D1 is no longer bound by that rule.
  - FINDINGS.md:1414-1415 says C3 "waits for the owner"; it was done in `7a290c98`.
  - FINDINGS.md:1674-1675 says none of D1–D5 "has run"; D1 ran.
  - LEVANTE_TASKS.md:161 and :210 still call #70 a draft.
  - FINDINGS.md:1688 and LEVANTE_TASKS.md:489 still list the experiment "C2" (implicit brackets). #69 built it, and the name clashes with the to-do list's C2 (restart guard).
- **Phase B** (FINDINGS.md:1682-1686) is not mentioned. List it as dropped or as open.

**9. Small errors.**
- "#72: add E35–E44" should be E35–E43 (OPERATIONAL_TODO.md:81). E44 is about EDMF build time, not the audit.
- The head is `3b60a49d`; `50b7461e` is its parent.
- P4-stages is called "Approved", but no record in the tree says so. Record the approval.

**Checked and sound:**
- **Numbers:** ±30,920 (FINDINGS.md:470), ±16,294 (:694), 17% (:875), and C1b's 220 + 200 lines (design :412).
- **Code citations:** `edmfx_sgs_flux.jl:403-409` and `restart.jl:34-39`.
- **Housekeeping claims:** the validator filter (validate_d_configs.jl:20), and the uncommitted files, which match `git status`.
- **Stack and worktree:** the PR states and bases, and the p4 worktree at `edd44e1d`.
- **Done items:** C1a, C3, M2, R2, R4 and D1 with its twin are correctly left out.
- **Order:** P4-fix before C1b, docs after C1b, and GPU last.
- **Open questions in §6:** they match FINDINGS §7.
