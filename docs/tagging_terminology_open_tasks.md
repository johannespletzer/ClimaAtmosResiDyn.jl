# Open tasks in the tracer tagging work

This is a checklist, not a decision record. It collects the loose ends left by
the tagging pull requests so they are not rediscovered one at a time in review.
Each entry says what is wrong or missing, where, and what would close it. Delete
an entry when it is done.

The decisions themselves belong in the pull requests that make them. Nothing
here is a commitment to a particular answer.

## Limits that are documented but not lifted

These are stated in the docs and in the diagnostic `comments`, so nothing is
hidden. They are listed here because they are the natural next pieces of work,
not because they are defects.

  - **Process records cover the explicit path only.** Only the explicit path
    has a snapshot/attribute bracket. `snapshot_tags!` and `attribute_tags!`
    are called from `remaining_tendency.jl` and nowhere else. `microphysics`
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

`cla / checker` fails after about three seconds with `CLA_EFFECTIVE_DATE is required but was not set`. The job log shows `CLA_API_URL`, `CLA_API_TOKEN`,
`CLA_ORG_TOKEN` and `CLA_EFFECTIVE_DATE` all empty. It fails before reading any
file, so it is independent of what a PR changes, and re-running it cannot help.

Closing it needs a repository administrator to set those secrets, or to drop the
workflow in this fork. Until then the check is red on every branch and should
not be read as a signal about the code.
