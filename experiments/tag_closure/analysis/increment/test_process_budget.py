"""G4.6: a test of process_budget.py on three synthetic runs.

    python3 test_process_budget.py

The runs are built with netCDF4, four 250 m layers and hourly outputs for a
day, with every term of the note's identities set by hand: the residual's
remainder 0.8 J/m² at c and 2 J/m² at 2c (A2 passes, A3 fails), a repair that
keeps the partition's sum (A4 passes), and a column mass change the brackets
miss, 300 J/m², which the follower's left part carries (A5 passes). A second
case breaks parity and must make every verdict not assessable.
"""
import csv
import io
import os
import sys
import tempfile
import unittest
from contextlib import redirect_stdout

import netCDF4 as nc
import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

Z = np.array([125.0, 375.0, 625.0, 875.0])
T = np.arange(25) * 3600.0
LAYERS = 4 * 250.0  # a per-mass value v in every layer, with ρ = 1, integrates to v · 1000


def write_nc(d, var, values, reduction="inst"):
    with nc.Dataset(os.path.join(d, f"{var}_1h_{reduction}.nc"), "w") as ds:
        ds.createDimension("time", None)
        ds.createDimension("z", len(Z))
        ds.createVariable("time", "f8", ("time",))[:] = T
        ds.createVariable("z", "f8", ("z",))[:] = Z
        ds.createVariable(var, "f8", ("time", "z"))[:] = values


def ramp(final):
    """A field growing linearly from 0 to `final` per unit mass over the day."""
    return np.outer(T / T[-1], np.full(len(Z), final))


def make_run(root, name, *, L_R, I, fix, X, L_part, precip, E_change, throughput, ta):
    d = os.path.join(root, name, "output_0000")
    os.makedirs(d)
    write_nc(d, "rhoa", np.ones((len(T), len(Z))))
    write_nc(d, "ta", ta)
    if L_R is None:
        return
    write_nc(d, "e_src_led_src_res", ramp(L_R))
    write_nc(d, "e_src_inc_left", ramp(I))
    write_nc(d, "e_src_fix_strat", ramp(fix))
    write_nc(d, "e_src_fix_tropo", ramp(-fix))
    write_nc(d, "e_src_res", ramp(L_R + I + X))
    write_nc(d, "e_src_led_src_strat", ramp(L_part / 2))
    write_nc(d, "e_src_led_src_tropo", ramp(L_part / 2))
    write_nc(d, "e_prc_precipitation", ramp(precip))
    with open(os.path.join(d, "energy_source_tag_closure.csv"), "w", newline="") as f:
        w = csv.writer(f)
        w.writerow(["time", "total", "gross_residual"])
        for t in T:
            w.writerow([t, 1e8 + E_change * t / T[-1], 0.0])
    with open(os.path.join(d, "energy_source_tag_audit.csv"), "w", newline="") as f:
        w = csv.writer(f)
        w.writerow(["time", "source_throughput"])
        for t in T:
            w.writerow([t, throughput * t / T[-1]])


def build(root, broken_parity=False):
    ta = np.full((len(T), len(Z)), 280.0)
    common = dict(fix=0.001, precip=-0.05, throughput=2e7)
    # B at c: 1000 J/m² over the column; at 2c 700, so c·M_U = c·0 − (−300) = 300.
    make_run(root, "g46_d4_budget", L_R=0.01, I=0.02, X=0.0008, L_part=0.99,
             E_change=5000.0, ta=ta, **common)
    make_run(root, "g46_d4_budget_2c", L_R=0.01, I=0.32, X=0.002, L_part=0.69,
             E_change=5000.0, ta=ta + (1e-12 if broken_parity else 0.0), **common)
    make_run(root, "g46_d4_untagged", L_R=None, I=None, fix=None, X=None, L_part=None,
             precip=None, E_change=None, throughput=None, ta=ta)


def run_budget(root):
    import process_budget
    process_budget.ROOT = root
    process_budget.od4.ROOT = root
    out = io.StringIO()
    with redirect_stdout(out):
        process_budget.report()
    return out.getvalue()


class ProcessBudgetTests(unittest.TestCase):
    def test_verdicts(self):
        with tempfile.TemporaryDirectory() as root:
            build(root)
            text = run_budget(root)
            self.assertIn("bit for bit", text)
            self.assertRegex(text, r"A2: \|X_II\| at 24 h, c: 8\.000e-01 J/m² .*pass")
            self.assertRegex(text, r"A3: \|X_II\| at 24 h, 2c: 2\.000e\+00 J/m² .*fail")
            self.assertRegex(text, r"A4: .*pass")
            self.assertRegex(text, r"A5: .*pass")
            self.assertIn("c·M_U +3.0000e+02", text)

    def test_parity_voids_the_verdicts(self):
        with tempfile.TemporaryDirectory() as root:
            build(root, broken_parity=True)
            text = run_budget(root)
            self.assertIn("DIFFERS: ta", text)
            self.assertIn("not assessable: parity fails for g46_d4_budget_2c", text)
            self.assertNotIn("A2:", text)


if __name__ == "__main__":
    unittest.main()
