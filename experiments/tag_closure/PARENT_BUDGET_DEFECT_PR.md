# Draft PR: the parent-budget solve defect test (decision 13)

Branch `claude/parent-budget-defect-test` (`4c15038f`) is pushed to `origin`. Opened as draft PR #81 on 2026-09-17, with this title and body. A first attempt failed because `gh` sent it to the `upstream` remote, `CliMA/ClimaAtmos.jl`.

**Title:** Test the parent-budget solve defect where it stands above rounding

**Body:**

## Why

`test/parent_budget/implicit_attribution_tests.jl`, "The solve defect shrinks when the solve converges", failed on one CI runner (`Downgrade 1.11 - parent_budget` on #72): three Newton iterations left a solve defect of 5.37e-7 against 3.43e-7 for one. The test ran on the dry column, where that defect is already rounding at one iteration, so more iterations cannot shrink it. Measured on terrabyte with the same setup:

| dry column | solve defect (J/m²) | in units of eps × ∫\|ρe_tot\| |
|:--|--:|--:|
| 1 Newton iteration | 2.005e-7 | 1.95 |
| 3 Newton iterations | 1.951e-7 | 1.90 |

A 3% margin on terrabyte and the opposite order on the CI runner: the two numbers are rounding noise, and their order depends on how a machine rounds.

## What changes

Test code only.

- **The convergence check** now runs on the moist DYCOMS column (0M, 10 s steps) that the file already builds, in audit mode. There the defect is a real signal:

  | moist column | solve defect (J/m²) | in rounding units |
  |:--|--:|--:|
  | 1 Newton iteration | 0.040 | 2.5e6 |
  | 3 Newton iterations | 3.7e-4 | 2.3e4 |

  The test requires the one-iteration defect to exceed 1e4 rounding units, and three iterations to leave less than a tenth of it. Both hold with a wide margin.
- **The dry column** keeps its check that a second approximate solver iteration changes the defect by rounding only. The tolerance is now four rounding units, instead of the strict `<=` that the same rounding could break.
- **Unchanged:** the parent identity is still checked in every run.

## Cost and checks

The moist column in audit mode is one more compile in the `parent_budget` group. Locally, Julia 1.11.9: `implicit_attribution_tests.jl` 133 of 133.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

https://claude.ai/code/session_01XNjVD5YEniWtoQBjqDMLL5
