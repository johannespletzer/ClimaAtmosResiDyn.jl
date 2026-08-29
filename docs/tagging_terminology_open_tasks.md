# Open tasks in the tracer tagging work

This is a checklist, not a decision record. It collects the loose ends left by
the tagging pull requests so they are not rediscovered one at a time in review.
Each entry says what is wrong or missing, where, and what would close it. Delete
an entry when it is done.

The decisions themselves belong in the pull requests that make them. Nothing
here is a commitment to a particular answer.

## Naming

### "Process-change record" names two different things

The phrase is used for two products that the KT Boost Fund method note keeps
deliberately apart.

  - In `docs/src/tracer_configuration.md` and `docs/src/tagged_tracers.md` it is
    the quantity an `energy_tracers` entry with a `source` holds: a prognostic
    `ρe_tag_<name>` field, transported, signed, one per tag.
  - In the process-record work it is the `prc_<process>` family behind the
    `energy_process_record` and `water_process_record` keys: cache-resident, not
    transported, one field per process.

Those are the method note's item 4 and its B respectively. They differ in what
they are attached to, whether they move, and what they can be summed over. The
glossary currently defines the first and then, three paragraphs later, sends the
reader to the second under the same words.

Closing it: keep "process-change record" for the `prc_*` family alone, and call
an `energy_tracers` `source` entry a *signed process tag* in prose. Both names
already appear; only the shared one has to go. This is documentation only, but
it should be settled before the process-record PR merges, since that is the PR
that introduces the collision.

### The glossary counts two tag families, and there will be three

`docs/src/tracer_configuration.md` opens its glossary with "Two of these
families use the word 'tag'". That is true today. It stops being true when
`energy_source_tags` lands, which adds `ρe_src_<name>` as a third.

The same file's "Which one do I want?" table has three rows and no entry for
`energy_source_tags`, `energy_process_record` or `water_process_record`. A
reader who arrives at the configuration reference will not learn the new keys
exist.

Closing it: fix both in the PR that adds the third family, not afterwards.

### Corrections on the wording PR have not reached the stacked branches

Commit 5517913 on `claude/tagging-a-and-b` corrected four overstated claims: a
citation the repository does not make, the assertion that the `source` key
selects the same processes in both families, an unqualified "process tags are
unaffected" by the energy reference, and "never negative" for a water tag. The
stacked branches were cut before it, so each still carries the old text.

This resolves itself when the stack merges in order. It matters only in the
meantime, to a reviewer who reads a stacked branch and reports a finding that is
already fixed one PR down.

## Limits that are documented but not lifted

These are stated in the docs and in the diagnostic `comments`, so nothing is
hidden. They are listed here because they are the natural next pieces of work,
not because they are defects.

  - **Process records cover the explicit path only.** The implicit path is
    evaluated with `ForwardDiff.Dual` numbers when an AD Jacobian is used, and
    only `p.precomputed` and `p.scratch` are dual-converted, so a record written
    from there would put a `Dual` into a plain-float cache field. `microphysics`
    for water and `precipitation` for energy therefore stay zero when stepped
    implicitly, which is the default for microphysics. Lifting this is the
    smaller of the two follow-ups.
  - **Process records cover bracketed processes only.** Transport, phase
    changes, gravity-wave drag and the numerical repairs have no
    snapshot/attribute bracket and are absent from the record entirely. A run's
    records consequently do not sum to the change in the parent variable. The
    review plan's model-step table wants full coverage; that is a larger piece
    of work and would change what a record means.
  - **Energy source tags see the explicit path only.** `precipitation` reaches
    an `ρe_tag_*` tag on the implicit path but never reaches an `ρe_src_*` tag.
    The two families therefore do not see the same set of processes, which
    matters when comparing them.

## Decisions waiting on evidence

### Whether energy source tracing is usable at all

Moist total energy has no physical zero. A shift of the thermodynamic or
gravitational reference changes every source tag's share and can drive the
parent non-positive, where the donor fraction is undefined and
`energy_source_fraction` falls back to zero. Water does not have this problem,
which is what makes its version well posed.

Whether the shares stay stable and interpretable under a realistic configuration
is the open question. It decides between energy source tags and the fallback of
water source tags plus an energy process record.

The evidence is a configuration that runs energy source tags, the energy process
record and the existing signed tags together on the dry baroclinic wave, with
post-processing that puts the three side by side. That work has not been
started.

## Infrastructure

### The CLA check fails on every pull request in this fork

`cla / checker` fails after about three seconds with `CLA_EFFECTIVE_DATE is
required but was not set`. The job log shows `CLA_API_URL`, `CLA_API_TOKEN`,
`CLA_ORG_TOKEN` and `CLA_EFFECTIVE_DATE` all empty. It fails before reading any
file, so it is independent of what a PR changes, and re-running it cannot help.

Closing it needs a repository administrator to set those secrets, or to drop the
workflow in this fork. Until then the check is red on every branch and should
not be read as a signal about the code.
