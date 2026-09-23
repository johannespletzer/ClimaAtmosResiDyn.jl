# Review of the phase-1 evidence tools (G3 WP0, old item 1.8)

Written on 2026-09-23 by an independent agent that wrote none of the tools.
It covers `analysis/evidence/`: `compare_runs.py` (the verifier),
`test_compare_runs.py`, `manifest.py`, `inventory.py`, `runs_inventory.csv`,
`README.md` and `e73_reproduction.txt`. The old comparator,
`analysis/increment/tag_correctness.py`, was read for comparison.

The state reviewed:

| What | Value |
|:--|:--|
| Worktree | `ClimaAtmosResiDyn-exp`, detached; `1ec7a87f` at the start, `aab4d94c` at the end (the parent session committed during the review) |
| Tools | added in `8023664b`, last touched in `2a9d4619`; unchanged during the review |
| sha256 (first 16) | `compare_runs.py` `e861b0403402ba66`, `inventory.py` `e89f443816dcb9f0`, `manifest.py` `a3fedf4146326d07`, `test_compare_runs.py` `541020069ccd55b0` |
| Python | `python/3.12` (3.12.8), numpy 2.5.1, netCDF4 1.7.4 |
| Budgets | `G3_PLAN.md` section 6.1, set by the owner on 2026-09-23 |

Every statement below comes from a command I ran, unless it says otherwise.
Synthetic runs and mutated copies of the tools were built in my scratchpad.
Nothing under the output root on scratch was written. No tool was modified.

## Verdict

**The numbers the verifier prints today are right. But its tests would not
notice if they became wrong, and it has no guard against non-finite input.**
Fix both before the verifier is extended to water, or before it judges any
budget. The other findings are gaps that the water extension must close. None
of them changes a number that has been published.

What holds, checked by a command:

  - **The metrics are exact.** An independent script recomputed L1, L∞ and
    Δ∫/∫ for all 28 non-zero rows of E73. It uses a uniform 50 m Δz taken
    from `z_max/z_elem`, not the verifier's reconstruction. The largest
    relative disagreement is 0.
  - **E73 reproduces.** A fresh run of the verifier on
    `v3_upd_copies/output_0000` against `v3_upd_default/output_0002` gives
    the table in `e73_reproduction.txt` character for character.
  - **The Δz reconstruction is right, also on a stretched grid.** On the
    10-level stretched sphere grid of `b1_base` (`dz_bottom` 500 m, `z_max`
    30 km), the rebuilt faces start at 500 m and end at 30000 m, to 1.2e-16
    relative. That matches ClimaCore, where a centre is the midpoint of its
    faces. On that grid the old script's `np.gradient(z)` is wrong by +24%
    in the lowest cell and −4% in the top one. On the uniform G3 columns
    (DYCOMS, BOMEX, RICO, TRMM: all `z_stretch: false`) the two agree
    exactly. So "the measures are those of `tag_correctness.py`" (plan 6.1)
    holds for G3's columns, but not on a stretched grid.
  - **Time alignment is exact.** An hour is looked up at exactly `h*3600` s,
    and the time and date arrays of the two runs must be equal.
  - **Signed zeros are seen.** The parity check compares bit patterns.
  - **The tests pass.** 6 of 6 pass in 2 s.
  - **`manifest.py` works on a detached worktree.** On this worktree and on the
    G3 run worktree `-wedmf-run` it records `branch: detached`, the HEAD,
    LocalPreferences and the rest, without writing to the worktree. `--verify`
    reports CLEAN right afterwards. After a hashed file changes it reports
    `CHANGED` and exits 1.

## Mutation analysis of the test suite

I copied the verifier and its tests to my scratchpad. Then I injected 19
defects into the copy, one at a time, and ran the six tests against each.
**17 of the 19 defects pass all six tests.**

