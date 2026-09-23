# G3 phase 1: the evidence pipeline

Four standalone tools (`compare_runs.py`, `test_compare_runs.py`,
`manifest.py`, `inventory.py`), built for G3_TODO.md phase 1, items 1.1-1.5.
Background: `../../reference/untapped-potential-assessment-extended.md`, "New insight
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
                         [--json PATH]
```

`DIR` must be an explicit `output_XXXX` directory (an absolute or relative
path to one). `output_active` and a bare run root (e.g. `v3_upd_default`
itself) are both refused: either can point at a different run, and a
different code version, tomorrow. See `e73_reproduction.txt` for a real
demonstration of that hazard against the old script's glob.

Checks, each failure exiting nonzero and naming the variable and the
problem:

  - (a) every requested variable's file exists in both runs (default tags:
    every `e_src_<name>` in the reference, excluding `e_src_fix_*`,
    `e_src_inc_*` and `e_src_res`; `rhoa` is always required too, since the
    weights need it even when `--parent` leaves it out of the parity
    report);
  - (b) `time` and `date` are exactly equal. If the two runs have different
    lengths, this fails unless `--hours` was given on the command line
    *and* every requested hour is present in both runs at exactly `h*3600`
    seconds — only then is the common-length prefix compared, with an
    explicit `NOTICE:` line;
  - (c) `z` is exactly equal (its dimension is found by name, never by
    position, so a file with dimensions written `(time, z)` is still read
    correctly);
  - (d) only the column geometry (dimensions `z` and `time`) is supported;
    anything else is refused as "unsupported geometry".

Two reports follow. Neither is a hard failure by itself — they are findings,
not input-validity checks.

**Parent-state parity.** The default set is `ta`, `rhoa`, and every other
variable present in both runs whose name does not start with `e_src_`,
`e_prc_`, `q_prc_`, `e_tag_`, `q_tag_` or `q_gas_` (`--parent` overrides).
Each variable is compared **bit pattern by bit pattern**: same dtype and
shape required, then `a.view(uintN) == b.view(uintN)` element-wise (`uintN`
matches the dtype's own width, e.g. `uint64` for `float64`). This is what
"bitwise identical" means throughout this pipeline: not `==`, which treats
`+0.0` and `-0.0` as equal and so cannot see the difference. For each
variable the report gives:

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

**Per-tag, per-hour metrics.** Weights are `w_k = ρ_ref,k · Δz_k`: the
reference's own `rhoa` at that hour, for both runs (stated explicitly in the
printed output). `Δz` is rebuilt from the `z` cell centres as faces,
`z_f[0] = 0`, `z_f[k+1] = 2 z_c[k] - z_f[k]`; a non-positive resulting
thickness, or a top face that disagrees with the run's own YAML `z_max` by
more than a relative `1e-9` (skipped with a notice if the YAML has no
`z_max`), is a hard failure. For each tag and hour:

  - `integral_ref` = Σ `e_ref` `w` (J/m²) — the reference's own column
    integral, not a difference;
  - `rel_integral_change` = `(integral_run - integral_ref) / integral_ref`;
  - `L1_mass_weighted` = Σ`|Δe| w` / Σ`|e_ref| w` — a mass-weighted mean
    relative error, not a plain column mean;
  - `Linf_peak_normalized` = `max|Δe| / max|e_ref|` — the largest pointwise
    error over the reference's largest value, not a maximum pointwise
    relative error;
  - `max_abs_error` = `max|Δe|` in J/kg (pointwise, not mass-weighted).

Where the reference is identically zero at that hour (e.g. `mp` in the D4
configs, which is always zero), the four ratio metrics have no defined
value: the table prints `ref zero (run zero|nonzero)` instead of a stray `0`
or `NaN`. `integral_ref` and `max_abs_error` are still printed as real
numbers in that case — they do not depend on dividing by the reference.

`--json PATH` writes every number above, the resolved input paths, the
sha256 of every input file this run actually read, and the sha256 of
`compare_runs.py` itself, so a reported table can be checked against exactly
what produced it.

## test_compare_runs.py

```sh
python3 test_compare_runs.py            # or: python3 -m unittest test_compare_runs -v
```

Five mutation tests plus one baseline, per G3_TODO.md 1.3, built as
synthetic run directories under
`$SCRATCH/claude_work/g3_evidence/test_runs/` (never under the real output
root, which is read-only here). Each synthetic run copies `ta`, `rhoa`,
`e_src_sfc`, `e_src_rad`, `e_src_mp` and the YAML from
`v3_upd_copies/output_0000`; only the copies are mutated, with netCDF4 in
`r+` mode. Runs `compare_runs.py` as a real subprocess for each case (its
actual CLI contract, exit code included):

  1. an identical copy is bitwise identical, and every tag metric is 0 (or
     the explicit `ref zero` case);
  2. a deleted variable file — fails, naming the variable;
  3. one shifted timestamp (`time[5] += 1`) — fails;
  4. a truncated run (first 13 of 25 times) — fails without `--hours`,
     passes with `--hours 1,6` and the prefix notice;
  5. a moved coordinate (`z[3] += 1e-6`) — fails;
  6. a flipped signed zero (`+0.0` in the reference, `-0.0` in the run) —
     **not** fatal; reported as "not bitwise, signed-zero-only", with a note
     that plain `np.array_equal` would call it equal.

## manifest.py

```sh
python3 manifest.py --repo WORKTREE --config YML [--driver FILE] \
                     [--extra FILE ...] [--command "..."] --out PATH.json
