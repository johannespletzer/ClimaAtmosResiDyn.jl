# Parent Budget: Vocabulary

The parent budget is an opt-in conservation audit. Over each accepted time step
it checks whether air mass, total water and total energy changed by what the
accepted step applied, within a declared tolerance. It is off by default.
Set `parent_budget_mode` to `summary` or `audit` to switch it on. A successful
run then writes `parent_budget_report.yaml` to the output directory and logs a
summary.

With it on, every model field that exists without it stays bit for bit as in the
same run with it off, under the default solver settings. Only its own fields and
output are added. The
[fork parity contract](https://github.com/johannespletzer/ClimaAtmosResiDyn.jl/blob/main/docs/clima_atmos_specific.md#fork-parity-with-upstream)
gives the limits.

This page explains the words in plain language for someone reading the report
or configuring a run. The [contract](contract.md) gives the rules and the
arithmetic behind them. Where the two differ, the contract governs.

## What the parent budget counts

  - **Parent quantity**: One of the three totals the model state carries: air
    mass `M`, total water `W` and total energy `E`.
  - **Reservoir**: A place that holds a parent quantity. The atmosphere, and the
    slab surface when a run has one.
  - **Control volume**: The reservoirs a claim is about. The atmosphere alone, or
    the atmosphere and the surface together. The same entries give a different
    answer in each.
  - **Endpoint**: The total of one quantity in one reservoir at the start or the
    end of a step.
  - **Exterior**: Everything the model does not hold, such as space or the ocean
    below a slab. It is named and never measured.

## What can change a total

  - **Accepted step**: One time step the integrator finished and kept. Only
    accepted updates count. Intermediate stages do not.
  - **Channel**: One way the integrator applies an accepted update: the explicit
    tendency, the limited explicit tendency, or the implicit solve. The
    post-implicit correction is part of the implicit channel.
  - **Envelope**: The whole change one channel made to one reservoir in one step,
    measured from the update the integrator applied.
  - **Process**: One physical or numerical path inside a channel, such as
    radiation, a surface flux or microphysics. The processes of a channel are its
    decomposition. They are meant to add up to its envelope.
  - **Final map**: An operation on the accepted state after the tendencies, such
    as limiting, continuity (DSS) or a constraint. Its change counts toward the
    total. It is not a channel and has nothing to decompose.
  - **Transfer event**: One exchange between reservoirs, or between a reservoir
    and the exterior, such as a surface flux or radiation to space.
  - **Leg**: One side of a transfer event in one reservoir, with a sign.
    Positive is into that reservoir.
  - **Topology**: What kind of exchange an event is. An internal event stays within
    one reservoir, a coupled event runs between two modeled reservoirs and an
    exterior event has one side outside the model. The legs of an internal or
    coupled event are expected to cancel. An exterior crossing has nothing to
    cancel against.
  - **Counterparty**: The name of the exterior an exterior crossing goes to. It is
    a label. No number is invented for it.

## The questions it asks

  - **Parent closure**: Did each total change by what the accepted updates say,
    within the declared tolerance? The endpoint change is compared with the
    envelopes plus the final maps.
  - **Attribution**: Do the process amounts add up to their channel's envelope?
  - **Transfer consistency**: Do the separately measured sides of one exchange
    cancel?
  - **Residual**: What is left when one side of a question is subtracted from the
    other. It is always a subtraction. Nothing is written in to make it zero.
  - **Tolerance**: How large a residual still counts as closed. It is declared per
    quantity and calibrated for the run. Without one, no verdict is given.
  - **Claim**: One answer to one question, for one quantity, in one control
    volume, for one step.

## The words in the report

  - **Pass**: Applicable, nothing missing, and the residual is within tolerance.
  - **Fail**: Nothing missing, and the residual is outside tolerance.
  - **Blocked**: Something required is unknown, open or missing, so no claim can
    be made even when the numbers happen to close. The numbers are still shown.
    The report names what blocks.
  - **Not applicable**: Nothing in this control volume owns the quantity, such as
    water in a dry run. It is not a zero and is left out of every sum.
  - **Reported**: A flux across the edge of the control volume or out of the model.
    It is a signed total with no verdict.
  - **Measured, invariant zero, unknown**: What is known about one number. An
    invariant zero is provably zero with the proof named. An unknown number adds
    nothing and blocks the claim it belongs to. It is never read as zero.
  - **Drift**: The running signed sum of residuals. The report shows it beside the
    running sum of absolute residuals and the worst single step, because a signed
    sum can hide two errors that cancel.

Missing information blocks a claim. It is never read as a zero or a pass.

## What it does not cover

The tag families (`ρq_tag_*`, `ρe_tag_*`, `ρe_src_*`) and the process records
(`prc_q_*`, `prc_e_*`) are diagnostics with their own vocabulary in
[Configuring tracers](../tracer_configuration.md). They are not terms of the
parent budget. A tag partition can drift while the parent total closes, and the
parent total can fail to close while every tag sums correctly.
