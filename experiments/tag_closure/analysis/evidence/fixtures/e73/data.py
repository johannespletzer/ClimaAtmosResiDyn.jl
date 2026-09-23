"""The E73 regression fixture's raw arrays and metadata.

The repo's .gitignore ignores '*.nc' and '*.json' (they are simulation
outputs everywhere else in this repo), so the fixture cannot be committed as
netCDF files or a JSON report. Instead the trimmed arrays (five time steps:
0, 1, 6, 12, 24 h; all 30 z levels) live in reference.npz and run.npz next to
this file, and test_compare_runs.py's E73 regression test rebuilds real
'<var>_1h_inst.nc' files from them, into a scratch tmp dir, at test time --
the netCDF files themselves are not durable, only the arrays that make them
are. The two runs' '.yml' files are committed as-is (not gitignored).

Built from experiments/tag_closure/output/v3_upd_copies/output_0000 (the
reference) and .../v3_upd_default/output_0002 (the run) by
fixtures/make_e73_fixture.py, then fixtures/e73's own one-off dump to .npz.
"""
from pathlib import Path

import numpy as np

HERE = Path(__file__).resolve().parent

STEMS = [
    "rhoa", "ta", "arup", "waup",
    "e_src_strat", "e_src_tropo", "e_src_rad", "e_src_sfc",
    "e_src_sub", "e_src_mp", "e_src_new_strat", "e_src_new_tropo",
]
PARENT_STEMS = ["rhoa", "ta", "arup", "waup"]
TAG_NAMES = ["strat", "tropo", "rad", "sfc", "sub", "mp", "new_strat", "new_tropo"]

# Units as read from the real files; not stored in the .npz (units are
# strings, and np.savez is for numeric arrays).
UNITS = {
    "rhoa": "kg m^-3",
    "ta": "K",
    "arup": "",
    "waup": "m s^-1",
    "e_src_strat": "J kg^-1",
    "e_src_tropo": "J kg^-1",
    "e_src_rad": "J kg^-1",
    "e_src_sfc": "J kg^-1",
    "e_src_sub": "J kg^-1",
    "e_src_mp": "J kg^-1",
    "e_src_new_strat": "J kg^-1",
    "e_src_new_tropo": "J kg^-1",
}
DATE_UNITS = "seconds since 2010-01-01T00:00:00"
TIME_UNITS = "s"
Z_UNITS = "m"

REFERENCE_DIR = HERE / "reference" / "output_0000"
RUN_DIR = HERE / "run" / "output_0000"


def load(which):
    """which: 'reference' or 'run'. Returns the .npz's arrays."""
    return np.load(HERE / f"{which}.npz")
