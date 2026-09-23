# H5: the loss check of the condensing

Step H5 of [CONDENSE_PLAN.md](../CONDENSE_PLAN.md). An independent agent that
wrote none of the condensed documents compared them with the originals. Written
on 2026-09-23.

- **Condensed:** `claude/tag-closure-condense` at `89a1954b`, directory
  `experiments/tag_closure/`.
- **Originals:** the record branch at `eec7f363`, and the copies in
  `archive/2026-09-23/`.
- **Register:** `review/register/` at `89a1954b`. H4 changed it after H2. It
  added E76's claim, the item `LEARNINGS:A2:1` and eleven conflict rows, and it
  halved the NetCDF counts in `runs.csv`. The halved counts are right: the old
  counts had followed the `output_active` links. Every other row is as H2 wrote
  it.

## Verdict

**Not clean. Two gaps are blocking, and both are one-line fixes.** Nothing is
lost. Every original is in the archive unchanged, and every register row has a
home. No number in the new FINDINGS is missing from the originals or the
register. But one entry had a value changed without an erratum. One row of the
superseded table gives a claim a status the originals do not support. There are
also 24 minor gaps: wording, pointers, stale housekeeping facts, and four pieces
of operator guidance that are now only in the archive.

By the plan, H5 repeats once the blocking gaps are fixed.

## The checks

| # | Check | Result | Counts |
|:--|:--|:--|:--|
| 1 | Claims in FINDINGS | **pass**, 2 minor | 130 rows (126 FINDINGS, 4 LEARNINGS): 130 IDs present. Every register number was found in its entry, except two time qualifiers that were dropped (m1). Evidence pointers (job, commit, `output/`): all present. The one mismatch, E32's `91b9bb9b`, is the register's typo; FINDINGS keeps the correct `91b9bbb9`. 22 design rows (ATTRIBUTION_PATH 19, TRACER_AND_FLUX 2, UPDRAFT_GAP 1): all three files are byte-identical to their originals. |
| 2 | Numbers | **fail**, 1 blocking, 3 minor | 0 numbers in the new FINDINGS are missing from the original FINDINGS or the register. Every entry was compared with its original. 1 changed value: E50's date (B1). The 3 errata (W7, E73, E75) are present and stated correctly. §12 holds the old values of all three. |
| 3 | Decisions | **pass**, 2 minor | 67/67 register rows are in DECISIONS.md with their date and substance. All 4 superseded rows are marked (rows 23, 25, 56, 64). Row 26 is filed under 2026-09-20, and the file notes the register's 2026-09-19. |
| 4 | Items | **pass**, 2 minor | 138 rows are open, waiting, shelved, superseded or done-not-struck. 63 are G3 rows, and G3_TODO keeps them unchanged. Of the other 75, 73 appear by ID in G3_TODO, G4_TODO, BACKLOG or FINDINGS §13. 2 have register target "archive": `LT-1`, in RUNS.md, and `NS-1`, in DECISIONS.md. 14 are placed differently from their register target, and all 14 follow ROADMAP's placement rule. §13's pointers are wrong for 4 rows (m6). |
| 5 | Runs | **pass**, 4 minor | 113/113 runs are in RUNS.md. Output index, date, job, findings, scratch and archive match the register. The NetCDF and `.hdf5` counts were recounted for all 113 runs on scratch and in the archive, without following links: 0 mismatches. |
| 6 | Documents | **pass**, 1 minor | 31/31 rows have a home. `archive/2026-09-23/`: 14 files are byte-identical to their originals at `eec7f363`, including FINDINGS.md. `INDEX.md` is new. `design/`: 3 files are identical. SUBGRID has 2 link fixes. `reference/`: each file has one pointer paragraph rewritten, to ROADMAP, G3_TODO and G4_TODO. `G3_PLAN.md` has one #95 reference changed. There are no other differences. |
| 7 | Removed #95 instruction | **pass** | The tag `archive/g3-programme-2026-09-23` (`2d7fa835`) holds the file, byte-identical to `eec7f363`'s. Four live references name the tag instead of the path: G3_PLAN.md:26, G3_TODO.md:72, review/checks/README.md:11 and STATUS.md:68-72, and DECISIONS.md does the same. Only the register CSVs still give the old path, as a record. |
| 8 | Links | **pass** | 214 relative Markdown links, anchors included, in every live `.md` outside `archive/`: 0 broken. |
| 9 | Nothing new claimed | **pass**, 7 minor | See m10 to m16. One claim in FINDINGS §12 is new and unsupported (B2). |
| 10 | Conflicts | **pass**, 1 minor | 11 original conflict rows: all 11 are in §12. 11 rows found by H4-B are recorded in `conflicts.csv` as "for G4's full re-check". No live document points to them (m17). |
| 11 | Content no register row covers | **pass**, 4 minor | 60 paragraphs were sampled from the originals. 46 are live, 10 are in the archive with a pointer from a live document, and 4 are only partly live (m18 to m21). None is lost. |