| Injected defect | Caught? |
|:--|:--|
| Weights from the run's `rhoa` instead of the reference's | no |
| Δz = 1 (no thickness weighting) | no |
| L1 without mass weighting | no |
| L∞ as the largest pointwise relative error | no |
| Run's time index off by one | **yes** |
| Within-run coordinate check (`RunCoords`) disabled | no |
| Parity through `==` instead of bit patterns | **yes** |
| Date check removed (equal lengths) | no |
| Date check removed (common prefix) | no |
| `output_active` accepted | no |
| Non-column geometry accepted | no |
| `(time, z)` files not transposed | no |
| Top-face check against `z_max` disabled | no |
| dtype check disabled | no |
| Hour found by the nearest time, not the exact one | no |
| Sign of Δ∫/∫ flipped | no |
| Δz from `np.gradient(z)` | no |
| Parity checked at the first time only | no |
| Tag metrics from the lowest level only | no |

The six tests check that bad input is refused. They do not check a single
metric value. Test 1 only checks that identical runs give 0, and every
formula above gives 0 there.

## Findings

Ranks: **blocking** means fix it before the verifier produces a G3 number or
judges a budget. **Should fix** means fix it in the water extension or in the
submit path. **Minor** means it is cheap and not urgent.

### Blocking

**B1. The tests do not pin any metric.**
`test_compare_runs.py:114-189`.

  - *Evidence.* The mutation table above. A verifier that weights by the
    wrong density, drops Δz, or reports a pointwise L∞ passes all six tests.
  - *Scenario.* The water extension is next, and a Sonnet builder agent
    writes it (plan section 7). Suppose it refactors `tag_row_metrics` and
    weights by the run's `rhoa`. Nothing fails. On default against copies
    the parent is the same, so the numbers do not move. On the V-W4 ladder
    they do move, and every rung's per-tag number is then off without
    warning. G3 criterion 1 sends every headline number through this code.
  - *Fix.* Add tests that pin values:
      + Two synthetic runs on a nonuniform grid (for example centres
        25, 100, 250 m) with ρ and q chosen so that L1, L∞, Δ∫/∫ and
        `max_abs_error` have closed forms. Assert each to 1e-14 relative.
        A nonuniform grid also kills the `np.gradient` and Δz = 1 mutants.
      + A run whose ρ differs from the reference's, to pin which ρ weights.
      + A perturbation at the top level and at the last time, to kill the
        first-level and first-time mutants.
      + A regression test against E73's JSON: all 32 rows to 1e-15.
      + One test per refusal that has none: `output_active`, a bare run
        root, a non-column file, a `(time, z)` file, a dtype mismatch, a
        top face that disagrees with `z_max`, a date change, and a time
        shift in one file other than `rhoa` (for `RunCoords`).
    Then rerun the mutation script. Every mutant above must be caught.

**B2. Non-finite and fill values give exit 0 and numbers that pass a budget.**
`compare_runs.py:172`, `:186`, `:337-366`, `:513`.

  - *Evidence.* On synthetic copies of `v3_upd_copies/output_0000`:
      + One NaN in the run's `e_src_sfc` at 24 h gives exit 0, with L1,
        L∞ and Δ∫/∫ all `nan` for that hour. The test `L1 > 0.02` is
        `False` for NaN, so a budget check written that way passes it.
      + The netCDF default fill value (9.97e36) in the run's tag at 24 h
        gives exit 0 and an L1 of 1.8e33. `set_auto_mask(False)` turns fill
        values into data.
      + A NaN in the run's `ta` gives exit 0 and the parity line
        `max|Δ|=nan`.
      + `json.dumps` writes NaN as the bare token `NaN`, which is not valid
        JSON. A strict reader rejects the whole report.
  - *Scenario.* A run that blows up in the last hour, as issue #64's
    run did, or a file that is cut short while the job still writes. The
    budget judgement in the water extension then passes the tag.
  - *Fix.* After reading each field, check it. Die if any value in the tag,
    `rhoa`, `hus` or Δz is non-finite, or equals the variable's `_FillValue`
    or the netCDF default fill for its dtype, and name the variable, level
    and time. For parent parity, report NaN counts separately and treat any
    NaN as a parity break. Write JSON with `allow_nan=False`. Keep
    `set_auto_mask(False)` for the signed zeros, but do this check next to
    it.

### Should fix

