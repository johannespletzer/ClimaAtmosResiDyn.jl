# Parent Budget: The Vocabulary in Plain Language

The words the parent budget uses, in simple terms, for someone reading
`parent_budget_report.yaml` or configuring a run. The
[closure contract](contract.md) defines the same terms normatively in its
glossary and fixes the arithmetic behind them. When the two differ, the
contract governs. This page exists so the contract does not have to be read
first.

## Three families of bookkeeping words

Budget is the parent's, ledger is a tag's, record is a process's. The rest of
this page explains only the first family.

  - **Parent budget**: The check this page describes, in the module
    `ParentBudget`. Over each accepted step it compares the change of `∫ρ`,
    `∫ρq_tot` and `∫ρe_tot` with what the timestepper applied. Its per-step
    store is the journal, and it writes `parent_budget_report.yaml`.
  - **Tag ledger**: A running total that a tag correction keeps of what it
    moved. It comes in three kinds. A *repair ledger* is `q_tag_fix_*` or
    `e_src_fix_*`, held in the cache as `ᶜwater_fix` or `ᶜenergy_source_fix`.
    An *increment ledger* is `e_src_inc_left`, `e_src_inc_moved` or
    `q_tag_inc_*`. A *mechanism ledger* is `q_tag_led_*` or `e_src_led_*`.
    This version of the code does not define `q_tag_inc_*`, `q_tag_led_*` or
    `e_src_led_*`. They are named in the tag-closure design notes.
  - **Closure residual**: The parent minus the sum of the tags. It is
    `q_tag_res`, `e_src_res` or `e_tag_res`.
  - **Process record**: One process's signed history of the parent tendency,
    `prc_e_<process>` or `prc_q_<process>`, written out as `e_prc_*` and
    `q_prc_*`. The noun "record" means only this.

## What the parent budget counts

  - **Parent quantity**: One of the three totals the model state carries: air
    mass, total water, and total energy. The parent budget is about these
    three and nothing else.
  - **Reservoir**: A place that holds a parent quantity. The atmosphere, and the
    slab surface when a run has one.
  - **Control volume**: The reservoirs a claim is about. The atmosphere alone, or
    the atmosphere and the surface together. The same entries give a different
    answer in each.
  - **Endpoint**: The total of one quantity in one reservoir at the start or the
    end of a step, integrated from the model state.
  - **Exterior**: Everything the model does not hold, such as space, or the
    ocean below a slab. It is named, and never measured.

## What can change a total

  - **Accepted step**: One time step the integrator finished and kept. Only
    accepted updates count; what happens on an intermediate stage does not.
  - **Channel**: One of the ways the integrator applies an accepted update: the
    explicit tendency, the limited explicit tendency, and the implicit solve.
    The post-implicit correction is applied inside the implicit solve's update,
    so it is a piece of that channel rather than a channel of its own.
  - **Envelope**: The whole change one channel made to one reservoir in one
    step, measured as one number from the update the integrator applied.
  - **Process**: One physical or numerical path inside a channel. Radiation, a
    surface flux, microphysics, and so on.
  - **Decomposition**: The per-process pieces that are supposed to add up to a
    channel's envelope.
  - **Final map**: An operation applied to the accepted state after the
    tendencies, such as limiting, continuity (DSS), or a constraint. Its change
    counts toward the parent total, but it is not a channel and has nothing to
    decompose.
  - **Transfer event**: One exchange between reservoirs, or between a reservoir
    and the exterior: a surface flux, or radiation to space. Every leg of the
    exchange shares its name.
  - **Leg**: One side of a transfer event in one reservoir, with a sign.
    Positive means into that reservoir.
  - **Topology**: What kind of exchange an event is. *Internal* stays within one
    reservoir, *coupled* runs between two modeled reservoirs, and *exterior* has
    one side outside the model. The legs of an internal or coupled event are
    expected to cancel; an exterior crossing has nothing to cancel against.
  - **Counterparty**: The name of the exterior an exterior crossing goes to. It
    is a label. No number is ever invented for it.

## The three questions the parent budget asks

  - **Parent closure**: Did each total change by exactly what the accepted
    updates say? The endpoint change is compared with the envelopes plus the
    final maps.
  - **Attribution**: Do the per-process pieces add up to their channel's
    envelope?
  - **Transfer consistency**: Do the separately measured sides of one exchange
    cancel?
  - **Residual**: What is left when one side of a question is subtracted from
    the other. It is always a subtraction. Nothing is ever written in to make
    it zero.
  - **Tolerance**: How large a residual still counts as closed. Declared per
    quantity and calibrated for the run. Without one, no verdict is given.
  - **Claim**: One answer to one question, for one quantity, in one control
    volume, for one step.

## How the parent budget decides

  - **Schema**: Everything the parent budget expects, declared from the
    configuration before the first step: which reservoirs own which quantity,
    which channels, maps and events must report, and what each is expected to
    do.
  - **Disposition**: What a declaration expects of one quantity: measured,
    provably zero, not applicable, or open.
  - **Open**: Not established yet. An open row demands nothing of an entry and
    blocks every claim it feeds, because a sum over a row nobody has
    established proves nothing.
  - **Roster**: The list of process rows a channel's decomposition must record.
    A row that never arrives blocks the channel's attribution and is named.
  - **Component status**: What is known about one number: measured, invariant
    zero, not applicable, or unknown.
  - **Invariant zero**: Provably zero, with the proof named. Safe to add into a
    sum.
  - **Not applicable**: A quantity this configuration does not have here, such
    as water in a dry run. Not a zero. Left out of every sum.
  - **Unknown**: A number nobody established. It adds nothing and blocks the
    claim it belongs to. It is never read as zero.
  - **Fail closed**: The rule behind all of the above. Missing information
    blocks a claim rather than being read as zero or as a pass.
  - **Execution identity**: What makes one recording unique: its reservoir,
    channel, event, leg, step, stage and occurrence. The same one twice is
    refused.
  - **Stage observation**: A raw before/after difference taken on an
    intermediate stage. Kept as evidence for locating a defect, and never
    counted.

## The words in the parent-budget report

  - **Pass**: Applicable, nothing missing, and the residual is within tolerance.
  - **Fail**: Nothing missing, and the residual is outside tolerance.
  - **Blocked**: Something required is unknown, open, or missing. No claim can
    be made, even when the numbers happen to close. The numbers are still
    shown.
  - **Not applicable**: Nothing in this control volume owns the quantity.
  - **Reported**: A flux across the edge of the control volume, or out of the
    model. A signed total with no verdict, because there is nothing on the
    other side to cancel against.
  - **Drift**: The running signed sum of residuals over the steps so far. It is
    reported next to the running sum of absolute residuals and the worst single
    step, because a signed sum alone can hide two errors that cancel.

## What this vocabulary does not cover

The source tags `ρq_tag_*`, `ρe_src_*` and `ρe_tag_*`, and the process records
`prc_q_*` and `prc_e_*`, are diagnostics with a vocabulary of their own, defined
in [Configuring tracers](../tracer_configuration.md). They are never terms of
the parent budget. A tag partition can drift while the parent total closes, and
the parent total can fail to close while every tag sums correctly.
