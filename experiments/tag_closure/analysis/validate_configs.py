"""Validate every tag-closure configuration, and prove the checks are live.

    python3 experiments/tag_closure/analysis/validate_configs.py
    python3 experiments/tag_closure/analysis/validate_configs.py --mutations

Each file is checked against `config/default_configs/default_config.yml` for key
existence and value type, then against the per-run invariants of the plan's
common protocol, per tag family. `--mutations` breaks a copy of the tree in
fifteen ways and asserts every one is caught, so the checks below are
demonstrably live rather than merely present.

Python rather than Julia because this is the tool that was actually run while
the configurations were written, and porting it to Julia would mean shipping an
unverified rewrite: the container these were written in has no Julia. It needs
only PyYAML. `analysis/selftest.jl` invokes it and skips with a message if
neither the interpreter nor PyYAML is there, so the Julia self-test does not
gain a hard dependency on it.

Exit status is non-zero when anything fails, so it can gate a commit.
"""
import glob, os, sys

try:
    import yaml
except ImportError:  # pragma: no cover - environment dependent
    sys.stderr.write(
        "validate_configs.py needs PyYAML (pip install --user pyyaml).\n"
    )
    sys.exit(2)

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))
CFG = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "configs")

schema = {
    k: v["value"]
    for k, v in yaml.safe_load(
        open(os.path.join(ROOT, "config/default_configs/default_config.yml"))
    ).items()
}

# family -> (tracer key, check key, residual diagnostic, per-tag prefixes,
#            ledger prefix or None)
FAMILIES = {
    "water": ("water_tracers", "water_closure_check", "q_tag_res",
              ("q_tag_", "qv_tag_", "q_tag_fix_"), "q_tag_fix_"),
    "energy": ("energy_tracers", "energy_closure_check", "e_tag_res",
               ("e_tag_",), None),
    "energy_source": ("energy_source_tags", "energy_source_closure_check",
                      "e_src_res", ("e_src_",), None),
}

# Runs that deliberately carry no tags: the per-phase timing controls.
CONTROLS = {"a1_dt10_notags", "b1_notags", "c0_column_notags"}
# The only run allowed a limiter, and the only one allowed Float32.
LIMITER_OK = {"a5_sphere_limiter", "b3_limiter"}
FLOAT32_OK = {"a4_float32"}
# Runs that must set `audit: true` on their closure block, and no others. The
# audit costs a handful of global reductions and answers a question that run
# has and the rest do not; see each config's own comment. It is checked in both
# directions so that neither dropping it from a run that needs it nor spraying
# it over runs that do not passes silently.
AUDIT_REQUIRED = {
    "a5_sphere_limiter",
    "c0_sphere_deep",
    "c0_sphere_audit",
    "c1_sphere_shift",
}

def shorts(config):
    out = set()
    for entry in config.get("diagnostics", []) or []:
        name = entry["short_name"]
        out |= set(name if isinstance(name, list) else [name])
    return out

def is_region_tag(tag):
    """A pure region tag, the set the closure residual sums over.

    Not "has a region and no source": `tag_sources_from_config` skips the label
    `none`, so a tag written with `source: none` has no sources and the model
    counts it in the partition.
    """
    if "region" not in tag:
        return False
    source = tag.get("source")
    if source is None:
        return True
    labels = [source] if isinstance(source, str) else list(source)
    return all(str(label) == "none" for label in labels)

def duplicate_keys(path):
    """Top-level keys bound more than once.

    YAML.jl keeps the last binding and a stricter reader keeps the first, so a
    repeated key is a file that means different things to different readers.
    That turned three B1 variants into copies of B1 once already.
    """
    seen, repeated = set(), []
    for line in open(path):
        if line[:1].isalnum() and ":" in line:
            key = line.split(":", 1)[0]
            if key in seen:
                repeated.append(key)
            seen.add(key)
    return repeated