**S1. The parent-parity check is narrower than it looks, and never fails.**
`compare_runs.py:64`, `:123-128`, `:180-185`, `:458-466`.

  - *Evidence.*
      + The default parent set is the intersection of the two runs'
        variables. With `arup` deleted from the run, the report compares
        `rhoa` and `ta` only, with exit 0 and no notice.
      + `q_gas_` is excluded (`:64`). The D4-W configs committed in
        `c537903b` write the passive tracer `q_gas_A`, which is a model
        field for the water tags and must be bit for bit.
      + `qv_tag_` is not excluded. The model registers `qv_tag_<name>` for
        every water tag (`src/diagnostics/tagged_water_diagnostics.jl`). It
        would be read as a parent field and show as a parity break between
        default and copies.
      + A field without `z` stops the whole run. A synthetic `pr` with
        dimensions `('time',)` in both runs gives `ERROR: ... unsupported
        geometry`, exit 1. `w0a_*`, `w0c_d4w_untagged` and
        `w1_d4w_grid_tags` all write `pr`, `evspsbl` and `lwp`. So the
        default call on V-W1 against its twin fails. That failure is loud.
      + A parity break is reported but the exit code stays 0.
      + The check sees hourly snapshots of the fields in the output list.
        The fork's parity rule (`docs/clima_atmos_specific.md`, "Fork parity
        with upstream") asks for the prognostic state and every output
        field. G3 criterion 3 says "every model field".
  - *Scenario.* V-W1 (tags on against the untagged twin) is a parity claim
    for criterion 3. If a field is missing from one run, the claim silently
    rests on fewer fields.
  - *Fix.*
      + Take the union of the two runs' variables, and fail on a variable
        present in only one run, unless `--allow-missing NAME` names it.
      + Exclude diagnostics by an explicit list of prefixes that matches the
        claim contract: `e_src_`, `e_prc_`, `e_tag_`, `q_prc_`, `q_tag_`,
        `qv_tag_`, `pr_tag_`, and the rain and snow tag prefixes once WP4b
        names them. Keep `q_gas_` in the parent set.
      + Support fields on `('time',)` (surface fields) for parity.
      + Add `--expect-parity`, which exits nonzero on any parity break.
        Criterion 3's runs use it.
      + For criterion 3, compare the final checkpoint too (the HDF5 restart
        file), field by field, bit for bit.

**S2. The verifier does not check that a pair of runs may be compared.**
`compare_runs.py:412-427`.

  - *Evidence.* It reads neither run's `provenance.txt` nor a manifest. It
    does not compare float type, `ntasks`, machine, Julia version or the
    Manifest hash, though the README says bit-for-bit only holds within one
    of each. It does not check which run is the copies run. Passing the
    same directory twice gives a clean pass.
  - *Scenario.* The reference and the run are swapped. Then L1 is
    normalised by the default run instead of the copies, and every per-tag
    number changes a little, with no error. Or two runs on different
    machines are called "not bitwise" when that was never expected.
  - *Fix.*
      + Read both runs' `provenance.txt` and, once they exist, their
        manifests. Record both in the JSON.
      + Refuse a parity verdict unless machine, `ntasks`, `FLOAT_TYPE`,
        Julia version and the Manifest hash agree. Also refuse it when
        `use_krylov_method` or `use_newton_rtol` is on, as the parity rule
        says.
      + Diff the two merged YAMLs. Fail on any difference outside an
        allowlist: the mode key, `diagnostics`, `output_dir`, `toml`
        (compare the hashes of the files it names instead), job fields.
      + For a per-tag budget, require `water_tag_updraft_copy: true` in the
        reference and `false` in the run.
      + Refuse two paths that resolve to the same directory.

**S3. With two different atmospheres, the weights and "∫run" are not what
their names say.** `compare_runs.py:341-342`, `:481`, `:502`.

  - *Evidence.* `w = ρ_ref Δz` for both runs, so `integral_run` is
    `Σ q_run ρ_ref Δz`, not the run's own column integral. That is fine for
    default against copies, which share one atmosphere. It is not fine for
    the V-W4 ladder, the Float32 twin or a restart pair.
  - *Scenario.* V-W4 compares the copies at dt 120 s and dt 30 s. The two
    atmospheres differ. The reported Δ∫/∫ mixes the change of the tag with
    the change of ρ, and is labelled as a change of the tag's integral.
  - *Fix.* When the parent parity of `rhoa` fails, print a notice. Report
    each run's own integral (`Σ q_run ρ_run Δz`) next to the ρ_ref-weighted
    one, and name the JSON fields for what they are. The share metric for
    the ladder is in requirement R12.

