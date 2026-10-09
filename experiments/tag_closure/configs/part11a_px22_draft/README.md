# PX22 draft

This is a draft pending the owner. No job is authorized or submitted.

PX22 tests energy at a fixed `c` (PROVENANCE_PATHWAY, PX22). Three D4 jobs on
`main` `bb2bedf23`, each one day at 120 s. They use three new configs in this
directory (owner decision of 2026-10-09):

  - `px22_d4_c.yml`, from `g411x_d4_default.yml` at the fixed
    `c = 166764` J/kg (DECISIONS, 2026-10-09).
  - `px22_d4_2c.yml`, the same at `2c = 333528` J/kg, for the C4 pair.
  - `px22_d4_untagged.yml`, from `g411x_d4_untagged.yml`, the parity twin.

The two tagged configs add output keys only. They add each tag's source,
increment and repair ledgers (`e_src_led_src_*`, `e_src_led_inc_*`,
`e_src_led_fix_*`), the residual's `e_src_led_src_res` and
`e_src_led_srcgross_res`, and the repair's gross `e_src_fixgross_*`. The
per-tag identity check needs these terms from the same state (challenge,
section B). They also add `water_process_record`, the `q_prc_*` records and
`pr` averaged over each hour. EA-C4 separates `c` times the integral of `pr dt`
with them. The twin adds the averaged `pr` only. The tagged configs also set
`energy_source_tag_offset` to `c` or `2c`, which `g411x_d4_default.yml` sets to
110,495 J/kg, the G1 and G2 value. No other model setting changes.
`g411x_d4_default.yml`, `g411x_d4_untagged.yml` and the `g46` configs are
unchanged, so earlier evidence that cites them keeps its provenance.

`preregistration.json` holds the question, the checks, the metrics and the
proposed numbers. Every threshold there is proposed for the owner. Submission
stays the owner's.
