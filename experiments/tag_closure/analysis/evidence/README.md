# G3 phase 1: the evidence pipeline

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
                         [--ladder-share] [--json PATH]
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
    the common-length prefix compared, with an explicit `NOTICE:` line;
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

## test_compare_runs.py

```sh
python3 test_compare_runs.py            # or: python3 -m unittest test_compare_runs -v
```

45 tests (about 12s, mostly the E73 fixture rebuild and the synthetic
netCDF writes), in four
groups:

  1. **`CompareRunsCLIMutationTests`** -- the original six mutation tests
     (a real energy run pair copied from `v3_upd_copies/output_0000` on
     scratch, mutated with netCDF4 in `r+` mode, run through the real CLI as
     a subprocess), plus three more: a within-run time shift in a
     **non-`rhoa`** file (kills the "RunCoords disabled" mutant, which a
     shift in `rhoa` alone cannot), `output_active`/a bare run root/the same
     directory twice refused. `--tags sfc,rad,mp` pins these to the three
     tag files actually copied, since the tag list now defaults to *every*
     tag in the YAML (8, for this config).
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
     `--judge` refusing a non-water `--family`); `--bitwise-tags`; and
     `--ladder-share` on two different `z` grids (3 vs. 5 levels), checking
     it falls back to the column-integrals-only mode and does not attempt a
     level-wise comparison.
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
