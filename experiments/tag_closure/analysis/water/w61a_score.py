"""Score the W61 addendum (design/W61_ADDENDUM.md, section 4).

    python3 w61a_score.py <passive_dir> <face_dir> [<w61_passive_ledgers.csv>]
"""
import csv
import sys


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
        exp = float(e["export"])
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
    w61 = rows(sys.argv[3])[-1]
    mine = rows(passive_dir + "/ledgers.csv")[-1]
    same = all(w61[k] == mine[k] for k in ("led_repair", "led_repairnet", "led_rescale", "led_empty"))
    out.append("passive arm reproduces W61's passive ledgers byte for byte: %s" % same)
print("\n".join(out))
