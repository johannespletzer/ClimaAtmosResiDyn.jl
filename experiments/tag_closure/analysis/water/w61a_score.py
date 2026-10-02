"""Score the W61 addendum (design/W61_ADDENDUM.md, section 4).

    python3 w61a_score.py <passive_dir> <face_dir> [<w61_passive_ledgers.csv>]

The driver's `export` column is `dt * sum(sfc)` with `sfc` on the bottom face
level of the 3D space. ClimaCore's `sum` on that level keeps the 3D weight, so
it returns the area integral times the bottom face's height, 250 m on W61's
grid (`analysis/water/w61a_export_weight.jl`, `output/w61a/export_weight.txt`).
The scorer divides the column by that height to get kg. This correction was
added in review, after the first scoring (`beb503f7`), which read the raw
column as kg.
"""
import csv
import sys

# `sum` on the bottom face level over `sum` on the horizontal space, the same
# at every point (w61a_export_weight.jl, shallow and deep geometry alike).
SFC_SUM_HEIGHT = 250.00000000014091


def rows(path):
    with open(path) as f:
        return list(csv.DictReader(f))


def last_by_tag(inv):
    t_end = max(float(r["t"]) for r in inv)
    t0 = min(float(r["t"]) for r in inv)
    start = {r["tag"]: r for r in inv if float(r["t"]) == t0}
    end = {r["tag"]: r for r in inv if float(r["t"]) == t_end}
    return start, end, t_end


passive_dir, face_dir = sys.argv[1], sys.argv[2]
out = []
for arm, d in (("passive", passive_dir), ("face", face_dir)):
    start, end, t_end = last_by_tag(rows(d + "/inventory.csv"))
    for tag in sorted(end):
        s, e = start[tag], end[tag]
        inv0 = float(s["inventory"])
        exp = float(e["export"]) / SFC_SUM_HEIGHT
        for form in ("pass", "face"):
            signed = float(e["ref_" + form])
            gross = float(e["ref_" + form + "_abs"])
            out.append(
                "%s arm, %s, %s form at %.0f h: signed %.3e (%.3e of start inventory, %.3e of export), "
                "absolute %.3e (%.3e of inventory, %.3e of export); inventory %.3e -> %.3e, export %.3e"
                % (arm, tag, form, t_end / 3600, signed, signed / inv0, signed / exp,
                   gross, gross / inv0, gross / exp, inv0, float(e["inventory"]), exp)
            )
    var = rows(d + "/variance.csv")
    for form in ("var_pass", "var_face", "var_cross"):
        later = [float(r[form]) for r in var if float(r["t"]) >= 21600]
        out.append("%s arm, %s from 6 h: max %.3e, min %.3e, positive samples %d of %d"
                   % (arm, form, max(later), min(later), sum(v > 0 for v in later), len(later)))
    led = rows(d + "/ledgers.csv")[-1]
    out.append("%s arm, ledgers at the end: %s" % (arm, {k: v for k, v in led.items()}))
# The rules of section 4.
start, end, _ = last_by_tag(rows(face_dir + "/inventory.csv"))
inv_ok = all(abs(float(end[t]["ref_face"])) <= 1e-9 * float(start[t]["inventory"]) for t in end)
var = rows(face_dir + "/variance.csv")
mix_ok = all(float(r["var_face"]) < 0 for r in var if float(r["t"]) >= 21600)
out.append("Q2 inventory rule (|face| <= 1e-9 of start inventory, face arm): %s" % ("pass" if inv_ok else "FAIL"))
out.append("Q2 mixing rule (face variance rate < 0 from 6 h, face arm): %s" % ("pass" if mix_ok else "FAIL"))
if len(sys.argv) > 3:
    w61 = rows(sys.argv[3])
    mine = rows(passive_dir + "/ledgers.csv")
    keys = ("t", "led_repair", "led_repairnet", "led_rescale", "led_empty")
    same = len(w61) == len(mine) and all(a[k] == b[k] for a, b in zip(w61, mine) for k in keys)
    out.append("passive arm reproduces W61's passive ledgers byte for byte (all %d samples): %s"
               % (len(mine), same))
# Review checks, not pre-registered.
for arm, d in (("passive", passive_dir), ("face", face_dir)):
    start, end, t_end = last_by_tag(rows(d + "/inventory.csv"))
    net = sum(float(end[t]["ref_pass"]) for t in end)
    total = sum(float(start[t]["inventory"]) for t in start)
    out.append("review, %s arm: passive form summed over the tags at %.0f h: %.3e (%.3e of the total start "
               "inventory); face form summed: %.3e"
               % (arm, t_end / 3600, net, net / total, sum(float(end[t]["ref_face"]) for t in end)))
_, end_p, _ = last_by_tag(rows(passive_dir + "/inventory.csv"))
_, end_f, _ = last_by_tag(rows(face_dir + "/inventory.csv"))
for tag in sorted(end_p):
    d_inv = float(end_f[tag]["inventory"]) - float(end_p[tag]["inventory"])
    est = -float(end_p[tag]["ref_pass"])
    out.append("review, %s: face arm's inventory minus passive arm's at the end %.3e; the driver's estimate "
               "(minus the passive arm's ref_pass) %.3e; ratio %.3f" % (tag, d_inv, est, d_inv / est))
print("\n".join(out))