## Gaps

### Blocking: changed without an erratum

**B1. E50's decision date was changed silently.** FINDINGS.md:1087 now reads
"decision 7 of 2026-09-18". The original E50 (archive FINDINGS.md:1473) reads
"decision 7 of 2026-09-17". The new date agrees with the archived
OPERATIONAL_TODO.md:574, "On 2026-09-18, going through section 1", and with
`decisions.csv` row 54. So it is probably the right date. But the entry was
edited without a dated erratum, the conflict is not in `conflicts.csv`, and the
commit message does not mention it. That breaks the plan's rule: "A correction
is a dated erratum beside its entry". *Fix:* add a dated erratum to E50, or a
conflict row.

**B2. §12 lists E13 as superseded, and the originals do not.** FINDINGS.md:1525:
"E13's and E34's reading of the audit's first-hour residual as the initial
adjustment. → The one-iteration Newton increment. (E39, E39b)". E13 is about C1
against the unshifted sphere under tracer transport, not about the audit. Its
candidate was the `p·u` difference, not the initial adjustment. The register
has E13 as live. The new E13 entry (FINDINGS.md:560-566) and FQ-5 keep its
first-minute jump open. Only E34 named "the initial adjustment of E13 and E25"
as the candidate (FQ-16). *Fix:* drop "E13's and" from that row.

### Minor

**Claims and numbers (checks 1 and 2)**

- **m1. Two time qualifiers were dropped.** E22 (FINDINGS.md:992-994) lost "at
  24 h" and the record's −20,566 J kg⁻¹. The 0.0044 J kg⁻¹ share has no time
  now. M6 (FINDINGS.md:1486-1488) lost "from t = 0 on".
- **m2. E73's erratum is shorter than the original's.** FINDINGS.md:1262-1268
  drops "about 2× after the default's build in one process". G3_PLAN.md:485
  keeps it. The erratum also says the numbers were "first quoted here". Only
  §12 quotes them now (FINDINGS.md:1543).
- **m3. Three entries now carry a later entry's answer.** Each is supported,
  but the text is not the original's:
  - E34 (FINDINGS.md:246-247): "The first hour's residual is the one-iteration
    Newton increment (E39, E39b)". The original said it was "not separated".
    On the sphere E39b gives 83%, not all of it.
  - E33 (FINDINGS.md:371-373) adds "that is the Newton lag (E43)" and "that gap
    is the per-tag transport (E43)".
  - E49's table (FINDINGS.md:1062): the C8 cell, "not separated (E33)", now
    reads "not separated in E33; the per-tag transport (E43)". The original
    E49 said "Which transport term makes it is not shown."
- **m4. The FINDINGS header is stale.** FINDINGS.md:10 says "E1–E75". E76 is
  in the register.

**Decisions (check 3)**