**S4. Units and epochs are not compared.** `compare_runs.py:165-193`.

  - *Evidence.* A run whose `date:units` names another epoch
    (`seconds since 1999-06-01`), with the same numbers, passes with exit 0.
    So does a tag whose `units` attribute reads `kJ kg^-1`.
  - *Scenario.* Two runs with different `start_date` values are compared as
    if they were the same day. The forcing and the insolation differ.
  - *Fix.* Require the `units` of `time`, `date` and `z`, the `start_date`
    attribute, and each variable's `units` to be equal in both runs. For a
    tag, also check them against the expected unit (`kg kg^-1`, or `J kg^-1`
    for energy).

**S5. A tag missing from the reference is dropped without notice.**
`compare_runs.py:110-120`, `:421`.

  - *Evidence.* With `e_src_rad` deleted from the reference, the default
    call compares `sfc` only and exits 0.
  - *Fix.* Take the tag list from the run's own YAML (`energy_source_tags`,
    later `water_tracers`). Fail if the two YAMLs list different tags, or if
    a listed tag has no file in either run.

**S6. Restart segments cannot be compared.** `compare_runs.py:206-220`.

  - *Evidence.* `v5_c5_continuous/output_0000` has times 0 to 86400 s.
    `v5_c5_restarted/output_0000` has 43200 to 86400 s. With `--hours 13,24`
    the verifier compares the prefixes and dies: "disagree within their
    common 13-time prefix". The failure is loud, but restarts are then not
    supported at all. V-W9 and criteria 2 and 11 need them. The
    `q_tag_fix_*` ledgers also reset at a restart.
  - *Fix.* Align by exact time values (the intersection), not by position.
    Let `--run` take an ordered list of segments that form one lineage.
    Check that the segments join without a gap, and difference cumulative
    ledgers within a segment only.

**S7. The manifest records hashes, not content. So a dirty run can be
detected but not rebuilt.** `manifest.py:134-138`, `:81-96`.

  - *Evidence.* `diff_sha256` and one combined hash of the untracked files
    are stored. The diff itself and the untracked files are not. The
    README's own example, the old `-upd-run` worktree, no longer exists. Its
    `experiments/` was an untracked copy.
  - *Scenario.* A run is submitted from a dirty worktree, and the worktree
    is later cleaned or removed. The manifest proves that the state was
    different, but nobody can say what it was. The housekeeping of
    2026-09-23 lost 34 `.out` logs this way.
  - *Fix.* Pick one of the two:
      + Refuse a dirty worktree at submission, apart from an allowlist
        (`LocalPreferences.toml`).
      + Or write `git diff HEAD --binary` and a tarball of the untracked
        files next to the manifest, and hash those.
    Also record whether HEAD is on a remote ref
    (`git for-each-ref --contains HEAD refs/remotes`). A detached HEAD that
    is on no ref is lost when the worktree is removed and git garbage
    collection runs. Today's G3 HEAD `c537903b` was on
    `origin/claude/tag-closure-record`, so it is safe.

