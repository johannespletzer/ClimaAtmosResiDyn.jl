"""G3 1.1: a manifest of the worktree, config and environment at job submission.

    python3 manifest.py --repo WORKTREE --config YML [--driver FILE]
                         [--extra FILE ...] [--command "..."] --out PATH.json
    python3 manifest.py --verify PATH.json

Compute nodes on terrabyte have no git, which is why a run's provenance.txt
reads `commit_dirty: unknown` (G3_TODO.md 1.1). This tool runs on the login
node, before a job is submitted, and records what the login node can see and
the compute node cannot: the worktree's actual HEAD, its dirty files, the
resolved `.buildkite` Manifest/Project/LocalPreferences, the config, driver
and any extra file, and the environment (`julia +1.11 --version`, hostname,
UTC time, and the submit command string).

Every git call goes through `git --no-optional-locks`, so running this tool
never itself touches the worktree it is inspecting (no index lock, no
stat-refresh write); it is safe to run alongside other work in the same
worktree.

`--verify PATH.json` re-reads a written manifest, recomputes every hash and
git fact from scratch against the same repo and files, and prints what
changed since. A clean, unchanged worktree reports every field "unchanged".
"""
import argparse
import hashlib
import json
import socket
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

BUILDKITE_FILES = ("Manifest-v1.11.toml", "Project.toml", "LocalPreferences.toml")


def die(message):
    print(f"ERROR: {message}", file=sys.stderr)
    sys.exit(1)


