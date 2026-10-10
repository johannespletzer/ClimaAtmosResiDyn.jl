"""Assemble the runtime_validation proof that production_gate reads (part 9).

    python3 water_tag_application_proof.py BUNDLE_DIR --receipt application_receipt.json
        --source PRODUCER_SOURCE --logs LOG_DIR --environment TEXT [--out lifecycle_evidence.json]

LOG_DIR holds one `<check>.log` per gate check, the output of
water_tag_application_checks.py, and `<check>.cmd`, the command that wrote it.
The script copies the logs and the producer source into BUNDLE_DIR, reads each
log with the registry's check_log_pattern and writes the proof:
kind runtime_validation, the receipt's model identity and integrator pin,
producer_id, producer_source and the six checks with result, command,
environment and log. A check is PASS only when its log names it PASS and
never FAIL. It prints the new artifact names and their SHA256 for the
bundle's `artifacts`. It registers nothing: register_producer is called in the
record follow-up, after the checks pass on the cluster.
"""

import argparse
import json
import re
import shutil
import sys
from pathlib import Path

from manifest import sha256_file

REGISTRY_CONFIG = Path(__file__).with_name("water_tag_application_registry.json")
GATE_CHECKS = ("accepted_weights", "trial_rollback", "newton_replacement", "complete_active_roster",
               "parent_bitwise_parity", "all_channel_checkpoint_restart")
PROOF = "lifecycle_evidence.json"


class ProofError(ValueError):
    pass


def load_registry(path=REGISTRY_CONFIG):
    return json.loads(Path(path).read_text())


def registry_entry(receipt_pin, path=REGISTRY_CONFIG, allow_pending=False):
    """The entry for register_producer, with cts_version from the cluster receipt's pin.

    Refused while the config is pending, unless a dry test asks for it.
    """
    config = load_registry(path)
    if config["status"] != "registered" and not allow_pending:
        raise ProofError("the registry entry is pending. Register only after the six checks pass on the cluster")
    entry = dict(config["entry"])
    entry["cts_version"] = receipt_pin["version"]
    return config["producer_id"], entry


def check_result(log_text, key, pattern):
    results = [m["result"] for m in re.finditer(pattern, log_text, re.MULTILINE) if m["check"] == key]
    return "PASS" if results and all(r == "PASS" for r in results) else "FAIL"


def build_proof(bundle_dir, receipt, source, logs, environment, out=PROOF, registry=REGISTRY_CONFIG):
    bundle_dir, logs = Path(bundle_dir), Path(logs)
    config = load_registry(registry)
    pattern = config["entry"]["check_log_pattern"]
    header = json.loads((bundle_dir / receipt).read_text())
    artifacts = {}
    source_name = "producer_source/" + Path(source).name
    (bundle_dir / "producer_source").mkdir(exist_ok=True)
    shutil.copy2(source, bundle_dir / source_name)
    artifacts[source_name] = sha256_file(bundle_dir / source_name)
    checks = {}
    (bundle_dir / "lifecycle_logs").mkdir(exist_ok=True)
    for key in GATE_CHECKS:
        log, cmd = logs / f"{key}.log", logs / f"{key}.cmd"
        if not log.is_file() or not cmd.is_file():
            raise ProofError(f"no log or command for {key} in {logs}")
        name = f"lifecycle_logs/{key}.log"
        shutil.copy2(log, bundle_dir / name)
        artifacts[name] = sha256_file(bundle_dir / name)
        checks[key] = {"result": check_result(log.read_text(), key, pattern), "command": cmd.read_text().strip(),
                       "environment": environment, "log": name}
    proof = {"kind": "runtime_validation", "model_commit": header["model_commit"],
             "model_diff_sha256": header["model_diff_sha256"], "producer_id": config["producer_id"],
             "integrator_pin": header["integrator_pin"], "producer_source": source_name, "checks": checks}
    (bundle_dir / out).write_text(json.dumps(proof, sort_keys=True, indent=1) + "\n")
    artifacts[out] = sha256_file(bundle_dir / out)
    return proof, artifacts


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("bundle_dir")
    parser.add_argument("--receipt", default="application_receipt.json")
    parser.add_argument("--source", required=True)
    parser.add_argument("--logs", required=True)
    parser.add_argument("--environment", required=True)
    parser.add_argument("--out", default=PROOF)
    args = parser.parse_args(argv)
    try:
        proof, artifacts = build_proof(args.bundle_dir, args.receipt, args.source, args.logs, args.environment, args.out)
    except (ProofError, OSError, KeyError) as exc:
        print(f"REFUSED: {exc}", file=sys.stderr)
        return 2
    print(json.dumps({"checks": {k: v["result"] for k, v in proof["checks"].items()}, "artifacts": artifacts}, indent=1))
    return 0 if all(v["result"] == "PASS" for v in proof["checks"].values()) else 1


if __name__ == "__main__":
    sys.exit(main())
