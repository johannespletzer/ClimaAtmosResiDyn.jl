"""G3 1.1: a manifest of the worktree, config and environment at job submission.

    python3 manifest.py --repo WORKTREE --config YML [--driver FILE]
                         [--extra FILE ...] [--julia BIN] [--julia-channel +1.11]
                         [--command "..."] --out PATH.json
    python3 manifest.py --verify PATH.json

Compute nodes on terrabyte have no git, which is why a run's provenance.txt
reads `commit_dirty: unknown` (G3_TODO.md 1.1). This tool runs on the login
node, before a job is submitted, and records what the login node can see and
the compute node cannot: the worktree's actual HEAD, its dirty files (and the
diff itself, not just a hash of it), the untracked files (each one, with its
own hash), the resolved `.buildkite` Manifest/Project/LocalPreferences, the
config, driver and any extra file, the paths a config itself names
(`restart_file`, `external_forcing_file`, `toml`, `era5_*`), and the
environment: the Julia binary and channel the job will actually use, the
loaded modules, `JULIA_DEPOT_PATH`, the relevant Julia/CliMA env vars,
hostname, UTC time, and the submit command string.

Every git call goes through `git --no-optional-locks`, so running this tool
never itself touches the worktree it is inspecting (no index lock, no
stat-refresh write); it is safe to run alongside other work in the same
worktree.

`--verify PATH.json` re-reads a written manifest, recomputes every hash and
git fact from scratch against the same repo and files, and prints what
changed since. A clean, unchanged worktree reports every field "unchanged".
Fields this tool added after a manifest was written are not in that old
manifest's schema; --verify reports their current value as "(new field)"
rather than comparing them, so old manifests (four exist under
experiments/tag_closure/output/w*/manifest.json) keep verifying cleanly.
"""
import argparse
import hashlib
import json
import os
import re
import shutil
import socket
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

# Env vars whose value can change whether a run is bitwise reproducible.
RELEVANT_ENV_VARS = (
    "JULIA_NUM_THREADS",
    "JULIA_CPU_TARGET",
    "JULIA_DEPOT_PATH",
    "OMP_NUM_THREADS",
    "OPENBLAS_NUM_THREADS",
    "MKL_NUM_THREADS",
    "CLIMACOMMS_CONTEXT",
    "CLIMACOMMS_DEVICE",
)

# Config keys that name a path outside the repository. `toml` may be a YAML
# list (`toml: [a.toml, b.toml]`) or given as a bare `key: value`. `era5_*`
# covers whatever era5 path keys a config adds, without listing each one.
CONFIG_PATH_KEY_RE = re.compile(r"^(restart_file|external_forcing_file|toml|era5_[A-Za-z0-9_]*):\s*(.+?)\s*$")

# A file this large is recorded by size and mtime, not hashed; restart files
# and ERA5 inputs can be many GB, and hashing them on every submission would
# make the manifest itself the bottleneck.
HASH_SIZE_LIMIT = 200 * 1024 * 1024


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


def get_head_on_remote(repo):
    """Every remote ref that contains HEAD. A detached HEAD on none of these
    is lost once the worktree is removed and git garbage collection runs
    (S7): the manifest records this so that gap is visible at write time,
    not discovered later."""
    raw = git_text(repo, ["for-each-ref", "--contains", "HEAD", "refs/remotes"], required=False)
    refs = []
    for line in raw.splitlines():
        parts = line.split(None, 2)
        if len(parts) >= 3:
            refs.append(parts[2])
    return refs


def parse_porcelain_z(repo):
    """One `git status -z` call, parsed into (xy, path, orig_path) records.
    `-z` is used instead of the default porcelain v1 quoting (M3): a path
    with a space in it arrives quoted (`"a b.txt"`) under v1 and is then not
    a file on disk, which made the tool die trying to hash it."""
    raw = git_bytes(repo, ["status", "--porcelain=v1", "--untracked-files=all", "-z"]).stdout
    parts = raw.split(b"\x00")
    entries = []
    i = 0
    while i < len(parts):
        rec = parts[i]
        i += 1
        if not rec:
            continue
        xy = rec[:2].decode("utf-8", errors="replace")
        path = rec[3:].decode("utf-8", errors="replace")
        orig_path = None
        if xy[0] in ("R", "C") and i < len(parts):
            orig_path = parts[i].decode("utf-8", errors="replace")
            i += 1
        entries.append({"xy": xy, "path": path, "orig_path": orig_path})
    return entries


