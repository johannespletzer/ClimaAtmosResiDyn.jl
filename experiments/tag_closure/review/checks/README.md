# Check scripts behind reviews and instructions

Small scalar checks that support a review's or an instruction's claims. They
are kept here because the session scratchpads they were written in are not
durable.

| Script | Supports | How to run |
|:--|:--|:--|
| `g3_checks.py` | `agent_reviews/g3_water_plan_review.md`: the exchange with weight `q_totᵏ`, the copies' 0M rule, ψ, the sign of the 1M diffusion correction, van Leer against linear reconstruction | `module load python/3.12; python3 g3_checks.py` |
| `plume_sink.py` | The same review, B2: a plume that ignores the updraft's water loss is biased toward low-level water | as above |
| `pr95_blend_check.jl` | The #95 instruction (removed once carried out; text under the tag `archive/g3-programme-2026-09-23`): tests 1 to 5 in Float32 and Float64 | `julia +1.11 --startup-file=no pr95_blend_check.jl` |
| `pr95_blend_alloc.jl` | The same instruction: the proposed operator allocates what `dbe7435c`'s does, and equals it where no bound binds | as above |
| `plan_docs/` (`md_links.py`, `crosswalk_check.py`, `gfm_columns.py`, `semicolons.py`, `preflight.sh`) | `agent_reviews/plan_parts_1_to_3_review_2026-10-07.md`: links and anchors, crosswalk pointers against the quoted base line, table column counts, semicolons outside code and quotes, and the prek equivalent (trailing newline, whitespace, pinned formatter). Run from the repository root with `python/3.12`; each script says its arguments in its docstring. | as above |