**S8. The manifest misses parts of the environment.** `manifest.py:33`,
`:107-116`.

  - *Evidence.*
      + The Julia version is taken from `julia +1.11 --version`. The submit
        path (`runscripts/tag_closure_common.sh:224-228`) takes `JULIA` and
        `JULIA_CHANNEL` from the environment. A job run with another
        channel or binary is recorded wrongly.
      + No loaded modules are recorded (compiler, MPI). The script loads
        them from a pairing file whose hash is not recorded either. The
        MPI library decides whether an MPI run is bitwise.
      + `JULIA_DEPOT_PATH` is not recorded, nor are the Julia and CliMA
        environment variables (`JULIA_NUM_THREADS`, `JULIA_CPU_TARGET`,
        `CLIMACOMMS_*`, `OMP_NUM_THREADS`).
      + Only `Manifest-v1.11.toml` is hashed. A 1.10 run uses
        `Manifest-v1.10.toml`, which git ignores, so no other record sees
        it either.
      + Ignored files are invisible. `.gitignore` ignores `*.json`, `*.nc`,
        `*.in` and `*/Manifest*.toml`.
      + Inputs outside the repository are not hashed: `restart_file`,
        `external_forcing_file` and the ERA5 directories.
      + `v5_c5_restarted`'s `restart_file` points into `output_active` of
        another run. That link moves when the other run is rerun.
  - *Fix.*
      + Record the Julia binary the job will use and its `versioninfo()`.
        Pass the same `JULIA` and `JULIA_CHANNEL` that the submit script
        uses.
      + Record `module list`, the pairing file's hash, the depot path and
        the environment variables listed above.
      + Hash every `.buildkite/Manifest*.toml` that exists.
      + Resolve every path key in the config (`restart_file`,
        `external_forcing_file`, `toml`, `era5_*`). Record each real path
        and its hash, or its size and mtime for large files. Refuse a path
        that goes through `output_active`.

**S9. Nothing ties a manifest to its run, and the queue wait is not
covered.**

  - *Evidence.* The manifest is written before `sbatch`. At that point the
    `output_XXXX` index is not known, and `provenance.txt` does not name the
    manifest. The job may start hours later. The compute nodes have no git,
    so the job cannot run `--verify`.
  - *Fix.* The submit path passes the manifest's path and its sha256 to the
    job. The job writes both into `provenance.txt` and copies the manifest
    into the output directory. Also store a list of per-file sha256 values
    for the tracked and untracked files under `src/`, `config/`, `toml/`,
    `.buildkite/` and `experiments/`. The job can then check them with
    `sha256sum -c`, without git, before the first step. This is the WP0 item
    "the manifest in this session's submit path".

**S10. The inventory's `graceful_exit` column does not mean a graceful exit.**
`inventory.py:133`.

  - *Evidence.* `maybe_graceful_exit` (`src/callbacks/callbacks.jl:364-393`)
    creates `graceful_exit.dat`, holding `0`, at the first step of every
    run. The OOM run `g2_v2_sphere_mix_oom_13538434` has `exit_status` 1 and
    `graceful_exit` True.
  - *Fix.* Rename the column to `stop_file_present`, or read the file and
    report whether it holds `1`. Take the outcome from `exit_status` and
    from `n_times` against the expected count, `t_end/period + 1`.

**S11. The inventory has no classification, and its key is not unique.**
`inventory.py:136`, `runs_inventory.csv`.

  - *Evidence.*
      + Every row is `unclassified`.
      + The CSV covers 54 run directories on this scratch root. The run
        register `review/register/runs.csv` has 113, and 40 of them
        (`a1_*`, `a2_*`, `a3_*`, and more) are not in the inventory.
      + For `c0_sphere_audit` the two disagree. The inventory says commit
        `72a1bc6a`, job `13383685` (terrabyte). The register says
        `bcbe190f`, job `27369268`, which looks like Levante's numbering.
        So a run name is not unique across machines.
      + The CSV is stale already. `v3_upd_default/output_0004` shows no
        provenance and `is_active` True, but it finished at 09:15. And
        `output_0005` is missing. The CSV does not say when it was made.
  - *Fix.* See "Classifying the inventory" below.