def status_lines_from_entries(entries):
    lines = []
    for e in entries:
        line = f"{e['xy']} {e['path']}"
        if e["orig_path"] is not None:
            line += f" <- {e['orig_path']}"
        lines.append(line)
    return lines


def get_untracked(repo, entries):
    """Every untracked file (not directory), individually with its own
    sha256 (S7: a dirty or partly-committed run must be rebuildable from the
    manifest, not just detectable as dirty), its count, and one combined
    sha256 over the sorted (path, sha256) list for a quick equality check."""
    paths = sorted(e["path"] for e in entries if e["xy"] == "??")
    files = []
    for rel in paths:
        full = Path(repo) / rel
        if not full.is_file():
            die(f"untracked entry '{rel}' is not a plain file (git status --untracked-files=all should only list files)")
        files.append({"path": rel, "sha256": sha256_file(full)})
    combined = "\n".join(f"{f['path']}\t{f['sha256']}" for f in files).encode("utf-8")
    return {
        "count": len(files),
        "sha256": hashlib.sha256(combined).hexdigest() if files else None,
        "files": files,
    }


def get_buildkite_files(repo):
    """Project.toml and LocalPreferences.toml by their fixed names, plus
    every Manifest-v*.toml actually present. The old code only ever hashed
    Manifest-v1.11.toml, so a 1.10 run's manifest -- which git ignores, so no
    other record sees it either -- was invisible (S8)."""
    result = {}
    buildkite = Path(repo) / ".buildkite"
    for name in ("Project.toml", "LocalPreferences.toml"):
        path = buildkite / name
        result[name] = sha256_file(path) if path.is_file() else None
    for path in sorted(buildkite.glob("Manifest-v*.toml")):
        result[path.name] = sha256_file(path)
    return result


def resolve_julia(julia_arg, channel_arg):
    """The Julia binary and channel this manifest should record, matching
    what the submit path actually uses (S8): `--julia`/`--julia-channel`
    override; otherwise the JULIA/JULIA_CHANNEL env vars that
    runscripts/tag_closure_common.sh itself reads; otherwise whatever `julia`
    resolves to on PATH with the `+1.11` channel juliaup defaults to."""
    binary = julia_arg or os.environ.get("JULIA") or shutil.which("julia") or "julia"
    if channel_arg is not None:
        channel = channel_arg
    else:
        channel = os.environ.get("JULIA_CHANNEL", "+1.11")
    return binary, channel


def get_julia_info(binary, channel):
    cmd = [binary] + ([channel] if channel else []) + ["--version"]
    try:
        proc = subprocess.run(cmd, capture_output=True, text=True, timeout=60)
    except FileNotFoundError:
        die(f"julia binary not found or not runnable: {binary}")
    except subprocess.TimeoutExpired:
        die(f"'{' '.join(cmd)}' did not return within 60s")
    if proc.returncode != 0:
        die(f"'{' '.join(cmd)}' failed: {proc.stderr.strip()}")
    return proc.stdout.strip()


def get_loaded_modules():
    """Lmod exports LOADEDMODULES as a colon-separated list; this needs no
    subprocess (the `module` shell function is not on a plain PATH)."""
    raw = os.environ.get("LOADEDMODULES", "")
    return [m for m in raw.split(":") if m]


def get_env_vars():
    return {name: os.environ.get(name) for name in RELEVANT_ENV_VARS}


def parse_config_path_values(config_path):
    """Every `restart_file`, `external_forcing_file`, `toml` and `era5_*`
    value in the config, as raw strings. `toml` may be a bracketed list."""
    values = []
    for line in Path(config_path).read_text().splitlines():
        m = CONFIG_PATH_KEY_RE.match(line)
        if not m:
            continue
        key, raw_value = m.group(1), m.group(2)
        raw_value = raw_value.split("#", 1)[0].strip()  # trailing comment
        if raw_value.startswith("[") and raw_value.endswith("]"):
            items = [v.strip().strip('"').strip("'") for v in raw_value[1:-1].split(",") if v.strip()]
        else:
            items = [raw_value.strip('"').strip("'")]
        for item in items:
            if item:
                values.append((key, item))
    return values