- **m5. Two states differ from the register.**
  - Row 57 (2M and P3): the register has `waiting_owner (gate still closed)`.
    DECISIONS.md:181-184 has "In force, waiting for upstream", outside the
    "Waiting for the owner" section.
  - Row 59 (D1, decision 9): the register reads D1 as the run and marks it
    done. DECISIONS.md:187-190 reads it as the user guide and marks it "Done in
    part". The DECISIONS reading fits the archived OPERATIONAL_TODO's B12. The
    departure from the register is not noted.

**Items (check 4)**

- **m6. FINDINGS §13's "tracked in" column is wrong for four rows.**
  - FQ-3 (FINDINGS.md:1556): it says "G4_TODO.md G4.9, or BACKLOG". FQ-3 is
    only in BACKLOG.
  - FQ-11 (FINDINGS.md:1561): it says "G3_TODO.md WP0, or BACKLOG". FQ-11 is
    only in G4_TODO, G4.6.
  - FQ-15 (FINDINGS.md:1563): it says "BACKLOG". FQ-15 is in G4_TODO's table
    "Energy items within M1 to M5".
  - FQ-17 (FINDINGS.md:1564): it says "BACKLOG". FQ-17 is in G4_TODO, G4.6.
  - FQ-21 and FQ-22 point to G3_TODO. They sit in G4_TODO's table "Items that
    G3 takes up", which then points into G3.
- **m7. Two rows have no home in the to-do files.** `LT-1` (shelved) is only
  in RUNS.md:110. `NS-1` (superseded) is only in DECISIONS.md:57. Both have
  register target "archive", so this is acceptable. It is noted because the
  check asks for G3_TODO, G4_TODO, BACKLOG or §13.

**Runs (check 5)**

- **m8. RUNS.md's prose is stale against its own branch.**
  - RUNS.md:68-74 says "The counts differ from the register's" because
    `runs.csv` counts files twice. The same branch has already corrected
    `runs.csv`, so the counts now agree.
  - RUNS.md:246-247 says E76 "reaches the record branch at H6". It has been on
    the record branch since `eec7f363`.
  - STATUS.md:37-38 says the same ("takes it in before H6"), though
    `89a1954b` has merged it.
- **m9. Some register values were copied or corrected without a note.**
  - RUNS.md:211: `v3_upd_default`'s Output column says "0000-0004". Scratch
    has 0000 to 0005, and RUNS.md's own second table lists 0005 (E76).
  - The eight ladder rungs show job "—" in the main table, although the
    second table gives their jobs.
  - `g2_v2_sphere_mix_oom_13538434`: RUNS.md gives the config
    `configs/g2_v2_sphere_mix.yml`, where the register has a file that does not
    exist. That is a sensible correction, but it is not noted.

**Nothing new claimed (check 9)**

- **m10. "5,434 files, identical to scratch" is wrong** (STATUS.md:46-47,
  RUNS.md:50-52). 5,434 is the whole archive: `scratch_tag_closure/` holds
  2,697, `scratch_claude_work/` 678, `worktrees/` 2,058, plus the README.
  `scratch_tag_closure/` is identical to scratch at 2,697 files.
- **m11. STATUS gives #95's head as `dcf7d086`** (STATUS.md:83, and G4_TODO's
  guide check). The branch and origin have been at `cd21af3a` since 11:29,
  with two docs-only commits. This was 20 minutes before `89a1954b`.
- **m12. Three figures in the README come from the owner's Claude memory**
  (`mpi-runs-terrabyte.md`), not from the originals, and no source is cited:
  - README.md:101: "Each rank peaked at about 17 GB". In the originals, 17 GB
    is the one-process `g2_v2_sphere_test`.
  - README.md:102: "A node has 160 cores and 1 TB".
  - README.md:176: "30 to 55% CPU per rank".
- **m13. INDEX.md:4-6 says each file was moved "unchanged, with `git mv`" and
  FINDINGS.md "is a copy instead".** README.md and OPERATIONAL_TODO.md are
  copies too, since new files took their paths.