def check(path):
    name = os.path.basename(path)[:-4]
    config = yaml.safe_load(open(path))
    problems = []

    # 0. No top-level key bound twice.
    for key in duplicate_keys(path):
        problems.append("key %r is bound more than once" % key)

    # 1. Every key exists in the schema, with a compatible value type.
    for key, value in config.items():
        if key == "job_id":
            continue
        if key not in schema:
            problems.append("UNKNOWN KEY %r" % key)
            continue
        default = schema[key]
        if default is None or key in ("hyperdiff", "diagnostics"):
            continue
        same_boolness = isinstance(default, bool) == isinstance(value, bool)
        numeric_ok = isinstance(default, float) and isinstance(value, (int, float))
        if not same_boolness or (
            not isinstance(default, bool)
            and type(default) is not type(value)
            and not numeric_ok
        ):
            problems.append("TYPE %s: default %r vs %r" % (key, default, value))

    # 2. The run names itself.
    if config.get("job_id") != name:
        problems.append("job_id %r != file name" % config.get("job_id"))

    # 3. Precision, per the common protocol.
    want_float = "Float32" if name in FLOAT32_OK else "Float64"
    if config.get("FLOAT_TYPE") != want_float:
        problems.append("FLOAT_TYPE %r, want %r" % (config.get("FLOAT_TYPE"), want_float))

    # 4. The defaults are off, so the explicit block is the whole output.
    if config.get("output_default_diagnostics") is not False:
        problems.append("output_default_diagnostics is not false")

    # 5. No limiter and no nonnegativity method outside the two runs that
    #    exist to measure one.
    for key in ("apply_sem_quasimonotone_limiter", "tracer_nonnegativity_method"):
        if key in config and name not in LIMITER_OK:
            problems.append("configures %s outside a limiter run" % key)
    if name in LIMITER_OK and config.get("apply_sem_quasimonotone_limiter") is not True:
        problems.append("a limiter run without the limiter")

    # 5b. Cross-key model consistency the schema check cannot see. These
    #     mirror `check_case_consistency` in `src/config/model_getters.jl`,
    #     which runs inside `get_atmos` -- that is, after the queue, after
    #     Julia starts and after the packages load. A configuration that trips
    #     one of these validates cleanly here and then dies on the node, which
    #     is what happened to the first `c0_sphere_deep` submission.
    if config.get("implicit_diffusion") is True and not (
        config.get("vert_diff") or config.get("turbconv")
    ):
        problems.append(
            "implicit_diffusion: true without vert_diff or turbconv "
            "(model_getters.jl:1074 asserts on this)"
        )

    # 6. Per family: tags and check together, a pure region tag, the check
    #    period, no tolerance, and the diagnostics that phase needs.
    listed = shorts(config)
    covered = set()
    active = 0
    for family, (tracer_key, check_key, residual, prefixes, ledger) in FAMILIES.items():
        tags = config.get(tracer_key)
        block = config.get(check_key)
        if tags is None and block is None:
            continue
        if (tags is None) != (block is None):
            problems.append(
                "%s: %s and %s must be present or absent together; the check "
                "errors at startup without its family" % (family, tracer_key, check_key)
            )
            continue
        active += 1
        region = [t["name"] for t in tags if is_region_tag(t)]
        if not region:
            problems.append("%s: no tag with a region and no source" % family)
        if "tolerance" in block:
            problems.append("%s: tolerance set; leave it at the default" % family)
        if "period" not in block:
            problems.append("%s: no period" % family)
        wants_audit = name in AUDIT_REQUIRED
        if bool(block.get("audit")) != wants_audit:
            problems.append(
                "%s: audit is %r, want %r"
                % (family, block.get("audit"), wants_audit or None)
            )
        need = {residual}
        if ledger:
            need |= {ledger + r for r in region}
        if need - listed:
            problems.append("%s: diagnostics missing %s" % (family, sorted(need - listed)))
        legal = {residual} | {p + t["name"] for t in tags for p in prefixes}
        covered |= legal

    # Process records add their own diagnostic names.
    for label in config.get("energy_process_record", []) or []:
        covered.add("e_prc_" + label)
    for label in config.get("water_process_record", []) or []:
        covered.add("q_prc_" + label)

    if name in CONTROLS:
        if active:
            problems.append("a timing control must configure no tag family")
        if listed:
            problems.append("a timing control should list no diagnostics")
    else:
        if active != 1:
            problems.append("expected exactly one tag family under test, found %d" % active)
        stray = listed - covered
        if stray:
            problems.append("diagnostics the run will not register: %s" % sorted(stray))

    # 6b. Phase A's ladder fires the closure check every step, so its period is
    #     that run's own dt and changes down the ladder. A sphere run uses an
    #     hour. This is what makes the three A1 residuals comparable.
    if name.startswith("a") and name not in CONTROLS:
        block = config.get("water_closure_check") or {}
        want = "1hours" if name == "a5_sphere_limiter" else config.get("dt")
        if block.get("period") != want:
            problems.append(
                "closure period %r, want %r (phase A fires every step)"
                % (block.get("period"), want)
            )

    # 7. Nothing asks for a reduction: every sample is instantaneous.
    for entry in config.get("diagnostics", []) or []:
        if "reduction_time" in entry:
            problems.append("reduction_time set; samples must be instantaneous")
        if "period" not in entry:
            problems.append("a diagnostics entry has no period")

    return name, problems, config

