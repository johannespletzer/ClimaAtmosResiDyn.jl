# Residence time is the term for the passive-tracer timescale

## Decision

The stratospheric passive tracers measure a **residence time**. That is the main and
only term for it. `lifetime` is retired everywhere it names this quantity: in the budget
table, the post-processing script, the docstrings and the comments.

## Why

The tracers have one source, a constant production rate inside a box above the
tropopause, and one sink, relaxation to zero below the tropopause. Once the burden stops
drifting,

    τ = burden / source

which is how long air released in that box takes to leave the stratosphere. In the
transport-time literature that is the residence time, or interior-to-exit transport time.
Hall and Waugh (1999JD901096) name the same ratio directly: under steady state and
stationary transport, `burden / source` equals the mean first-exit time of a pulse.

`lifetime` means something else. It is the full persistence timescale of injected
material, usually lag plus decay, and for aerosol or chemically produced tracers it
includes formation and microphysical loss. None of that applies here: the tracers are
inert, they are produced continuously rather than injected, and nothing removes them but
the tropopause sink. A column named `lifetime` invites a reader to take τ for a decay
time, which it is not.

The repository already says residence time in prose. `docs/src/passive_tracers.md`,
`docs/strat_tracer_campaign_plan.md`, `docs/clima_atmos_specific.md`, `NEWS.md` and the
three `strat_tracers_*` configs all use it, while every identifier says lifetime. The two
words currently look like two different quantities.

## Terms that stay out

These name other transport times and no diagnostic here measures them:

  - **age of air**, entry-to-interior transport;
  - **transit time** or **CSTT**, entry-to-exit;
  - **lag time** and **decay time**, the two parts of a lifetime;
  - **chemical** or **steady-state stratospheric lifetime**, which is set by chemistry
    rather than by exit through the tropopause.

## What the rename touches

  - `src/parameterized_tendencies/chemistry/stratospheric_passive_tracers.jl` — the
    `lifetime`, `lifetime_years` and `lifetime_from_loss` columns of
    `tracer_budget_header()`, the values written next to them, the file header, and the
    `TropopauseRelativeHeight` and `GeometricHeight` docstrings.
  - `post_processing/tracer_lifetimes.jl` — the file name, and the `tracer_lifetime` and
    `tracer_lifetime_summary` functions.
  - `post_processing/plot_tracer_burdens.jl`, which includes that file.
  - `src/callbacks/get_callbacks.jl` and `src/diagnostics/stratospheric_tracer_diagnostics.jl`
    — comments and docstrings.
  - `experiments/passive_stratospheric_tracers.jl`, the four `passive_stratospheric_*`
    and `strat_tracers_*` configs, `test/parameterized_tendencies/chemistry/passive_stratospheric_tracers.jl`,
    `docs/src/passive_tracers.md`, `docs/src/tracer_configuration.md` and `NEWS.md`.

Renaming the budget columns breaks anything already reading
`stratospheric_tracer_budget.csv`, so the rename needs a NEWS entry.

## Worth stating once the term is fixed

Three limits follow from the definition and are not documented yet:

  - `burden / source` equals a mean first-exit time only under **stationary transport**
    as well as steady source-loss balance. The `imbalance` column tests the balance;
    nothing tests stationarity, and a transient run such as the 1979-2021 campaign does
    not have it. There the ratio is a history-weighted inventory time.
  - The value is tied to the **soft sink**, relaxation on `loss_timescale` below the
    tropopause, not to a hard tropopause boundary.
  - It is a **source-weighted mean over the box**, and it is not the mean age of the air
    still in the stratosphere. That is why the boxes are kept small.

Reporting `burden / source` and `burden / loss` side by side is already the right pair and
should stay.