### Minor

  - **M1. README errors.** `README.md:377-389` says Julia's `isequal` does
    not treat two NaN payloads as equal. It does treat them as equal. The
    verifier's bit check is stricter than `isequal` there, which is fine,
    but say so. `README.md:246-247` says neither report is a hard failure,
    but a dtype or shape mismatch in parity dies (`compare_runs.py:284-287`).
    `README.md:351-356` describes a test on the `-upd-run` worktree, which
    has been removed.
  - **M2. `git diff` misses binary changes.** `manifest.py:137`. Without
    `--binary`, a second change to an already modified binary file gives the
    same diff text, "Binary files ... differ", and so the same hash. Use
    `git diff HEAD --binary --no-ext-diff --no-textconv`.
  - **M3. Porcelain v1 quotes paths.** `manifest.py:84-85`. A path with a
    space arrives as `"a b.txt"`, is not a file, and the tool dies. Use
    `-z`.
  - **M4. The top-face tolerance ignores the dtype of `z`.**
    `compare_runs.py:274`. Float32 runs write `z` as float32. On the
    stretched grid of `b1_base`, rounded to float32, the rebuilt top face is
    off by 2.0e-8 relative. That exceeds 1e-9, so the verifier dies. G3's
    columns are uniform, so this only matters on the sphere. Use a few
    hundred times `eps(dtype(z))`.
  - **M5. Only `_1h_inst` files are read.** `compare_runs.py:107`, `:134`.
    Other periods and reductions (`_1h_average`, `_6h_inst`) are ignored
    without notice. Requirement R9 needs averages.
  - **M6. The tests read non-durable data.** `test_compare_runs.py:41-43`
    read `v3_upd_copies/output_0000` on scratch. Point them at the minimal
    datasets in `ClimaAtmosResiDyn-archive/reference_data/`, and check the
    hashes.
  - **M7. The warning filter does not act under unittest.**
    `test_compare_runs.py:39`. Under `python3 -m unittest` the numpy
    DeprecationWarnings still print, because unittest resets the filters.
    This is cosmetic.
  - **M8. The directory name is checked, not what it points to.**
    `compare_runs.py:86-101`. A symlink named `output_0003` that points into
    another run is accepted. The resolved path is recorded, so the case can
    be traced. Refuse a symlink.
  - **M9. The inventory counts times in `ta` only.** `inventory.py:75-92`.
    Runs without `ta` output (the `v5_c5_*` runs, `b1_base`, the `c1`, `c5`
    and `d1` runs) show no time count. Count the times of every
    `*_inst.nc` file, and report the smallest and largest count.

## Classifying the inventory (the WP0 item)