# The fifteen classes of mistake these checks exist to catch. Each is applied
# to a copy of one real configuration; `--mutations` asserts every one is
# caught. A check that stops catching its mutation is a check that has quietly
# stopped working.
MUTATIONS = [
    ("drop the closure check, keep the tags", "c0_column.yml",
     lambda t: t.replace('energy_source_closure_check:\n  period: "1hours"', "")),
    ("drop the region tags, keep a source tag", "b1_base.yml",
     lambda t: t.replace(
         "  - name: tropics\n    region: tropics\n"
         "  - name: extratropics\n    region: extratropics",
         "  - name: hs\n    source: held_suarez")),
    ("set a tolerance", "b1_base.yml",
     lambda t: t.replace(
         '  period: "6hours"',
         '  period: "6hours"\n  tolerance: 1.0e-3', 1)),
    ("ask for an averaged diagnostic", "c0_sphere.yml",
     lambda t: t.replace('    period: "1hours"',
                         '    period: "1hours"\n    reduction_time: average', 1)),
    ("ask for a diagnostic the run will not register", "c0_column.yml",
     lambda t: t.replace("e_src_rad]", "e_src_nope]")),
    ("wrong FLOAT_TYPE", "b2_dry_hs.yml",
     lambda t: t.replace('FLOAT_TYPE: "Float64"', 'FLOAT_TYPE: "Float32"')),
    ("a typo'd key", "b1_base.yml", lambda t: t.replace("vert_diff:", "vertical_diff:")),
    # The one that got through. `c0_sphere_deep` carried `implicit_diffusion`
    # from a numerics common config that expects its partner to supply a
    # diffusion model, validated clean, and died in `check_case_consistency`
    # after the queue.
    ("implicit diffusion with no diffusion model", "c0_sphere_deep.yml",
     lambda t: t.replace("viscous_sponge: true",
                         "viscous_sponge: true\nimplicit_diffusion: true")),
    ("a limiter outside a limiter run", "c0_column.yml",
     lambda t: t + "apply_sem_quasimonotone_limiter: true\n"),
    ("default diagnostics left on", "b1_base.yml",
     lambda t: t.replace("output_default_diagnostics: false",
                         "output_default_diagnostics: true")),
    ("a control that still lists diagnostics", "b1_notags.yml",
     lambda t: t + 'diagnostics:\n  - short_name: [e_tag_res]\n    period: "6hours"\n'),
    ("phase A closure period no longer tracks dt", "a1_dt5.yml",
     lambda t: t.replace('water_closure_check:\n  period: "5secs"',
                         'water_closure_check:\n  period: "10secs"')),
    ("job_id not matching the file name", "b3_limiter.yml",
     lambda t: t.replace('job_id: "b3_limiter"', 'job_id: "b3"')),
    ("missing the q_tag_fix ledger diagnostic", "a1_dt10.yml",
     lambda t: t.replace("[q_tag_res, q_tag_fix_upper, q_tag_fix_lower]", "[q_tag_res]")),
    ("a top-level key bound twice", "b1_base.yml",
     lambda t: t + "vert_diff: ~\n"),
    ("the audit dropped from the run that needs it", "a5_sphere_limiter.yml",
     lambda t: t.replace('  period: "1hours"\n  audit: true',
                         '  period: "1hours"')),
]