- **m14.** The link fixes in `design/SUBGRID_AND_MICROPHYSICS_DESIGN.md` and
  `reference/` are not listed as such in the H4 commit message or in INDEX.md.
  INDEX.md does give the path map.
- **m15.** E16 gains "on 2026-09-10" for the owner's "no fifth twin"
  (FINDINGS.md:589). This is supported by the original's section 8, item 2,
  not by the original E16.
- **m16.** Two other entries gain dates and commits that are supported: E16's
  four commits, from `runs.csv`, and W6's `49b2ec97`, from `verify_g3.md`.

**Conflicts (check 10)**

- **m17. The 11 conflict rows found by H4-B have no live pointer.** G4_TODO.md:24
  says the full re-check moves to G4. It does not name `conflicts.csv`. §12
  lists `conflicts.csv` as a source (FINDINGS.md:1495), but not these rows. So
  the conflicting pairs stand in FINDINGS without a mark:
  - ±30,920 against ±30,915 J kg⁻¹ (E27, E35 against E46, E48);
  - 17 ms against 13.7 and 14.7 ms (E44b against E44c);
  - T4's control job, 27368587 against 27368036;
  - and the others the CSV lists.

  *Fix:* one line in G4_TODO pointing to those rows.

**Content no register row covers (check 11).** Guidance that still applies,
now only in the archive:

- **m18.** The approval rule "model code, a default, a tolerance, an energy
  reference ... need the owner's approval before they are written" (archived
  OPERATIONAL_TODO.md:14-16 and NEXT_SESSION.md:45-48) is in no live document.
  The OPERATIONAL_TODO stub says STATUS.md now holds "what needs approval".
  STATUS covers jobs only.
- **m19.** "Send job logs to scratch with `--output` and `--error`, or they land
  in the repository root" (archived NEXT_SESSION.md:268-269). The runscripts'
  `#SBATCH --output=tag-closure-c-%j.out` is relative. The sbatch example at
  README.md:72 passes neither option.
- **m20.** The hand-back list lost `<run>_parameters.toml` (archived
  LEVANTE_TASKS.md:487) and the reducer's tables. README.md, "Where results
  go", step 3, lists neither.
- **m21.** "Run the reducer before copying anything back" (archived
  README.md:82-86 and LEVANTE_TASKS.md:474-482) is only in the archive. The
  new README points to the archive for "the reducer".

## Check 11: the sample

Sixty paragraphs from the originals that are neither claims nor decisions.
"Live" means the content is in a live document. "Archive" means it is only in
`archive/2026-09-23/`, which a live document links: STATUS → INDEX, README →
the archived README, FINDINGS → the archived FINDINGS and LEARNINGS, and the
OPERATIONAL_TODO stub → the archived OPERATIONAL_TODO.