The old item 1.4 asked for a status per run: PR head, historical,
superseded, failed or proposed. The tool leaves all of them `unclassified`.
Most of the classification can be done by machine. I propose these columns,
for the owner to confirm:

  - **Key:** `machine`, `run`, `output_index`. Take `machine` from
    `provenance.txt`. `c0_sphere_audit` shows why the machine is needed.
  - **Outcome** (by machine): `complete` when `exit_status` is 0 and every
    output file has `t_end/period + 1` times; `truncated`; `failed` when
    `exit_status` is not 0; `no_provenance` when the run never started, or
    is still running (the `*_dt30/60`, `*_newton2` and `*_upwind` rows).
  - **Code** (by machine, from git): whether the commit is on `main`, is the
    head of a merged PR (for #95, `b9c6e7b0`), is on a remote branch, or
    is on no ref.
  - **Lineage** (by machine): `superseded_by`, the newest `output_XXXX` of
    the same run with the same config hash. `restart_of`, the resolved
    `restart_file` source. `renamed`, such as
    `v3_upd_default_prefix_e010f780_superseded` and the `_oom_` run.
  - **Configuration** (by machine, from the YAML): geometry (column or
    sphere), family (energy, water, none), mode (`*_updraft_copy`),
    `FLOAT_TYPE`, `ntasks`, microphysics, the `turbconv` scheme, and the
    config's sha256.
  - **Evidence** (joined from `review/register/runs.csv` on the key): the
    purpose, the finding IDs, and whether the run is in the archive.
  - **Manifest:** its path and sha256, empty for every run before G3.
  - **Status** (by a person, from the columns above): `pr_head`,
    `historical`, `superseded`, `failed` or `proposed`. Add `cited` when a
    finding uses the run.

Also write a header row with the time, the root and the tool's sha256, and
regenerate the CSV at each gate.

## Requirements for the water extension

These are input for the `clima-analysis-builder`. The budgets are the
owner's, from plan 6.1. Where 6.1 leaves a definition open, I give one
and mark it **proposed**, for the owner to set before any G3 run.

**R1. Field families.** Take the tag list from `water_tracers` in each run's
merged YAML, not from file names. Fail if the two lists differ, or if a
listed tag has no file. The families:

| Family | Output name | Role |
|:--|:--|:--|
| tag | `q_tag_<name>` | judged per tag |
| residual | `q_tag_res` | closure, never a tag (it has the `q_tag_` prefix) |
| ledger | `q_tag_fix_<name>` | cumulative since the segment started; reset at restart |
| vapour share | `qv_tag_<name>` | derived; not a parent field; not judged |
| copies' repair | `q_tag_upfix_<name>` | from WP3; cumulative |
| copies | updraft fields per tag, names from WP3 | judged with updraft weights (R8) |
| rain and snow | names from WP4b-D (`rtag`, `stag`) | closure against `husra`, `hussn` (R9) |
| precipitation | `pr_tag_<name>` | surface field, dimensions `('time',)` (R9) |

Keep the families in one table in the code. WP3 and WP4b then add their
names in one place.

**R2. Region and source tags.** A tag is a region tag when its YAML entry
has no `source` key. This is the model's own rule
(`water_region_tag_state_names`). The partition is the set of region tags.
On each run, check that `Σ region q_tag + q_tag_res = hus` holds at every
level and hour, to 1e-12 relative in Float64 (**proposed**). That catches a
missing or misnamed tag.

**R3. Parent set for water.** These must be present in both runs and
bitwise equal: `rhoa`, `ta`, `hus`, `clw`, `cli`, `husra`, `hussn`, `wa`,
`q_gas_A`, `pr`, `prra`, `prsn`, `evspsbl`, and the updraft and environment
fields that the D4-W configs write (`arup`, `rhoaup`, `waup`, `husup`, and
the rest). Surface fields have dimensions `('time',)`. See S1 for the
exclusions and for `--expect-parity`.

**R4. Metrics per tag and hour.** Keep L1, L∞, Δ∫/∫ and `max_abs_error` as
they are, with `w = ρ_ref Δz`. Add:

  - `abs_L1 = Σ |Δq| w` in kg m⁻²;
  - `total_ref = Σ q_tot,ref w`, with `q_tot` from the reference's `hus`;
  - the share `S = Σ q_tag,ref w / total_ref`.

**R5. The budget judgement.** Add `--judge`. It exits nonzero when any
budget fails, and writes the verdict of every row to the JSON, together
with the budget table and the commit of `G3_PLAN.md` it came from.

| When | Region tag | Source tag |
|:--|:--|:--|
| 24 h | L1 ≤ 0.02, L∞ ≤ 0.05 | L1 ≤ 0.02, L∞ ≤ 0.05 |
| 1 h (the first-hour split) | L1 ≤ 0.01, L∞ ≤ 0.25 | L1 ≤ 0.10, L∞ ≤ 0.25 |
| Small tag, `S < 0.01`, at any hour judged | `abs_L1 ≤ 2e-4 · total_ref` | same |

Definitions that 6.1 leaves open (**proposed**):

  - `S` is computed from the reference at the same hour.
  - For a small tag, the absolute test replaces both L1 and L∞. The
    relative numbers are still reported.
  - A tag whose reference is zero at that hour counts as small.
  - A tag that is a source and a region at once, such as `evap_tropo`,
    counts as a source tag.
  - Any non-finite value, or a missing hour, is a failure (B2).
  - Other hours (6 and 12 h) are reported and not judged.

**R6. Pairing.** See S2. For a per-tag budget, the reference is the copies
run and the run is the default. Both share one atmosphere, so
`--expect-parity` is on.

**R7. Closure** (criterion 4). All of these are **proposed**:

  - `G(t) = Σ |q_tag_res| w / total_ref`, the gross residual. The budget is
    `G(24 h) ≤ 0.002`.
  - "The second 12 h add no more than the first" means
    `G(24) − G(12) ≤ G(12) − G(0)`.
  - The ledgers are cumulative, so an interval budget is the difference of
    two outputs within one segment.
  - The remainder after the named parts is `≤ 1e-6 · total_ref` at 24 h. The
    verifier takes the named parts as a list of fields, since their output
    names are fixed later.

**R8. Copies** (from WP3). All of these are **proposed**:

  - Weight updraft quantities by the updraft mass, `ρaʲ Δz`, from `rhoaup`
    and `arup`.
  - The copies' own residual `r = q_totʲ − Σᵢ χᵢʲ` must stay within
    `Σ |r| ρaʲ Δz ≤ 2e-4 · total_ref`, a tenth of the closure budget.
  - The repair over the day must stay within
    `Σᵢ Σ |q_tag_upfix_i(24 h)| w ≤ 0.002 · total_ref(24 h)`.
    `upfix` is cumulative, so a sign change within the day is hidden. WP6's
    gross accumulators give the real throughput; use them once they exist.
  - The copies start from the plume, through the driver. The verifier
    records the driver's hash from the manifest.

**R9. Rain, snow and precipitation** (from WP4b). All of these are
**proposed**:

  - Closure: `Σ |Σᵢ q_rtag_i − q_rai| w / Σ q_rai w ≤ 1e-8` per hour, the
    same for snow, in Float64. Where `q_rai` is zero in the whole column,
    use an absolute floor of `1e-8 · total_ref`.
  - `|Σᵢ pr_tag_i − pr| ≤ 1e-8 · |pr|` at each output time, with the same
    floor where `pr = 0`.
  - The audit's "within 10% of each tag's precipitation over the day" needs
    the precipitation accumulated over the day. Hourly instantaneous
    samples of a flux cannot give it. So the configs must write averages
    (`_1h_average`) or an accumulated field, and the verifier must read
    them (M5).
  - A tag with less than 1% of the precipitation passes within 0.1% of the
    total.

**R10. The first hour.** Hour 1 is the output at exactly 3600 s. The
region and source split (R5) needs R2's classification. The copies start
from the plume in both modes, so hour 1 measures the dynamics.

**R11. Restarts.** See S6. Criterion 11 asks that "the restart carries the
tags bit for bit". So add `--bitwise-tags`, which compares the tag fields
bit for bit, like the parent fields.

**R12. The convergence ladder** (criterion 6). All of these are
**proposed**:

  - The share metric is
    `L1_φ = Σ |φ_run − φ_ref| q_tot,ref w / Σ φ_ref q_tot,ref w`, with
    `φ = q_tag / q_tot` of each run on its own atmosphere.
  - Report the parent's own change beside it: L1 of `hus`, `ta` and `rhoa`.
  - The 60- and 120-level rungs differ in `z`, and the verifier refuses
    that today. Either average the finer run onto the coarser faces,
    conservatively with its own `ρ Δz`, or compare column integrals only.
    State which in the output.

**R13. Output and provenance.** Refuse non-finite and fill values (B2).
Compare units and epochs (S4). Record both runs' `provenance.txt`, their
manifests, and the numpy, netCDF4 and Python versions. Write strict JSON.

**R14. Tests.** Each requirement gets a test that fails when the
requirement is broken:

  - analytic metric values on a nonuniform grid (B1);
  - the small-tag boundary: `S` just below and just above 0.01, and
    `abs_L1` just below and just above the bound;
  - the region and source split at 1 h;
  - a surface field;
  - a NaN, and a fill value;
  - a tag in one run only, and a parent field in one run only;
  - reference and run swapped (copies and default);
  - two restart segments;
  - `Σ region + res ≠ hus`.

Then run the mutation script again. It is easy to rebuild from the table
above.

## Not checked

  - Untracked files were checked after all. I took a manifest of this
    worktree, then wrote this report. `--verify` then reported
    `CHANGED: status_lines` and `CHANGED: untracked` (count 0 to 1), and
    `DIRTY`. A change to an ignored file is not detected (S8). I checked
    that from the code, not with a run.
  - No 2D column output exists on scratch. The dimensions of `pr` in a
    column run, `('time',)`, are my assumption. The synthetic test shows
    that any field without `z` stops the verifier.
  - The sphere is out of scope for the verifier today. It will need area
    weights, the deep-atmosphere factor `(1 + z/R)²`, and the
    `z_reference` dimension of the G2 outputs.