def resolve_config_paths(config_path, repo):
    """Resolve every path a config names outside the repository. Each entry
    records the real path, and either its sha256 (small files) or its size
    and mtime (large ones, e.g. a restart checkpoint or an ERA5 file, which
    can be many GB). Refuses a path that goes through `output_active`: that
    link moves when the run it points at is rerun, so the manifest would
    then describe an input that has silently changed under it (S8)."""
    entries = []
    for key, raw_value in parse_config_path_values(config_path):
        candidate = Path(raw_value)
        if not candidate.is_absolute():
            candidate = Path(repo) / raw_value
        if "output_active" in candidate.parts:
            die(
                f"config path '{key}: {raw_value}' resolves through output_active, "
                "which moves when the run it names is rerun; point at the explicit "
                "output_XXXX directory instead"
            )
        entry = {"key": key, "raw": raw_value, "resolved": str(candidate)}
        if candidate.is_file():
            resolved = candidate.resolve()
            entry["resolved"] = str(resolved)
            entry["exists"] = True
            size = resolved.stat().st_size
            entry["size"] = size
            entry["mtime"] = datetime.fromtimestamp(resolved.stat().st_mtime, tz=timezone.utc).isoformat()
            entry["sha256"] = sha256_file(resolved) if size <= HASH_SIZE_LIMIT else None
        else:
            entry["exists"] = False
            entry["size"] = None
            entry["mtime"] = None
            entry["sha256"] = None
        entries.append(entry)
    return entries