| # | Original | Paragraph | Now | State |
|--:|:--|:--|:--|:--|
| 1 | README, What will bite you | tcsh runscripts never syntax-checked | README, Submitting | live |
| 2 | README, same | run the reducer before copying back | archived README; pointer in README intro | archive (m21) |
| 3 | README, same | sphere numbers are not column numbers | README, Traps | live |
| 4 | README, same | five files per run | README, Where results go | live, without the reducer's table |
| 5 | README, same | committed summary one pass behind | RUNS, Other files in `output/` | archive, with pointer |
| 6 | README, same | every run records `commit_dirty: yes` | RUNS, How to read the table | live |
| 7 | README, Where the record lives | a number lives in one place | README, How the record is written | live |
| 8 | README, sphere configurations | configs fold in `numerics_sphere_he6ze10` | DECISIONS, B1's grid; details archived | archive, with pointer |
| 9 | README, Checking the configurations | `validate_configs.py` and mutations | archived README; README intro names it | archive, with pointer |
| 10 | README, Testing the analysis | `selftest.jl` | archived README; README intro names it | archive, with pointer |
| 11 | README, Before the first job | instantiate once; depot must match | README, Setup; Traps, the scratch depot | live |
| 12 | README, tcsh | `CONFIG=... sbatch` is not tcsh | README, Traps | live |
| 13 | README, Submitting | run the driver by hand on a login node | archived README | archive, with pointer |
| 14 | README, On terrabyte | `RUN_DIR`, `TAG_CLOSURE_JOB_ID` | README, Submitting | live |
| 15 | README, same | read the job's exit status | README, Traps | live |
| 16 | README, same | `provenance.txt` written either way | README, Where results go, step 2 | live |
| 17 | README, same | a crashed run is handed back | README, step 3 | live |
| 18 | README, Order and gates | nothing edits `ref_counter.jl`, a tolerance, the calibration | archived README | archive, with pointer |
| 19 | README, Keeping an earlier reading | subdirectory, never overwrite | README, step 4 | live |
| 20 | README, same | no commit in provenance → not analysed | README, Traps | live |
| 21 | README, Repairing a provenance | the repair procedure | README, Traps, with pointer | live |
| 22 | README, Open items | C3 on a sphere | BACKLOG | live |
| 23 | NEXT_SESSION, Rules | the owner decides every submission | README, Approval | live |
| 24 | NEXT_SESSION, Rules | parity with upstream | README, Traps; AGENTS.md | live |
| 25 | NEXT_SESSION, Rules | approval before writing a default, tolerance, reference | — | partly (m18) |
| 26 | NEXT_SESSION, Rules | never change a committed measurement | README, step 4 and conventions | live |
| 27 | NEXT_SESSION, Rules | pull before commit; several agents | STATUS, "Both rebase before pushing" | live |
| 28 | NEXT_SESSION, Traps | `.buildkite` needs a prepared machine | README, Setup | live |
| 29 | NEXT_SESSION, Traps | `LocalPreferences.toml` tracked on `main` | README, Traps | live |
| 30 | NEXT_SESSION, Traps | never `module purge`; Python module | README, Setup and Traps | live |
| 31 | NEXT_SESSION, Traps | commit before you submit; no git on nodes | README, the manifest | live |
| 32 | NEXT_SESSION, Traps | queues; logs to scratch with `--output` | README, Partitions (queues only) | partly (m19) |
| 33 | NEXT_SESSION, Traps | `run_c1_twin.jl` exits 1 on purpose | README, Traps | live |
| 34 | NEXT_SESSION, Traps | region and source tags go negative differently | FINDINGS M5 | live |
| 35 | NEXT_SESSION, Traps | `nonpositive_fraction` is by volume | FINDINGS M1 | live |
| 36 | NEXT_SESSION, Traps | `gross_relative` across a reference change | FINDINGS E15, R11; G4_TODO UG8 | live |
| 37 | NEXT_SESSION, Traps | closure quantities not interchangeable | FINDINGS W8 | live |
| 38 | NEXT_SESSION, Traps | `sypd` is in `.err` | FINDINGS M4 | live |
| 39 | NEXT_SESSION, How this series writes | cite, bound, commit the script, record falsified, recompute | README, How the record is written | live |
| 40 | LEVANTE_TASKS, After any batch job | `sacct` exit code | README, Traps | live |
| 41 | LEVANTE_TASKS, same | reduce before copying back | archived | archive (m21) |
| 42 | LEVANTE_TASKS, same | hand-back list with `<run>_parameters.toml` | README, step 3 (without it) | partly (m20) |
| 43 | LEVANTE_TASKS, Once per shell | `pmi2` does not work | README, Partitions | live |
| 44 | LEVANTE_TASKS, Not yet | `c0_sphere_deep` dropped, and why | RUNS, its row (`LT-1`) | live |
| 45 | OPERATIONAL_TODO, preamble | nothing approved unless it says so | — | partly (m18) |
| 46 | OPERATIONAL_TODO, preamble | priorities B/S/N, sizes S/M/L | archived; IDs kept in G4_TODO, BACKLOG | archive, with pointer |
| 47 | OPERATIONAL_TODO, section 0 | #89 review nits, `project_hash` | BACKLOG, Code housekeeping | live |
| 48 | OPERATIONAL_TODO, section 0 | CI phase C on the tagging files | BACKLOG, CI | live |
| 49 | OPERATIONAL_TODO, section 7 | prepared designs 1, 2, 4, 5, 6 | G4_TODO, verbatim (checked by diff) | live |
| 50 | OPERATIONAL_TODO, section 5 | worktrees | CONDENSE_PLAN, H7 | live |
| 51 | OPERATIONAL_TODO, Plan A.4 | E58's restart drift, how to separate it | BACKLOG, M6 | live |
| 52 | FINDINGS §8, item 3 | the bracket and repair smoke test | FINDINGS §2.3 intro | live |
| 53 | FINDINGS §8, item 2 | no fifth twin | FINDINGS E16 | live |
| 54 | FINDINGS §8, item 1 | the offset's design reasoning | FINDINGS §3.3 intro (summary) | archive, with pointer |
| 55 | FINDINGS §8, item 3 | sedimentation as transport, the design | FINDINGS §2.4 intro | live |
| 56 | LEARNINGS, A2 | sub-first-order ladders, floor near 1e-7 | FINDINGS W1; BACKLOG | live |
| 57 | LEARNINGS, A4 | the reduction's floor at t = 0 | FINDINGS W4 | live |
| 58 | LEARNINGS, A5 | the ratio hypothesis | FINDINGS W7, §12 | live |
| 59 | LEARNINGS, A3 | A3 alone as evidence | FINDINGS W5, §12 | live |
| 60 | LEARNINGS, C9 → C10 | read form A without the repair | FINDINGS E38, §12 | live |

