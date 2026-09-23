"""G3 1.4: a classified, machine-readable inventory of every run.

    python3 inventory.py [--root ROOT] [--repo REPO] [--register CSV] --out runs_inventory.csv

Walks ROOT/*/output_*/ (default ROOT is the tag-closure output root on
scratch) and writes one row per `output_XXXX` directory found there, plus one
row for every run in the register (`review/register/runs.csv`) that has no
matching directory on scratch today -- its data may be gone, or it may live
on another machine (S11). `output_active` itself is a symlink alias, not a
separate directory, so it never gets its own row; it is only read to decide
the `is_active` flag of the row it points to.

The key is `(machine, run, output_index)`, not `run` alone: two machines have
both used the same run name for different commits and jobs (S11's
`c0_sphere_audit` example). `machine` comes from the row's own
`provenance.txt`, never guessed from the scratch root's own machine, so a
`levante`-run copy found here is still labelled correctly.

Beyond the raw facts `inventory.py` always gathered, this classifies each row
along the axes the phase-1 review proposed ("Classifying the inventory"):
outcome (from `exit_status`), code status (whether the commit is reachable
from a remote ref, checked against the git repo this tool itself runs from),
lineage (superseded / restart-of, from the run's own directory and config),
configuration (geometry and family, from the run's own YAML), and the
register's purpose and finding IDs, joined on `run` with a flag if the
register's own commit disagrees (another face of S11). `status` -- PR head,
historical, superseded, failed, proposed -- is left for a person to set; this
tool only seeds it where the other columns already make it unambiguous
(`failed`, `superseded`), and leaves everything else `unclassified`.

Never writes anywhere under the scratch output root, and never writes to the
git repo it queries; only reads both, plus the register CSV.
"""
import argparse
import csv
import re
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

from netCDF4 import Dataset

DEFAULT_ROOT = "/dss/dsstbyfs02/scratch/0D/di38kez/tag_closure/output"
OUTPUT_DIR_RE = re.compile(r"^output_(\d{4})$")
RENAMED_HINT_RE = re.compile(r"(_superseded$|_oom_\d+$)")

# Repo root and register CSV, found relative to this file: repo_root/
# experiments/tag_closure/{analysis/evidence/inventory.py, review/register/runs.csv}.
_THIS_FILE = Path(__file__).resolve()
DEFAULT_REPO = _THIS_FILE.parents[4]
DEFAULT_REGISTER = _THIS_FILE.parents[2] / "review" / "register" / "runs.csv"