def build_manifest(repo, config_raw, driver_raw, extra_raw, command, julia_arg=None, julia_channel_arg=None):
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

    status_entries = parse_porcelain_z(repo)
    julia_binary, julia_channel = resolve_julia(julia_arg, julia_channel_arg)
    diff_bytes = git_bytes(repo, ["diff", "HEAD", "--binary", "--no-ext-diff", "--no-textconv"]).stdout

    return {
        "repo": str(repo_path.resolve()),
        "head_sha": git_text(repo, ["rev-parse", "HEAD"]).strip(),
        "branch": get_branch(repo),
        "head_on_remote": get_head_on_remote(repo),
        "status_lines": status_lines_from_entries(status_entries),
        "diff_sha256": hashlib.sha256(diff_bytes).hexdigest(),
        "diff": diff_bytes.decode("utf-8", errors="replace"),
        "untracked": get_untracked(repo, status_entries),
        "buildkite_files": get_buildkite_files(repo),
        "config": config,
        "driver": driver,
        "extra": extra,
        "config_paths": resolve_config_paths(config["path"], repo),
        "julia_version": get_julia_info(julia_binary, julia_channel),
        "julia_binary": julia_binary,
        "julia_channel": julia_channel,
        "loaded_modules": get_loaded_modules(),
        "julia_depot_path": os.environ.get("JULIA_DEPOT_PATH", ""),
        "env_vars": get_env_vars(),
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


def compare_dict_subset(name, recorded, fresh, lines):
    """Compare only the keys the recorded manifest actually has. A field the
    tool started recording later (e.g. a second Manifest-v*.toml, or the
    'files' list under 'untracked') is new to an old manifest's schema, not
    a change since it was written, so it is reported as new rather than
    CHANGED (kept backward compatible with the four manifests already on
    disk)."""
    any_changed = False
    for key in sorted(recorded):
        old_v, new_v = recorded[key], fresh.get(key)
        if old_v == new_v:
            lines.append(f"  unchanged: {name}.{key}")
        else:
            lines.append(f"  CHANGED: {name}.{key}")
            lines.append(f"    was: {old_v}")
            lines.append(f"    now: {new_v}")
            any_changed = True
    for key in sorted(set(fresh) - set(recorded)):
        lines.append(f"  (new field, not in old manifest): {name}.{key} = {fresh[key]!r}")
    return any_changed


def compare_optional(name, recorded, fresh, key, lines):
    """Compare `key` only if the recorded manifest has it; otherwise report
    the current value as new, informational only."""
    if key not in recorded:
        lines.append(f"  (new field, not in old manifest): {name} = {fresh.get(key)!r}")
        return
    compare_field(name, recorded[key], fresh.get(key), lines)


def verify(json_path):
    recorded = json.loads(Path(json_path).read_text())
    fresh = build_manifest(
        recorded["repo"],
        recorded["config"]["path"],
        recorded["driver"]["path"] if recorded["driver"] else None,
        [e["path"] for e in recorded["extra"]],
        recorded.get("command"),
        julia_arg=recorded.get("julia_binary"),
        julia_channel_arg=recorded.get("julia_channel"),
    )
    print(f"verify: {json_path}")
    print(f"repo:   {recorded['repo']}")
    print(f"recorded at {recorded['utc_time']} on {recorded['hostname']}; verifying now on {fresh['hostname']}")
    lines = []
    changed = []

    def track(name, key):
        before = len(lines)
        compare_optional(name, recorded, fresh, key, lines)
        changed.append(any(l.strip().startswith("CHANGED") for l in lines[before:]))

    track("head_sha", "head_sha")
    track("branch", "branch")
    compare_optional("head_on_remote (informational)", recorded, fresh, "head_on_remote", lines)
    track("status_lines", "status_lines")
    track("diff_sha256", "diff_sha256")
    changed.append(compare_dict_subset("untracked", recorded.get("untracked", {}), fresh["untracked"], lines))
    changed.append(compare_dict_subset("buildkite_files", recorded.get("buildkite_files", {}), fresh["buildkite_files"], lines))
    compare_field("config.sha256", recorded["config"]["sha256"], fresh["config"]["sha256"], lines)
    changed.append(recorded["config"]["sha256"] != fresh["config"]["sha256"])
    compare_field(
        "driver.sha256",
        recorded["driver"]["sha256"] if recorded["driver"] else None,
        fresh["driver"]["sha256"] if fresh["driver"] else None,
        lines,
    )
    changed.append((recorded["driver"]["sha256"] if recorded["driver"] else None) != (fresh["driver"]["sha256"] if fresh["driver"] else None))
    old_extra = [e["sha256"] for e in recorded["extra"]]
    new_extra = [e["sha256"] for e in fresh["extra"]]
    compare_field("extra.sha256", old_extra, new_extra, lines)
    changed.append(old_extra != new_extra)
    track("julia_version", "julia_version")
    compare_optional("julia_binary (informational)", recorded, fresh, "julia_binary", lines)
    compare_optional("julia_channel (informational)", recorded, fresh, "julia_channel", lines)
    compare_optional("loaded_modules (informational)", recorded, fresh, "loaded_modules", lines)
    compare_optional("julia_depot_path (informational)", recorded, fresh, "julia_depot_path", lines)
    compare_optional("env_vars (informational)", recorded, fresh, "env_vars", lines)
    compare_optional("config_paths (informational)", recorded, fresh, "config_paths", lines)
    compare_field("hostname (informational)", recorded["hostname"], fresh["hostname"], lines)

    print("\n".join(lines))
    any_changed = any(changed)
    print("\nresult: " + ("DIRTY: the recorded state no longer matches" if any_changed else "CLEAN: unchanged since the manifest was written"))
    return 1 if any_changed else 0


def parse_args():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--repo", help="the git worktree to inspect")
    parser.add_argument("--config", help="the run's config YAML")
    parser.add_argument("--driver", default=None, help="the driver script, if any")
    parser.add_argument("--extra", action="append", default=[], help="an extra file to hash; may repeat")
    parser.add_argument("--julia", default=None, help="the julia binary the job will use (default: $JULIA or PATH)")
    parser.add_argument("--julia-channel", default=None, help="the juliaup channel, e.g. +1.11 (default: $JULIA_CHANNEL or +1.11)")
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

    manifest = build_manifest(
        args.repo, args.config, args.driver, args.extra, args.command,
        julia_arg=args.julia, julia_channel_arg=args.julia_channel,
    )
    Path(args.out).write_text(json.dumps(manifest, indent=2, sort_keys=True))
    print(f"manifest written: {Path(args.out).resolve()}")
    print(f"  head_sha={manifest['head_sha']} branch={manifest['branch']}")
    print(f"  status lines: {len(manifest['status_lines'])}; untracked files: {manifest['untracked']['count']}")


if __name__ == "__main__":
    main()