## What was not checked

- **Whether the archive tags are on origin.** That needs a network call to the
  remote, which this check did not make. The tags resolve locally:
  `archive/g3-programme-2026-09-23` at `2d7fa835` and
  `archive/tag-closure-experiments-2026-09-23` at `eead88c3`.
- **The archive directory's `SHA256SUMS`.** It was not verified. Only file
  counts were compared.
- **LEARNINGS in full.** The 4 register rows and 5 more paragraphs were
  checked. The other ~1,400 lines are narrative behind FINDINGS entries, and
  they are in the archive unchanged.
- **The 11 conflicts found by H4-B.** They were not adjudicated. They are left
  for G4's re-check, as the register says.
- **Anchors.** Anchors were resolved by GitHub's slug rules as reimplemented
  here, not by rendering on GitHub.
- **The claims about #95's user guide in G4_TODO, G4.1.** Two were checked
  against `dcf7d086`'s `energy_source_tags_guide.md` and hold: UG8 and the
  "untested ground" list. The other eleven were not checked.

## Method

The scripts are in this session's scratchpad, not in the repository:

- Both trees were extracted with `git archive`.
- The FINDINGS entries were parsed by their bold IDs. Every number in each
  new entry was matched by value against its original entry. Thousands
  separators, minus signs and `×10ⁿ` were normalised. Commit hashes, dates,
  IDs and file:line references were excluded.
- Numbers not found in the entry were then looked up in the whole original
  FINDINGS, LEARNINGS, the register and `verify_g3.md`.
- Dates, hashes and job IDs were diffed per entry, and the order of numbers
  was compared pairwise. Every entry was then read beside its original.
- The file comparisons used `cmp`, and the renames `git diff -M`.
- Scratch and archive files were counted with `os.walk`, without following
  links.

## Re-check after the fixes

Checked read-only on `claude/tag-closure-condense` at `274f55b0`, 2026-09-23,
12:20. The fix commit changed only FINDINGS, STATUS, RUNS, README, G4_TODO,
DECISIONS, `archive/2026-09-23/INDEX.md` and this file. The archive's other
files, `design/`, `reference/` and G3_PLAN.md are unchanged since `89a1954b`.
One correction to the report above: its verdict says "24 minor gaps", and the
list has 21, m1 to m21.