python3 manifest.py --verify PATH.json
```

Run on the login node (compute nodes have no git, which is why a run's
`provenance.txt` reads `commit_dirty: unknown` today). Records the
worktree's actual `HEAD` sha and branch (or `detached`), every
`git status --porcelain=v1` line, the sha256 of `git diff HEAD`, the count
and one combined sha256 of every untracked file (individually, via
`--untracked-files=all`, not directory-collapsed), the sha256 of
`.buildkite/Manifest-v1.11.toml`, `.buildkite/Project.toml` and
`.buildkite/LocalPreferences.toml` (each `null` if absent), the sha256 of
the config/driver/extra files given, `julia +1.11 --version`, the hostname,
the UTC time and the command string. Every git call goes through
`git --no-optional-locks`, so running this tool never itself modifies the
worktree it is inspecting.

`--verify PATH.json` re-reads a written manifest, recomputes every git fact
and hash fresh against the same repo and files, and prints `unchanged` or
`CHANGED: was ... now ...` per field; exits nonzero if anything changed.

Tried read-only against `../../../../ClimaAtmosResiDyn-upd-run` (config
`experiments/tag_closure/configs/v3_upd_default.yml` inside that worktree):
correctly reports `.buildkite/Manifest-v1.11.toml` as ` M` in `status_lines`
(the worktree is genuinely dirty there, as G3_TODO.md 1.1 says), and
`--verify` on the resulting manifest reports every field unchanged
immediately afterwards.

## inventory.py

```sh
python3 inventory.py [--root ROOT] --out runs_inventory.csv
```

Walks `ROOT/*/output_*/` (default: the tag-closure output root on scratch)
and writes one CSV row per `output_XXXX` directory — never per
`output_active`, which is only read to set the `is_active` flag of the
directory it currently points to. Columns: `run`, `output_index`,
`is_active`, then `provenance.txt`'s own `commit`, `commit_dirty`,
`started`, `finished`, `exit_status`, `slurm_job_id`, `partition`, `ntasks`
(each blank if that file or that field is absent), `float_type` (from the
run's own YAML, if present), `graceful_exit` (whether `graceful_exit.dat`
exists), `n_times` and `last_time` (from `ta_1h_inst.nc`, blank if that file
is absent or unreadable), and `status`, always `unclassified` — this tool
gathers facts only; classifying a run is separate, later work. Read-only:
never writes under the output root.

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
