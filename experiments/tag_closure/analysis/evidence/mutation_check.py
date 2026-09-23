"""G3 WP0 / review finding B1: how many injected defects does the test suite
catch? Copies analysis/evidence/ (compare_runs.py, test_compare_runs.py,
fixtures/) into a scratch tmp dir once per mutation, applies one textual
mutation to the copy's compare_runs.py, and runs the copy's
test_compare_runs.py against it. "Caught" means at least one test failed (or
errored); "not caught" means the whole suite passed, exactly as if
compare_runs.py had not been mutated at all.

    python3 mutation_check.py

Prints one line per mutation and the kill rate; see README.md for the
recorded result. This is not a hidden or graded test file -- it is the tool
the phase-1 review used (by hand, in its own scratchpad) to find that the
old six tests caught 2 of 19 defects; this script automates the same check
against the current, larger test suite.
"""
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
TMP_BASE = Path("/dss/dsstbyfs02/scratch/0D/di38kez/claude_work/g3_evidence/mutation_check")

# (name, old text, new text). Each must appear in compare_runs.py exactly
# once at the point intended -- str.count(old) is asserted to catch a
# mutation description that no longer matches the current source.
MUTATIONS = [
    (
        "weights from the run's rhoa, not the reference's",
        "        for h in hours:\n            i = idx_map[h]\n            w = ref_rhoa[:, i] * dz\n            w_run = None if rhoa_parity_ok else run_rhoa[:, i] * run_dz",
        "        for h in hours:\n            i = idx_map[h]\n            w = run_rhoa[:, i] * dz\n            w_run = None if rhoa_parity_ok else run_rhoa[:, i] * run_dz",
    ),
    (
        "dz = 1 (no thickness weighting)",
        "    dz = np.diff(faces)",
        "    dz = np.diff(faces)\n    dz = np.ones_like(dz)",
    ),
    (
        "L1 without mass weighting",
        'row["L1_mass_weighted"] = float(abs_l1 / abs_ref_weighted)',
        'row["L1_mass_weighted"] = float(np.sum(np.abs(delta)) / np.sum(np.abs(e_ref)))',
    ),
    (
        "L-infinity as the largest pointwise relative error, not peak-normalized",
        'row["Linf_peak_normalized"] = float(np.max(np.abs(delta)) / max_abs_ref)',
        'row["Linf_peak_normalized"] = float(np.max(np.abs(delta) / np.where(e_ref == 0, 1.0, np.abs(e_ref))))',
    ),
    (
        "run's time index off by one",
        "        idx[h] = int(hits[0])",
        "        idx[h] = int(hits[0]) + 1",
    ),
    (
        "within-run coordinate check (RunCoords) disabled",
        '        if not np.array_equal(self.time, time):\n            die(f"{self.label}: \'{source}\' has a different time array than the run\'s other files")\n        if not np.array_equal(self.date, date):\n            die(f"{self.label}: \'{source}\' has a different date array than the run\'s other files")',
        "        pass",
    ),
    (
        "parity through == instead of bit patterns",
        "    diff_mask = bits_a != bits_b",
        "    diff_mask = (a != b) & ~(np.isnan(a) & np.isnan(b))",
    ),
    (
        "date check removed (equal-length branch)",
        '        if not np.array_equal(ref_coords.date, run_coords.date):\n            die("date: reference and run have the same length but disagree somewhere in the array")',
        "        pass",
    ),
    # "output_active accepted" (disabling the special-case die) is not
    # listed: resolve_output_dir's OUTPUT_DIR_RE check refuses the name
    # 'output_active' independently (it does not match output_XXXX), so
    # removing the special case changes only the error message, not the
    # outcome -- confirmed by running the mutant by hand. Real defence in
    # depth, not a test gap.
    (
        "(time, z) files not transposed to canonical (z, time)",
        '            if dims != ("z", "time"):\n                data = np.moveaxis(data, dims.index("z"), 0)  # canonical (z, time)',
        "            pass",
    ),
    (
        "top-face check against z_max disabled",
        "    check_top_face(float(faces[-1]), z_max)",
        "    pass  # check_top_face(float(faces[-1]), z_max)",
    ),
    (
        "dtype check disabled",
        "    if a.dtype != b.dtype:\n        die(f\"{name}: dtype mismatch, reference {a.dtype} vs run {b.dtype}\")",
        "    pass",
    ),
    (
        "sign of rel_integral_change flipped",
        'row["rel_integral_change"] = (integral_run_ref_weighted - integral_ref) / integral_ref',
        'row["rel_integral_change"] = (integral_ref - integral_run_ref_weighted) / integral_ref',
    ),
    (
        "dz from np.gradient(z) instead of the face reconstruction",
        "    dz = np.diff(faces)",
        "    dz = np.gradient(z_centers)",
    ),
    (
        "tag metrics from the lowest level only",
        "def tag_row_metrics(tag, hour, e_ref, e_run, w, w_run=None):",
        "def tag_row_metrics(tag, hour, e_ref, e_run, w, w_run=None):\n    e_ref, e_run, w = e_ref[:1], e_run[:1], w[:1]",
    ),
    (
        "S1: parent-parity union check (one-run-only field) disabled",
        '    unexplained = sorted((set(only_ref) | set(only_run)) - set(allow_missing))\n    if unexplained:\n        die(',
        "    unexplained = []\n    if unexplained:\n        die(",
    ),
    (
        "B2: non-finite/fill-value check disabled",
        "    bad = ~np.isfinite(data)",
        "    bad = np.zeros(data.shape, dtype=bool)",
    ),
]


def apply_mutation(text, old, new):
    n = text.count(old)
    if n != 1:
        raise AssertionError(f"expected exactly one occurrence, found {n}: {old[:80]!r}...")
    return text.replace(old, new, 1)


def main():
    TMP_BASE.mkdir(parents=True, exist_ok=True)
    src_text = (HERE / "compare_runs.py").read_text()

    results = []
    for name, old, new in MUTATIONS:
        try:
            mutant_text = apply_mutation(src_text, old, new)
        except AssertionError as exc:
            results.append((name, "SKIPPED (pattern not found)", str(exc)))
            continue

        work = Path(tempfile.mkdtemp(prefix="mut_", dir=TMP_BASE))
        try:
            shutil.copytree(HERE, work, dirs_exist_ok=True, ignore=shutil.ignore_patterns("__pycache__"))
            (work / "compare_runs.py").write_text(mutant_text)
            proc = subprocess.run(
                [sys.executable, "test_compare_runs.py"], cwd=work, capture_output=True, text=True, timeout=300
            )
            caught = proc.returncode != 0
            results.append((name, "CAUGHT" if caught else "NOT CAUGHT", ""))
        finally:
            shutil.rmtree(work, ignore_errors=True)

    n_caught = sum(1 for _, verdict, _ in results if verdict == "CAUGHT")
    n_total = sum(1 for _, verdict, _ in results if verdict in ("CAUGHT", "NOT CAUGHT"))
    print(f"{'Mutation':70s} {'Verdict'}")
    print("-" * 90)
    for name, verdict, note in results:
        print(f"{name:70s} {verdict}{(' - ' + note) if note else ''}")
    print("-" * 90)
    print(f"kill rate: {n_caught}/{n_total}")


if __name__ == "__main__":
    main()
