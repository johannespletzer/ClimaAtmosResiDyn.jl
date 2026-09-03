# Parent-Budget Ledger: Architecture

How the parent-budget ledger is put together. The [contract](contract.md) fixes
what it claims; this page fixes the shapes that make those claims affordable,
reproducible, and localizable. The [coverage registry](coverage.md) lists the
paths, and the [implementation plan](plan.md) sequences the work.

Three constraints drive every choice here. Accounting must not change the
trajectory. A global integral is a collective, and a four-stage IMEX method with
dozens of instrumented paths cannot afford one collective per leg. And when a
budget fails to close, the output has to say *where*, which means evidence
survives long enough to distinguish a missing leg from a duplicated one from a
mismatched pair.

## Data flow

```
per accepted step

  state Y ──▶ local accumulation (accounting precision)
                    │
                    ├── endpoint slots      ┐
                    └── leg slots           ├──▶ one packed buffer, fixed layout
                                            ┘         │
                                                      ▼
                                        one global collective per step
                                                      │
                                                      ▼
                            unpack ──▶ endpoints + legs, with per-component
                                       status and evidence
                                                      │
                        ┌─────────────────────────────┼─────────────────────────┐
                        ▼                             ▼                         ▼
                  parent residual            attribution residual       transfer residual
              (endpoints vs envelopes    (envelope vs its classified   (legs of one event
               and final maps)            events)                       across a view)
```

The three residuals are computed from the same journal and are never combined.

## One journal, three budgets

A single event journal holds every leg of an accepted step. A leg carries a
mass, a water, and an energy component together, because the three budgets have
to stay coordinated across a coupled exchange: the same deposition event moves
water out of the atmosphere, mass with it, and the energy the water carried.
Splitting them into three journals would make that one event three, and nothing
would keep the three in step.

**Status and evidence are per component, never per leg.** One event routinely
measures energy, proves a mass zero, and has nothing to say about water. A
per-leg status would have to pick one of the three, and whichever it picked
would misdescribe the others. Each component therefore carries its own status
and its own evidence record, which names the collection or proof method, the
adapter or registry entry it came from, and the precision and reduction route
where those matter.

Two things stay out of the journal's summable set entirely. A **stage
observation** is a raw before/after difference on an intermediate stage array;
it is stored in its own structure, shares no interface with a leg, and no
projection iterates it. And a **residual** has no representation at all: it is
produced by subtraction at reconciliation time, so there is no way to write one
into the journal as a balancing entry.

## Collection: local, then packed, then global

### Accounting precision comes first

`Fields.local_sum` accumulates in the element type of the expression it is
given. Converting to the accounting type **after** a completed `Float32`
reduction recovers nothing — the information is already gone in the
accumulation. So the conversion is part of the expression that is reduced, and
the accumulation itself runs in the accounting type.

`ClimaCore`'s reductions accept a lazy `Broadcasted` over a field, so widening
costs no materialized copy: the widened element type promotes the product with
the geometric weight, and the accumulator follows.

### Local and global reductions are different things

`Base.sum(field)` in `ClimaCore` is `local_sum` followed by a
`ClimaComms.allreduce!`. It is therefore **one collective per call**, and a
production endpoint interface that calls it once per quantity per reservoir
issues a handful of collectives every time it is used.

The ledger splits the two:

  - **Local accumulation** produces one number per slot on each rank, with no
    communication. On a device this is a device-side reduction.
  - **Packet construction** writes those numbers into a fixed-layout buffer.
  - **One packed collective** reduces the whole buffer, once per accepted step.
  - **Unpacking** builds the endpoints and legs from the reduced buffer.

Only the third step communicates, and it communicates once.

### The packet layout is fixed and deterministic

Slots are assigned by a layout computed from the configuration, not by the order
events happen to be recorded in. Every rank builds the same layout, so the
reduction is well defined, and the same run produces the same layout on every
invocation, so a residual is reproducible.

A fixed layout also bounds memory: the buffer is sized from the registry rather
than growing with the number of recorded events, and per-step storage does not
grow with run length.

### Endpoint reuse

The closing endpoint of step `n` is the opening endpoint of step `n+1`, and
measuring it twice repeats the same reduction over the same unchanged state.
Reusing it halves the endpoint reductions per step.

The trade is explicit: reuse gives up the continuity comparison that would catch
something mutating `Y` between the two readings. That comparison is what turns a
callback that quietly writes state into an error rather than a silent gap in the
cumulative total. Reuse is therefore sound exactly while no supported callback
mutates `Y`, which is a property of the model established by the coverage
registry, not a property of the ledger. Both paths exist and the report records
which one was used.

## Transactions

One transaction per accepted step. It opens on the finalized endpoint of step
`n`, collects legs, and closes on the finalized endpoint of step `n+1`.

**The commit is atomic.** Every reconciliation is computed into temporaries and
validated before the ledger is touched, and only then are the cumulative totals
advanced and the transaction closed. A failure part way through a commit
otherwise leaves a ledger that has half-counted a step it never committed, with
nothing in its own state to say so.

**Ordering is deterministic.** Events are recorded against stable identifiers,
and each recording carries an execution identity — step, stage, occurrence — so
a path that legitimately fires several times within one accepted step stays
legible and a path that fires twice by mistake is refused at the second
recording rather than surfacing as a residual a step later.

**Bounded per-step memory.** Legs are cleared on commit. Cumulative state is a
fixed set of totals per quantity and control volume. An audit mode may retain
per-step detail on request; the default summary mode must not, because retaining
every event over a long run is unbounded growth.

## Restarts

A restart restores state that no transaction produced. Two representations are
allowed and the report says which was used:

  - A **zero-duration transition**, so the restoration is its own transaction
    and is never charged to the next step; or
  - **Deliberate segmentation**, where the cumulative record restarts and the
    report names the segment boundary.

Silently absorbing a restart into the next step's residual is not allowed. Where
carrying cumulative ledger state across a restart is semantically valid, it is
preserved rather than reset.

## The timestepper adapter

All timestepper-specific knowledge lives in one adapter. The transaction and
reconciliation code knows nothing about ClimaAtmos processes, and the journal
knows nothing about tableaus.

The adapter owns:

  - the pinned `ClimaTimeSteppers` version and algorithm it is written against;
  - which channels exist and what an accepted envelope for each one is;
  - the accepted stage weights, and how to obtain an applied increment rather
    than an endpoint difference;
  - which hooks are already folded into an effective implicit increment;
  - the algebraic solve defect, with its sign and accepted weight.

An executable trace test records the stage construction and hook order the
adapter assumes, so that a change in the pinned version fails a test instead of
silently changing the meaning of every implicit leg.

Process classification lives in the other single source of truth, the coverage
registry, which the documentation table is generated from or checked against.

## Rules the design enforces

  - Nothing in the ledger writes to authoritative state. A run with accounting
    enabled produces the same trajectory as one without it, bitwise, and that is
    tested rather than asserted.
  - A residual is a subtraction and has no representation as a leg.
  - An aggregate envelope and its own decomposition are never both summed.
  - An unknown component blocks its claim and contributes zero to nothing.
  - No hidden global mutable state: a ledger is an ordinary value threaded
    through the integrator's cache.
  - Unsupported configurations and undeclared state-mutating callbacks fail at
    setup, before a long simulation starts.

## Implementation state

This page describes the architecture the contract requires. Which parts exist at
any moment is recorded in the [implementation plan](plan.md), which names for
each stack step the claim it establishes and its definition of done, and in the
[coverage registry](coverage.md), whose collection-state column is the per-path
answer.
