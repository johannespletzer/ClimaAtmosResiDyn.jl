"""
The P2/P3 profile's table (design/WP9_COST.md section 8). It decides nothing.

    python3 analysis/wp9_profile_table.py $SCRATCH/tag_closure/output/wp9_profile [--out table.md]

The argument has one directory per arm, each with the CSVs that
`wp9_profile_driver.jl` writes for its two points. Per arm it lays the low and
the high tag count side by side:
  - the timed block (ms and bytes per step) and the profiles' totals;
  - time and allocation per step by phase, and their growth;
  - the frames that hold the growth in allocation and in time, largest first,
    until they hold 80% of it or ten rows are shown;
  - the functions P2 and P3 name, and the bytes of type `String`.

A frame that is outside one point's top 80 is read as 0 there, so a frame's
growth can be overstated by at most the 80th frame's value. The table prints
that bound.
"""

import argparse
import csv
import sys
from pathlib import Path


def read(path):
    with open(path) as f:
        return list(csv.DictReader(f))


def keyed(rows, key, col):
    return {r[key]: float(r[col]) for r in rows}


def growth_rows(lo, hi, unit_fmt, limit=10, cover=0.8):
    keys = set(lo) | set(hi)
    deltas = sorted(((hi.get(k, 0.0) - lo.get(k, 0.0), k) for k in keys), reverse=True)
    total = sum(hi.values()) - sum(lo.values())
    out, acc = [], 0.0
    for d, k in deltas:
        if len(out) >= limit or (total > 0 and acc >= cover * total):
            break
        acc += d
        share = f"{100 * d / total:.1f}%" if total > 0 else "n/a"
        out.append(f"| `{k}` | {unit_fmt(lo.get(k, 0.0))} | {unit_fmt(hi.get(k, 0.0))} | {unit_fmt(d)} | {share} |")
    return total, acc, out


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("root", type=Path)
    parser.add_argument("--out", type=Path)
    args = parser.parse_args()
    lines = []
    for arm in sorted(p for p in args.root.iterdir() if p.is_dir()):
        summaries = sorted((read(f)[0] for f in arm.glob("*_summary.csv")), key=lambda r: int(r["ntags"]))
        if len(summaries) != 2:
            lines += [f"### {arm.name}: {len(summaries)} finished points, not 2; no comparison.", ""]
            continue
        lo, hi = summaries
        stem = {s["ntags"]: str(arm / s["label"]) for s in summaries}

        def tab(s, name):
            return read(stem[s["ntags"]] + f"_{name}.csv")

        n_lo, n_hi = lo["ntags"], hi["ntags"]
        lines += [
            f"### {arm.name}: `{lo['base']}`, {n_lo} and {n_hi} tags, commit `{lo['commit'][:8]}`",
            "",
            f"Hosts {lo['host']} / {hi['host']}, load {lo['loadavg1']} / {hi['loadavg1']}.",
            "",
            f"| measure | {n_lo} tags | {n_hi} tags |",
            "|:--|--:|--:|",
        ]
        for col, fmt in (("step_ms", "{:.3f}"), ("bytes_per_step", "{:.0f}"), ("allocs_per_step", "{:.0f}"),
                         ("alloc_bytes_per_step_est", "{:.0f}"), ("samples", "{:.0f}"),
                         ("alloc_recorded", "{:.0f}"), ("tag_code_time_share", "{:.3f}"),
                         ("tag_code_alloc_share", "{:.3f}")):
            lines.append(f"| {col} | {fmt.format(float(lo[col]))} | {fmt.format(float(hi[col]))} |")
        lines.append("")

        tp_lo, tp_hi = (keyed(tab(s, "time_phase"), "phase", "ms_per_step") for s in (lo, hi))
        ap_lo, ap_hi = (keyed(tab(s, "alloc_phase"), "phase", "bytes_per_step") for s in (lo, hi))
        lines += [f"| phase | ms/step {n_lo} | ms/step {n_hi} | B/step {n_lo} | B/step {n_hi} |",
                  "|:--|--:|--:|--:|--:|"]
        for ph in sorted(set(tp_lo) | set(tp_hi) | set(ap_lo) | set(ap_hi),
                         key=lambda k: -(ap_hi.get(k, 0.0) - ap_lo.get(k, 0.0))):
            lines.append(f"| {ph} | {tp_lo.get(ph, 0.0):.3f} | {tp_hi.get(ph, 0.0):.3f} "
                         f"| {ap_lo.get(ph, 0.0):.0f} | {ap_hi.get(ph, 0.0):.0f} |")
        lines.append("")

        for what, name, col, fmt in (("allocation", "alloc_frame", "bytes_per_step", lambda x: f"{x:.0f} B"),
                                     ("time", "time_frame", "ms_per_step", lambda x: f"{x:.3f} ms")):
            f_lo, f_hi = (keyed(tab(s, name), "frame", col) for s in (lo, hi))
            floor = max(min(f_lo.values(), default=0.0), min(f_hi.values(), default=0.0))
            total, acc, rows = growth_rows(f_lo, f_hi, fmt)
            lines += [f"Growth in {what} per step, {n_lo} to {n_hi} tags: {fmt(total)} over the top-80 frames; "
                      f"the rows below hold {fmt(acc)}. A frame outside a point's top 80 is read as 0 "
                      f"(bound: {fmt(floor)}).", "",
                      f"| innermost frame in `src/` | {n_lo} | {n_hi} | growth | share of growth |",
                      "|:--|--:|--:|--:|--:|"] + rows + [""]

        w_lo, w_hi = (tab(s, "watch") for s in (lo, hi))
        lines += [f"| P2/P3 function on the stack | time share {n_lo} | time share {n_hi} | B/step {n_lo} | B/step {n_hi} |",
                  "|:--|--:|--:|--:|--:|"]
        for a, b in zip(w_lo, w_hi):
            lines.append(f"| `{a['function']}` | {float(a['time_share']):.4f} | {float(b['time_share']):.4f} "
                         f"| {float(a['bytes_per_step']):.0f} | {float(b['bytes_per_step']):.0f} |")
        t_lo, t_hi = (keyed(tab(s, "alloc_type"), "type", "bytes_per_step") for s in (lo, hi))
        lines += ["", f"Type `String`: {t_lo.get('String', 0.0):.0f} B/step at {n_lo} tags, "
                  f"{t_hi.get('String', 0.0):.0f} B/step at {n_hi} (0 if outside the top 40 types).", ""]
        total, acc, rows = growth_rows(t_lo, t_hi, lambda x: f"{x:.0f} B", limit=5)
        lines += ["| type | " + n_lo + " | " + n_hi + " | growth | share of growth |", "|:--|--:|--:|--:|--:|"] + rows + [""]
    text = "\n".join(lines)
    print(text)
    if args.out:
        args.out.write_text(text + "\n")


if __name__ == "__main__":
    sys.exit(main())
