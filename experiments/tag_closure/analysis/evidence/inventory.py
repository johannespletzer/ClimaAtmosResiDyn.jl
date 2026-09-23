"""G3 1.4: a machine-readable inventory of every run on scratch.

    python3 inventory.py [--root ROOT] --out runs_inventory.csv

Walks ROOT/*/output_*/ (default ROOT is the tag-closure output root on
scratch) and writes one CSV row per output_XXXX directory: which run it
belongs to, whether `output_active` currently points to it, what its own
`provenance.txt` says (empty fields if that file is absent), the float type
from its own YAML copy, whether it exited gracefully, and how many hourly
times `ta_1h_inst.nc` actually holds. `output_active` itself is a symlink
alias, not a separate directory, so it never gets its own row; it is only
read to decide the `is_active` flag of the row it points to.

This tool only gathers facts. The `status` column is always "unclassified";
classifying a run (PR head, historical, superseded, failed, proposed) is a
later, human judgement (G3_TODO.md 1.4).

Never writes anywhere under the scratch output root; only reads it.
"""
import argparse
import csv
import re
import sys
from pathlib import Path

from netCDF4 import Dataset

DEFAULT_ROOT = "/dss/dsstbyfs02/scratch/0D/di38kez/tag_closure/output"
OUTPUT_DIR_RE = re.compile(r"^output_(\d{4})$")

FIELDS = [
    "run",
    "output_index",
    "is_active",
    "commit",
    "commit_dirty",
    "started",
    "finished",
    "exit_status",
    "slurm_job_id",
    "partition",
    "ntasks",
    "float_type",
    "graceful_exit",
    "n_times",
    "last_time",
    "status",
]


def parse_provenance(path):
    """provenance.txt is 'key: value' lines, one per line. Empty dict if the
    file is absent, so every downstream field just reads as ''."""
    fields = {}
    if not path.is_file():
        return fields
    for line in path.read_text().splitlines():
        if ":" not in line:
            continue
        key, _, value = line.partition(":")  # first colon only; timestamps have more
        fields[key.strip()] = value.strip()
    return fields


def find_float_type(run_dir):
    """FLOAT_TYPE: "..." from the run's own YAML copy, if one is present."""
    for path in sorted(run_dir.glob("*.yml")):
        for line in path.read_text().splitlines():
            m = re.match(r'^FLOAT_TYPE:\s*"?([A-Za-z0-9_]+)"?\s*$', line)
            if m:
                return m.group(1)
    return ""


def read_ta_times(run_dir):
    """(n_times, last_time) from ta_1h_inst.nc; ('', '') if the file is
    absent or cannot be read (e.g. a run that died mid-write)."""
    path = run_dir / "ta_1h_inst.nc"
    if not path.is_file():
        return "", ""
    try:
        with Dataset(path) as ds:
            ds.set_auto_mask(False)
            if "time" not in ds.variables:
                return "", ""
            time = ds.variables["time"][:]
            if len(time) == 0:
                return 0, ""
            return int(len(time)), float(time[-1])
    except OSError as exc:
        print(f"WARNING: could not read {path}: {exc}", file=sys.stderr)
        return "", ""


def active_target_name(run_dir_parent):
    """The output_XXXX name output_active currently resolves to, or None."""
    link = run_dir_parent / "output_active"
    if not link.is_symlink():
        return None
    try:
        return link.resolve().name
    except OSError:
        return None


def gather_rows(root):
    rows = []
    for run_dir_parent in sorted(p for p in Path(root).iterdir() if p.is_dir()):
        run = run_dir_parent.name
        active = active_target_name(run_dir_parent)
        for output_dir in sorted(run_dir_parent.iterdir()):
            if output_dir.is_symlink() or not output_dir.is_dir():
                continue
            m = OUTPUT_DIR_RE.match(output_dir.name)
            if not m:
                continue
            prov = parse_provenance(output_dir / "provenance.txt")
            n_times, last_time = read_ta_times(output_dir)
            rows.append(
                {
                    "run": run,
                    "output_index": m.group(1),
                    "is_active": output_dir.name == active,
                    "commit": prov.get("commit", ""),
                    "commit_dirty": prov.get("commit_dirty", ""),
                    "started": prov.get("started", ""),
                    "finished": prov.get("finished", ""),
                    "exit_status": prov.get("exit_status", ""),
                    "slurm_job_id": prov.get("slurm_job_id", ""),
                    "partition": prov.get("partition", ""),
                    "ntasks": prov.get("ntasks", ""),
                    "float_type": find_float_type(output_dir),
                    "graceful_exit": (output_dir / "graceful_exit.dat").exists(),
                    "n_times": n_times,
                    "last_time": last_time,
                    "status": "unclassified",
                }
            )
    return rows


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--root", default=DEFAULT_ROOT, help="the tag-closure output root to walk")
    parser.add_argument("--out", required=True, help="write the CSV here")
    args = parser.parse_args()

    root = Path(args.root)
    if not root.is_dir():
        print(f"ERROR: --root is not a directory: {root}", file=sys.stderr)
        sys.exit(1)

    rows = gather_rows(root)
    if not rows:
        print(f"ERROR: no output_XXXX directories found under {root}", file=sys.stderr)
        sys.exit(1)

    with open(args.out, "w", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=FIELDS)
        writer.writeheader()
        writer.writerows(rows)
    print(f"wrote {len(rows)} rows to {Path(args.out).resolve()}")


if __name__ == "__main__":
    main()