FIELDS = [
    "machine",
    "run",
    "output_index",
    "is_active",
    "on_scratch",
    "commit",
    "commit_dirty",
    "commit_status",
    "started",
    "finished",
    "exit_status",
    "outcome",
    "slurm_job_id",
    "partition",
    "ntasks",
    "float_type",
    "stop_file_present",
    "graceful_exit_value",
    "n_times",
    "last_time",
    "geometry",
    "family",
    "updraft_copy_mode",
    "config_sha256",
    "superseded_by",
    "renamed_hint",
    "restart_of",
    "register_purpose",
    "register_finding_ids",
    "register_status",
    "register_commit_mismatch",
    "manifest_path",
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


def read_own_yaml(run_dir):
    """Text of the run's own YAML copy (there is at most one *.yml per
    output_XXXX; the driver writes the merged config there), or None."""
    ymls = sorted(run_dir.glob("*.yml"))
    return ymls[0].read_text() if ymls else None


def classify_configuration(yaml_text):
    """Geometry, family and the updraft-copy mode, read from the run's own
    merged YAML. Geometry has no single YAML key across all configs in this
    series, so it is read from the grid keys that do exist: `h_elem` only
    appears on a cubed sphere."""
    if yaml_text is None:
        return "", "", ""
    geometry = "sphere" if re.search(r"^h_elem:", yaml_text, re.MULTILINE) else "column"
    if re.search(r"^water_tracers:", yaml_text, re.MULTILINE):
        family = "water"
    elif re.search(r"^energy_source_tags:", yaml_text, re.MULTILINE):
        family = "energy"
    else:
        family = "none"
    updraft_copy = "true" if re.search(r"^water_tag_updraft_copy:\s*true", yaml_text, re.MULTILINE) else ""
    return geometry, family, updraft_copy


def find_restart_of(yaml_text):
    """The raw restart_file value, if the run's own YAML has one. Not
    resolved further here -- manifest.py resolves and hashes it at
    submission time; this only records that a lineage edge exists."""
    if yaml_text is None:
        return ""
    m = re.search(r'^restart_file:\s*"?([^"\n]+)"?\s*$', yaml_text, re.MULTILINE)
    return m.group(1).strip() if m else ""


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


def read_graceful_exit(run_dir):
    """S10: `graceful_exit.dat` is created at the FIRST step of every run
    (src/callbacks/callbacks.jl), holding '0', and only overwritten with '1'
    at a real graceful stop. So its mere presence is not a graceful exit --
    an OOM-killed run has it too. Report presence and content separately."""
    path = run_dir / "graceful_exit.dat"
    if not path.exists():
        return False, ""
    try:
        return True, path.read_text().strip()
    except OSError:
        return True, ""


def classify_outcome(prov):
    """complete/failed/unknown from exit_status; no_provenance if the run
    never wrote one (never started, or crashed before the runscript's own
    trailer ran). This does not attempt 'truncated' (comparing n_times
    against t_end/period): that needs the output period parsed out of the
    YAML's diagnostics list, which varies enough between configs in this
    series that a wrong guess would be worse than not guessing (left open,
    S10)."""
    if not prov:
        return "no_provenance"
    exit_status = prov.get("exit_status", "")
    if exit_status == "":
        return "unknown"
    if exit_status == "0":
        return "complete"
    return "failed"


def active_target_name(run_dir_parent):
    """The output_XXXX name output_active currently resolves to, or None."""
    link = run_dir_parent / "output_active"
    if not link.is_symlink():
        return None
    try:
        return link.resolve().name
    except OSError:
        return None


def sha256_file(path):
    import hashlib
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


class GitCommitStatus:
    """Whether a commit is on main, on a remote ref, or reachable at all, in
    the git repo this tool runs from. One `git` process per distinct commit,
    cached, since a run register commonly repeats a commit across many rows.
    Best-effort: if `repo` is not a git worktree, or a commit predates this
    clone's history, every lookup reports 'unknown' rather than dying -- the
    inventory's job is to describe the runs on scratch, and a run's data does
    not stop existing because this tool's own repo cannot see its commit."""

    def __init__(self, repo):
        self.repo = repo
        self.usable = repo is not None and (Path(repo) / ".git").exists()
        self.cache = {}

    def _git(self, args):
        proc = subprocess.run(["git", "--no-optional-locks", *args], cwd=self.repo, capture_output=True, text=True)
        return proc

    def status(self, commit):
        if not self.usable or not commit or commit in ("unknown", ""):
            return "unknown"
        if commit in self.cache:
            return self.cache[commit]
        exists = self._git(["cat-file", "-e", f"{commit}^{{commit}}"]).returncode == 0
        if not exists:
            result = "unreachable (not in this repo)"
        else:
            on_main = False
            for ref in ("origin/main", "main"):
                proc = self._git(["merge-base", "--is-ancestor", commit, ref])
                if proc.returncode == 0:
                    on_main = True
                    break
            if on_main:
                result = "on_main"
            else:
                remotes = self._git(["for-each-ref", "--contains", commit, "refs/remotes"]).stdout
                names = [line.split(None, 2)[2] for line in remotes.splitlines() if len(line.split(None, 2)) >= 3]
                result = f"on_remote: {', '.join(names)}" if names else "no_ref (local only)"
        self.cache[commit] = result
        return result


def find_manifest(run_dir, run, scratch_root):
    """A manifest for this output directory, checked in the two places
    submit_g3.sh and tag_closure_common.sh leave one: copied into the
    output directory itself (manifest.json), or, for a run submitted before
    that wiring existed, under provenance.txt's own manifest_path."""
    local = run_dir / "manifest.json"
    if local.is_file():
        return str(local)
    prov = parse_provenance(run_dir / "provenance.txt")
    path = prov.get("manifest_path", "")
    if path and Path(path).is_file():
        return path
    return ""


def gather_scratch_rows(root, git_status):
    rows = []
    seen_runs = set()
    for run_dir_parent in sorted(p for p in Path(root).iterdir() if p.is_dir()):
        run = run_dir_parent.name
        seen_runs.add(run)
        active = active_target_name(run_dir_parent)
        output_dirs = sorted(
            d for d in run_dir_parent.iterdir()
            if not d.is_symlink() and d.is_dir() and OUTPUT_DIR_RE.match(d.name)
        )
        # The newest index present, for 'superseded_by' below. output_active
        # may point at an index that was since removed, so fall back to the
        # highest index actually on disk.
        newest = active if active in {d.name for d in output_dirs} else (output_dirs[-1].name if output_dirs else None)

        for output_dir in output_dirs:
            m = OUTPUT_DIR_RE.match(output_dir.name)
            prov = parse_provenance(output_dir / "provenance.txt")
            n_times, last_time = read_ta_times(output_dir)
            stop_present, stop_value = read_graceful_exit(output_dir)
            yaml_text = read_own_yaml(output_dir)
            geometry, family, updraft_copy = classify_configuration(yaml_text)
            ymls = sorted(output_dir.glob("*.yml"))
            config_sha256 = sha256_file(ymls[0]) if ymls else ""
            commit = prov.get("commit", "")

            superseded_by = ""
            if newest and output_dir.name != newest:
                superseded_by = newest

            outcome = classify_outcome(prov)
            provisional_status = "superseded" if superseded_by else ("failed" if outcome == "failed" else "unclassified")

            rows.append(
                {
                    "machine": prov.get("machine", ""),
                    "run": run,
                    "output_index": m.group(1),
                    "is_active": output_dir.name == active,
                    "on_scratch": True,
                    "commit": commit,
                    "commit_dirty": prov.get("commit_dirty", ""),
                    "commit_status": git_status.status(commit),
                    "started": prov.get("started", ""),
                    "finished": prov.get("finished", ""),
                    "exit_status": prov.get("exit_status", ""),
                    "outcome": outcome,
                    "slurm_job_id": prov.get("slurm_job_id", ""),
                    "partition": prov.get("partition", ""),
                    "ntasks": prov.get("ntasks", ""),
                    "float_type": find_float_type(output_dir),
                    "stop_file_present": stop_present,
                    "graceful_exit_value": stop_value,
                    "n_times": n_times,
                    "last_time": last_time,
                    "geometry": geometry,
                    "family": family,
                    "updraft_copy_mode": updraft_copy,
                    "config_sha256": config_sha256,
                    "superseded_by": superseded_by,
                    "renamed_hint": "yes" if RENAMED_HINT_RE.search(run) else "",
                    "restart_of": find_restart_of(yaml_text),
                    "register_purpose": "",
                    "register_finding_ids": "",
                    "register_status": "",
                    "register_commit_mismatch": "",
                    "manifest_path": find_manifest(output_dir, run, root),
                    "status": provisional_status,
                }
            )
    return rows, seen_runs


def read_register(path):
    """review/register/runs.csv, keyed by run_dir. Returns {} if the file is
    missing -- the join is then skipped, not a fatal error, since the
    register is a separate hand-maintained artifact this tool only reads."""
    if not path.is_file():
        print(f"WARNING: register not found, skipping the join: {path}", file=sys.stderr)
        return {}
    with open(path, newline="") as f:
        return {row["run_dir"]: row for row in csv.DictReader(f)}


def join_register(rows, register, seen_runs):
    """Add the register's purpose/finding_ids/status to every scratch row of
    a run it also lists, and flag a commit disagreement rather than trusting
    the join blindly (S11: the same run name has meant two different jobs on
    two machines). Then add one row per register run that has no directory
    on scratch at all today, so the CSV still covers every run RUNS.md
    lists, not just what happens to still be on this scratch root."""
    for row in rows:
        reg = register.get(row["run"])
        if reg is None:
            continue
        row["register_purpose"] = reg.get("purpose", "")
        row["register_finding_ids"] = reg.get("finding_ids", "")
        row["register_status"] = reg.get("status", "")
        reg_commit = reg.get("commit", "")
        if reg_commit and row["commit"] and reg_commit != row["commit"]:
            row["register_commit_mismatch"] = f"register has {reg_commit}"

    extra_rows = []
    for run, reg in sorted(register.items()):
        if run in seen_runs:
            continue
        extra_rows.append(
            {
                "machine": "",
                "run": run,
                "output_index": "",
                "is_active": "",
                "on_scratch": False,
                "commit": reg.get("commit", ""),
                "commit_dirty": reg.get("dirty", ""),
                "commit_status": "",
                "started": reg.get("date", ""),
                "finished": "",
                "exit_status": "",
                "outcome": "no_provenance",
                "slurm_job_id": reg.get("slurm_job", ""),
                "partition": "",
                "ntasks": "",
                "float_type": "",
                "stop_file_present": "",
                "graceful_exit_value": "",
                "n_times": "",
                "last_time": "",
                "geometry": "",
                "family": "",
                "updraft_copy_mode": "",
                "config_sha256": "",
                "superseded_by": "",
                "renamed_hint": "yes" if RENAMED_HINT_RE.search(run) else "",
                "restart_of": "",
                "register_purpose": reg.get("purpose", ""),
                "register_finding_ids": reg.get("finding_ids", ""),
                "register_status": reg.get("status", ""),
                "register_commit_mismatch": "",
                "manifest_path": "",
                "status": "unclassified",
            }
        )
    return rows + extra_rows


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--root", default=DEFAULT_ROOT, help="the tag-closure output root to walk")
    parser.add_argument("--repo", default=str(DEFAULT_REPO), help="the git repo to check each commit's status against")
    parser.add_argument("--register", default=str(DEFAULT_REGISTER), help="review/register/runs.csv, joined on run")
    parser.add_argument("--out", required=True, help="write the CSV here")
    args = parser.parse_args()

    root = Path(args.root)
    if not root.is_dir():
        print(f"ERROR: --root is not a directory: {root}", file=sys.stderr)
        sys.exit(1)

    git_status = GitCommitStatus(args.repo)
    if not git_status.usable:
        print(f"WARNING: --repo is not a git worktree, commit_status will read 'unknown': {args.repo}", file=sys.stderr)

    rows, seen_runs = gather_scratch_rows(root, git_status)
    if not rows:
        print(f"ERROR: no output_XXXX directories found under {root}", file=sys.stderr)
        sys.exit(1)

    register = read_register(Path(args.register))
    rows = join_register(rows, register, seen_runs)
    rows.sort(key=lambda r: (r["run"], r["output_index"]))

    tool_sha256 = sha256_file(Path(__file__).resolve())
    with open(args.out, "w", newline="") as f:
        f.write(
            f"# generated {datetime.now(timezone.utc).isoformat()} "
            f"root={root} register={args.register} tool_sha256={tool_sha256}\n"
        )
        writer = csv.DictWriter(f, fieldnames=FIELDS)
        writer.writeheader()
        writer.writerows(rows)
    on_scratch = sum(1 for r in rows if r["on_scratch"])
    print(f"wrote {len(rows)} rows to {Path(args.out).resolve()} ({on_scratch} on scratch, {len(rows) - on_scratch} register-only)")


if __name__ == "__main__":
    main()