def sha256_file(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def git_bytes(repo, args, required=True):
    """Run one git call with no optional locks, so it cannot modify the
    worktree it is inspecting."""
    proc = subprocess.run(["git", "--no-optional-locks", *args], cwd=repo, capture_output=True)
    if required and proc.returncode != 0:
        die(f"git {' '.join(args)} failed in {repo}: {proc.stderr.decode(errors='replace').strip()}")
    return proc


def git_text(repo, args, required=True):
    return git_bytes(repo, args, required=required).stdout.decode("utf-8", errors="replace")


def resolve_named_file(raw, label):
    if raw is None:
        return None
    path = Path(raw)
    if not path.is_file():
        die(f"--{label} is not a file: {raw}")
    resolved = path.resolve()
    return {"path": str(resolved), "sha256": sha256_file(resolved)}


def get_branch(repo):
    """The current branch name, or 'detached' if HEAD is not on one."""
    proc = git_bytes(repo, ["symbolic-ref", "-q", "--short", "HEAD"], required=False)
    if proc.returncode != 0:
        return "detached"
    name = proc.stdout.decode("utf-8", errors="replace").strip()
    return name if name else "detached"


def get_untracked(repo):
    """Every untracked file (not directory) under the worktree, individually,
    its count, and one sha256 over the sorted (path, sha256) list."""
    raw = git_text(repo, ["status", "--porcelain=v1", "--untracked-files=all"])
    paths = sorted(line[3:] for line in raw.splitlines() if line.startswith("?? "))
    pairs = []
    for rel in paths:
        full = Path(repo) / rel
        if not full.is_file():
            die(f"untracked entry '{rel}' is not a plain file (git status --untracked-files=all should only list files)")
        pairs.append((rel, sha256_file(full)))
    combined = "\n".join(f"{path}\t{h}" for path, h in pairs).encode("utf-8")
    return {
        "count": len(pairs),
        "sha256": hashlib.sha256(combined).hexdigest() if pairs else None,
    }


def get_buildkite_files(repo):
    result = {}
    for name in BUILDKITE_FILES:
        path = Path(repo) / ".buildkite" / name
        result[name] = sha256_file(path) if path.is_file() else None
    return result


def get_julia_version():
    try:
        proc = subprocess.run(["julia", "+1.11", "--version"], capture_output=True, text=True, timeout=60)
    except FileNotFoundError:
        die("'julia' is not on PATH (needed for 'julia +1.11 --version')")
    except subprocess.TimeoutExpired:
        die("'julia +1.11 --version' did not return within 60s")
    if proc.returncode != 0:
        die(f"'julia +1.11 --version' failed: {proc.stderr.strip()}")
    return proc.stdout.strip()


def build_manifest(repo, config_raw, driver_raw, extra_raw, command):
    """Everything the manifest records, computed fresh. Used both to build a
    new manifest and, from --verify, to recompute one for comparison."""
    repo_path = Path(repo)
    if not (repo_path / ".git").exists():
        die(f"--repo does not look like a git worktree (no .git): {repo}")

    config = resolve_named_file(config_raw, "config")
    if config is None:
        die("a config file is required")
    driver = resolve_named_file(driver_raw, "driver")
    extra = [resolve_named_file(e, "extra") for e in (extra_raw or [])]

    return {
        "repo": str(repo_path.resolve()),
        "head_sha": git_text(repo, ["rev-parse", "HEAD"]).strip(),
        "branch": get_branch(repo),
        "status_lines": git_text(repo, ["status", "--porcelain=v1"]).splitlines(),
        "diff_sha256": hashlib.sha256(git_bytes(repo, ["diff", "HEAD"]).stdout).hexdigest(),
        "untracked": get_untracked(repo),
        "buildkite_files": get_buildkite_files(repo),
        "config": config,
        "driver": driver,
        "extra": extra,
        "julia_version": get_julia_version(),
        "hostname": socket.gethostname(),
        "utc_time": datetime.now(timezone.utc).isoformat(),
        "command": command,
        "manifest_tool_sha256": sha256_file(Path(__file__).resolve()),
    }


def compare_field(name, old, new, lines):
    if old == new:
        lines.append(f"  unchanged: {name}")
    else:
        lines.append(f"  CHANGED: {name}")
        lines.append(f"    was: {old}")
        lines.append(f"    now: {new}")


def verify(json_path):
    recorded = json.loads(Path(json_path).read_text())
    fresh = build_manifest(
        recorded["repo"],
        recorded["config"]["path"],
        recorded["driver"]["path"] if recorded["driver"] else None,
        [e["path"] for e in recorded["extra"]],
        recorded.get("command"),
    )
    print(f"verify: {json_path}")
    print(f"repo:   {recorded['repo']}")
    print(f"recorded at {recorded['utc_time']} on {recorded['hostname']}; verifying now on {fresh['hostname']}")
    lines = []
    compare_field("head_sha", recorded["head_sha"], fresh["head_sha"], lines)
    compare_field("branch", recorded["branch"], fresh["branch"], lines)
    compare_field("status_lines", recorded["status_lines"], fresh["status_lines"], lines)
    compare_field("diff_sha256", recorded["diff_sha256"], fresh["diff_sha256"], lines)
    compare_field("untracked", recorded["untracked"], fresh["untracked"], lines)
    compare_field("buildkite_files", recorded["buildkite_files"], fresh["buildkite_files"], lines)
    compare_field("config.sha256", recorded["config"]["sha256"], fresh["config"]["sha256"], lines)
    compare_field(
        "driver.sha256",
        recorded["driver"]["sha256"] if recorded["driver"] else None,
        fresh["driver"]["sha256"] if fresh["driver"] else None,
        lines,
    )
    compare_field(
        "extra.sha256",
        [e["sha256"] for e in recorded["extra"]],
        [e["sha256"] for e in fresh["extra"]],
        lines,
    )
    compare_field("julia_version", recorded["julia_version"], fresh["julia_version"], lines)
    compare_field("hostname (informational)", recorded["hostname"], fresh["hostname"], lines)
    print("\n".join(lines))
    any_changed = any(line.strip().startswith("CHANGED") for line in lines)
    print("\nresult: " + ("DIRTY: the recorded state no longer matches" if any_changed else "CLEAN: unchanged since the manifest was written"))
    return 1 if any_changed else 0


def parse_args():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--repo", help="the git worktree to inspect")
    parser.add_argument("--config", help="the run's config YAML")
    parser.add_argument("--driver", default=None, help="the driver script, if any")
    parser.add_argument("--extra", action="append", default=[], help="an extra file to hash; may repeat")
    parser.add_argument("--command", default=None, help="the submit command string, recorded verbatim")
    parser.add_argument("--out", help="write the manifest here as JSON")
    parser.add_argument("--verify", default=None, help="verify a previously written manifest instead of building one")
    return parser.parse_args()


def main():
    args = parse_args()
    if args.verify:
        sys.exit(verify(args.verify))

    if not args.repo or not args.config or not args.out:
        die("--repo, --config and --out are required unless --verify is given")

    manifest = build_manifest(args.repo, args.config, args.driver, args.extra, args.command)
    Path(args.out).write_text(json.dumps(manifest, indent=2, sort_keys=True))
    print(f"manifest written: {Path(args.out).resolve()}")
    print(f"  head_sha={manifest['head_sha']} branch={manifest['branch']}")
    print(f"  status lines: {len(manifest['status_lines'])}; untracked files: {manifest['untracked']['count']}")


if __name__ == "__main__":
    main()
