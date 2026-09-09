# Learnings

The barrier register for the tag-closure experiments. One entry per run, added
by the agent after the owner has committed that run's files under `output/`.

This file is the point of the series. The runs exist to find which practical
barriers stop the source-tag method in a real simulation, so that the decision
named in [the source-tag page](../../docs/src/energy_source_tags.md) — whether
to use energy source tracing at all, or to combine water source tracing with the
energy process record — is taken on measurements rather than on argument. A
number that is not written down here has not been learned.

## What every entry answers

  - **What barrier did the run show, if any.** A run that showed none says so,
    and that is a result. Name the quantity and its value, not an impression.
  - **Is the barrier numerical, structural or a cost.** Numerical is a residual,
    a negative tag, a non-positive parent, a `Float32` floor. Structural is a
    process that no bracket covers. A cost is walltime, memory or Jacobian size.
  - **Does it carry over to the source tags.** The source tags ride the same
    passive-scalar path as the energy tags and get no corrections at all, so a
    barrier measured on the water or energy families is usually a floor for
    theirs rather than a separate finding. Say which it is.

A crash is a barrier like any other and earns its entry. So does a run that was
submitted and came back uninteresting.

## Entry shape

Each entry names the run, the commit it ran on and the date, so it can be placed
against the rest of the series, and then answers the three questions above.

```markdown
## <run>

Ran at `<commit>` on `<date>`, <node type>, <partition>, SLURM job `<id>`.

**Barrier.** ...

**Class.** Numerical / structural / cost, and why.

**Carry-over to the source tags.** ...
```

The commit, the date and the node come from that run's `provenance.txt`. A run
whose provenance is missing is not analysed and gets no entry; the agent asks
for it instead.

## Entries

None yet. No run has been submitted.