def bad_continuations(path):
    """Lines of *code* ending in a backslash, which Julia does not continue.

    Inside a string literal a trailing backslash joins lines. Outside one it is
    the left-division operator, and Base's generic fallback for that is
    `\\(x, y) = adjoint(adjoint(y) / adjoint(x))`. So

        @assert cond \\
            "a message"

    parses as `cond \\ "a message"` and dies far away with
    `MethodError: no method matching adjoint(::String)`, naming neither the file
    nor the operator. One of these cost two runs on Levante.

    A full scan rather than a line-based one, because block comments and quotes
    inside `$(...)` interpolations both defeat counting quotes per line.
    """
    src = open(path).read()
    n, i, line = len(src), 0, 1
    in_str = in_tstr = False
    depth = 0
    offenders = []
    while i < n:
        c = src[i]
        if depth:
            if src.startswith("=#", i): depth -= 1; i += 2; continue
            if src.startswith("#=", i): depth += 1; i += 2; continue
            if c == "\n": line += 1
            i += 1; continue
        if not (in_str or in_tstr):
            if src.startswith("#=", i): depth = 1; i += 2; continue
            if c == "#":
                while i < n and src[i] != "\n": i += 1
                continue
            if src.startswith('"""', i): in_tstr = True; i += 3; continue
            if c == '"': in_str = True; i += 1; continue
            if c == "\\":
                j = i + 1
                while j < n and src[j] in " \t": j += 1
                if j < n and src[j] == "\n":
                    offenders.append(line)
                i += 1; continue
            if c == "\n": line += 1
            i += 1; continue
        if in_tstr and src.startswith('"""', i): in_tstr = False; i += 3; continue
        if in_str and c == '"': in_str = False; i += 1; continue
        if c == "\\":
            if i + 1 < n and src[i + 1] == "\n": line += 1
            i += 2; continue
        if c == "\n":
            line += 1
            if in_str: in_str = False
        i += 1
    return offenders

def lint_continuations():
    """Refuse a backslash continuation in Julia code anywhere in analysis/."""
    here = os.path.dirname(os.path.abspath(__file__))
    failed = 0
    for path in sorted(glob.glob(os.path.join(here, "*.jl"))):
        for line in bad_continuations(path):
            print("FAIL %s:%d backslash continuation in code" %
                  (os.path.basename(path), line))
            failed += 1
    print("%d backslash continuations in code" % failed)
    return 1 if failed else 0

def run_mutations():
    """Break a copy of the tree fifteen ways; every one must be caught."""
    import shutil, tempfile
    missed = []
    for label, target, mutate in MUTATIONS:
        with tempfile.TemporaryDirectory() as tmp:
            copy = os.path.join(tmp, "configs")
            shutil.copytree(CFG, copy)
            path = os.path.join(copy, target)
            text = open(path).read()          # read before opening for write
            broken = mutate(text)
            if broken == text:
                print("BROKEN HARNESS %-46s did not change %s" % (label, target))
                missed.append(label)
                continue
            with open(path, "w") as handle:
                handle.write(broken)
            files = sorted(glob.glob(os.path.join(copy, "*.yml")))
            caught = any(check(f)[1] for f in files)
            caught = caught or duplicate_keys(path)
            print(("CAUGHT  " if caught else "MISSED  ") + label)
            if not caught:
                missed.append(label)
    print("\n%d of %d mutations caught" % (len(MUTATIONS) - len(missed), len(MUTATIONS)))
    return 1 if missed else 0

def main():
    if "--mutations" in sys.argv:
        return run_mutations()
    if "--lint-continuations" in sys.argv:
        return lint_continuations()
    paths = sorted(glob.glob(os.path.join(CFG, "*.yml")))
    failed = 0
    for path in paths:
        name, problems, config = check(path)
        if problems:
            failed += 1
            print("FAIL %-22s %s" % (name, "; ".join(problems)))
        else:
            fam = [
                f for f, (tk, _, _, _, _) in FAMILIES.items() if config.get(tk)
            ]
            print("ok   %-22s %s" % (name, ", ".join(fam) or "no tags (control)"))

    print("\n%d configs, %d with problems" % (len(paths), failed))
    return 1 if failed else 0

if __name__ == "__main__":
    sys.exit(main())
