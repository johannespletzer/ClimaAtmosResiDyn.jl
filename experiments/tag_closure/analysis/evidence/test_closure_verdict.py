"""G4.5: tests for closure_verdict.py, on synthetic tables.

    python3 test_closure_verdict.py

Each builds a run directory with the closure (and audit) tables a run writes,
with numbers chosen so that the verdict is known, and checks the verdict and
the refusals.
"""
import csv
import io
import os
import sys
import tempfile
import unittest
from contextlib import redirect_stdout

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import closure_verdict  # noqa: E402


def write(path, header, rows):
    with open(path, "w", newline="") as f:
        w = csv.writer(f)
        w.writerow(header)
        w.writerows(rows)


CLOSURE = ["time", "total", "tagged", "residual", "relative", "gross_residual",
           "gross_relative", "scale", "nonpositive_fraction"]


def run_dir(root, name="run"):
    d = os.path.join(root, name, "output_0000")
    os.makedirs(d)
    return d


def verdict(argv):
    out = io.StringIO()
    with redirect_stdout(out):
        result = closure_verdict.main(argv)
    return result, out.getvalue()


class WaterTests(unittest.TestCase):
    def test_pass_and_both_failures(self):
        with tempfile.TemporaryDirectory() as root:
            d = run_dir(root)
            # 1e-3 of the water at 24 h, growth slowing: a pass.
            write(os.path.join(d, "water_tag_closure.csv"), CLOSURE, [
                [0, 1, 1, 0, 0, 0, 0, 1, 0],
                [43200, 1, 1, 0, 0, 6e-4, 6e-4, 1, 0],
                [86400, 1, 1, 0, 0, 1e-3, 1e-3, 1, 0],
            ])
            self.assertEqual(verdict(["water", d])[0], "pass")
            # 3e-3 at 24 h: over the threshold.
            write(os.path.join(d, "water_tag_closure.csv"), CLOSURE, [
                [0, 1, 1, 0, 0, 0, 0, 1, 0],
                [43200, 1, 1, 0, 0, 2e-3, 2e-3, 1, 0],
                [86400, 1, 1, 0, 0, 3e-3, 3e-3, 1, 0],
            ])
            self.assertEqual(verdict(["water", d])[0], "fail")
            # Under the threshold, but growing faster in the second half.
            write(os.path.join(d, "water_tag_closure.csv"), CLOSURE, [
                [0, 1, 1, 0, 0, 0, 0, 1, 0],
                [43200, 1, 1, 0, 0, 2e-4, 2e-4, 1, 0],
                [86400, 1, 1, 0, 0, 1e-3, 1e-3, 1, 0],
            ])
            self.assertEqual(verdict(["water", d])[0], "fail")

    def test_refusals(self):
        with tempfile.TemporaryDirectory() as root:
            d = run_dir(root)
            with self.assertRaises(SystemExit):
                verdict(["water", d])  # no table
            write(os.path.join(d, "water_tag_closure.csv"), CLOSURE, [
                [0, 1, 1, 0, 0, 0, 0, 1, 0],
                [43200, 1, 1, 0, 0, 6e-4, 6e-4, 1, 0],
            ])
            with self.assertRaises(SystemExit):
                verdict(["water", d])  # the table stops before the window's end
            active = os.path.join(root, "run", "output_active")
            os.symlink(d, active)
            with self.assertRaises(SystemExit):
                verdict(["water", active])


class EnergyTests(unittest.TestCase):
    def closure(self, d, grown, throughput=None):
        header = CLOSURE + (["source_throughput"] if throughput is not None else [])
        rows = [[3600, 1e8, 1e8, 0, 0, 100.0, 1e-6, 1e8, 0],
                [86400, 1e8, 1e8, 0, 0, 100.0 + grown, 1e-6, 1e8, 0]]
        if throughput is not None:
            rows[0].append(1e6)
            rows[1].append(1e6 + throughput)
        write(os.path.join(d, "energy_source_tag_closure.csv"), header, rows)

    def test_exact_scale(self):
        with tempfile.TemporaryDirectory() as root:
            d = run_dir(root)
            # 1e3 J/m² over 1e7: 1e-4 of Θx, a pass.
            self.closure(d, 1e3, throughput=1e7)
            result, text = verdict(["energy_source", d])
            self.assertEqual(result, "pass")
            self.assertIn("Θx", text)
            # 3e4 over 1e7: 3e-3, a fail.
            self.closure(d, 3e4, throughput=1e7)
            self.assertEqual(verdict(["energy_source", d])[0], "fail")
            # Just under the threshold on Θx is still a verdict.
            self.closure(d, 1.95e4, throughput=1e7)
            self.assertEqual(verdict(["energy_source", d])[0], "pass")

    def test_the_audit_carries_the_throughput(self):
        with tempfile.TemporaryDirectory() as root:
            d = run_dir(root)
            self.closure(d, 1e3)
            write(os.path.join(d, "energy_source_tag_audit.csv"),
                  ["time", "source_throughput"], [[3600, 0.0], [86400, 1e7]])
            result, text = verdict(["energy_source", d])
            self.assertEqual(result, "pass")
            self.assertIn("Θx", text)

    def test_no_throughput_is_not_assessable(self):
        with tempfile.TemporaryDirectory() as root:
            d = run_dir(root)
            self.closure(d, 1e3)
            self.assertEqual(verdict(["energy_source", d])[0], "not assessable")


if __name__ == "__main__":
    unittest.main()