**Verdict: no blocking gap remains.** B1 and B2 are fixed. Checks 2 and 8 are
clean on the new head. Of the 21 minor gaps, 15 are fixed and 4 were accepted.
The other 2, m12 and m13, are only partly fixed. The fixes added two more
small errors, n1 and n2. n3 and n4 are older slips that surfaced during the
re-check. None of these touches a finding.

### B1 and B2

- **B1, fixed.** E50 keeps "decision 7 of 2026-09-18". A dated erratum gives
  the original's 2026-09-17 and the source of the new date: the archived
  OPERATIONAL_TODO and DECISIONS.md (FINDINGS.md:1091-1093).
- **B2, fixed.** §12's row now reads "E34's reading of the audit's first-hour
  residual as the initial adjustment" (FINDINGS.md:1534). E13 is no longer
  listed. E13's entry and FQ-5 are unchanged.

### m1 to m21

| # | State | Note |
|:--|:--|:--|
| m1 | fixed | E22 has "at 24 h (−20,566 J kg⁻¹, as in C3)", and M6 "from t = 0 on". |
| m2 | fixed | E73's erratum keeps "about 2× after the default's build" and says the old figures are "now in §12". |
| m3 | fixed | E33, E34 and E49's C8 cell again say what they measured, and give the later answer as later. E34's "99% on the column (E39), 83% on the sphere (E39b)" matches both entries. |
| m4 | fixed | The header reads E1–E76. |
| m5 | fixed | DECISIONS notes both departures from the register, rows 57 and 59. |
| m6 | fixed | FQ-3 → BACKLOG, FQ-11 and FQ-17 → G4_TODO G4.6, FQ-15 → G4_TODO "Energy items within M1 to M5", FQ-21 and FQ-22 → G4_TODO "Items that G3 takes up". Each place was checked, and each holds the ID. |
| m7 | accepted | — |
| m8 | fixed | RUNS.md:70-74 says the counts agree with the corrected register. RUNS.md:250 and STATUS.md:37-38 say E76 is ported and on the condense branch. |
| m9 | fixed | RUNS gives `v3_upd_default` 0000 to 0005. The ladder rungs point to the second table. The OOM run's config correction is listed. |
| m10 | fixed | STATUS.md:46-50 and RUNS.md:50-54: 2,697 files in the copy of scratch, 678 in `claude_work`, 2,058 in the worktree captures, 5,434 in all. The counts match `find`: the copy of scratch has 2,697 files, the same as scratch. |
| m11 | fixed, with one slip (n1) | STATUS gives #95 as open at `cd21af3a`, no longer a draft. `gh pr view 95` confirms: `isDraft: false`, head `cd21af3a`. |
| m12 | partly | Sources are now given. `sinfo -p hpda2_compute`: 160 CPUs and 1,020,721 MB, so "about 1 TB" holds. The per-rank figure is converted wrongly; see n2. README.md:196-197 says the 30 to 55% CPU was "not recorded elsewhere". It is recorded in the owner's memory note `mpi-runs-terrabyte.md`, which does not say `top`. |
| m13 | partly | INDEX now says README.md and OPERATIONAL_TODO.md were moved too. `git log --follow` does follow their history. But the new sentence at INDEX.md:8-10 says the moved live files "changed only in links". G3_PLAN.md, moved from G3_WATER_PLAN.md, changed in its #95 sentence, which is not a link (G3_PLAN.md:26-27). The `reference/` banners also gained the sentence "Until 2026-09-23 the roadmap stood at the top of OPERATIONAL_TODO.md". |
| m14 | accepted | INDEX gives the link changes (with m13's caveat). |
| m15 | accepted, with a caveat | The header note (FINDINGS.md:9-10) names "the register, RUNS.md or `review/verify_g3.md`" as the sources of added dates and commits. E16's "2026-09-10" comes from the original FINDINGS §8, item 2. E41's date comes from the original E40. Both are supported, but by sources the note does not name. |
| m16 | accepted | — |
| m17 | fixed | §12's intro (FINDINGS.md:1500-1503) and G4_TODO.md:24-31 point to the 11 rows marked H4-B. G4_TODO says E58's and E54's restart differences "differ by orders of magnitude". That holds for `ρe_tot` (1.604e-4 against 1.7e-9) and `u₃` (1.543e-11 against 3e-9), not for `ρ` (1.758e-10 against 1.5e-10). |
| m18 | fixed | The approval rule is in STATUS, "What needs approval", and in README, "Approval". Both match the archived OPERATIONAL_TODO.md:14-16. |
| m19 | fixed | README's sbatch example gives `--output` and `--error` under `$SCRATCH/tag_closure/logs/`, which exists. |
| m20 | fixed | The hand-back list now has `<run>_parameters.toml` and the reducer's tables. |
| m21 | fixed | README, "Where results go", step 3 runs `reduce_run.jl` before the copy. |

### New or left by the fixes (all minor)

- **n1. STATUS.md:86: "CI was running there at about 13:00".** The fix was
  committed at 12:18 CEST, so 13:00 had not come yet. #95's checks at
  `cd21af3a` started at 11:29:58 CEST (09:29:58 UTC). At 12:20 CEST, 59 of 71
  were still running.
- **n2. README.md:107: "16.75 GB" per rank.** `sacct -j 13504999,13505896 -o
  JobID,NTasks,MaxRSS` gives step `.0`, with 24 tasks, at 16,752,519K and
  16,749,911K. Slurm's K is KiB. So the peak is 15.98 GiB, or 17.15 GB. The
  README read K as 1,000 bytes. The old "about 17 GB" was right in GB.
- **n3. RUNS.md:201: the OOM run's Output column still says "0001".**
  Scratch has only `output_0000`, and RUNS.md:272-274 says so. The
  corrections list at RUNS.md:75-78 does not mention the index. This dates
  from H4, and I missed it in the first check.
- **n4. STATUS reports H5 as closed.** STATUS.md:46 says "its gaps are
  fixed", and STATUS.md:112 marks H5 "done ... fixed". The report above
  counted 21 minor gaps, not 24. With n1 to n4 and the partial m12, m13 and
  m15, that holds for the blocking gaps only.

### Checks 2 and 8, on the new head

- **Check 2, numbers: clean.**
  - No number in the new FINDINGS is missing from the original FINDINGS or
    the register. The same value-matching script as above was used, and the
    rows it flags are the same parse artefacts as before.
  - The edited entries gained two numbers, E34's 99 and 83, both from E39 and
    E39b. The one new date is E50's erratum date, 2026-09-23. No other value
    changed: every line of `git diff 89a1954b 274f55b0 -- FINDINGS.md` was
    read.
  - The FINDINGS header, section intros, §12 and §13 have no number or date
    that is missing from the originals or the register.
  - Numbers added to STATUS, RUNS and README were checked against their
    sources: 2,697, 678, 2,058 and 5,434 against `find`; 160 and "about
    1 TB" against `sinfo`; 16.75 against `sacct` (n2).
- **Check 1, re-run: unchanged.** All 130 IDs, register numbers and evidence
  pointers are present.
- **Check 8, links: clean.** 219 relative Markdown links, anchors included, in
  every live `.md` outside `archive/`: 0 broken.

### Checked now that could not be checked before

- **All seven archive tags are on origin**, as annotated tags, and each
  matches the local tag object:
  - `archive/g3-programme-2026-09-23`: tag object `79906aa9`, commit `2d7fa835`;
  - `archive/tag-closure-experiments-2026-09-23`: tag object `cc397f1c`,
    commit `eead88c3`;
  - `archive/c1b-wip-backup`, `archive/c1c-sgs-diffusion`,
    `archive/m3-species-lists`, `archive/tagged-tracers` and
    `archive/upstream-vwb-species-guard`.

  The source is the GitHub API, `git/matching-refs/tags/archive`.
