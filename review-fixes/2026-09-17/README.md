# CI pipeline review of 2026-09-17

[`ci_pipeline_review.md`](ci_pipeline_review.md) is the review. Start at section 1 for
the findings, section 9 for the ranked list, section 11 for the questions that need an
answer before anything is applied, and section 12 for the handover brief.

Nothing in the workflows or the tests was changed. This directory is a record, like
[`../2026-09-16`](../2026-09-16), and the branch it sits on runs no CI, because every
workflow triggers on pull requests, on pushes to `main` and tags, and on the merge queue.

## The measurement

Both runs are for the merge of #80: `ci` run 35121778373 and `Downgrade` run
35121778370.

- `ci_job_timings.tsv`: one row per job, 54 rows. Job minutes, the seconds and dependency
  count of the precompile inside `Pkg.test`, the test wall time, the cache outcome and
  the bytes it saved, and the Codecov token length with whether the upload failed.
- `ci_file_timings.tsv`: one row per test file per job variant, 296 rows. Seconds from
  the file's `@time include` line and its compilation share. Appendix A of the review is
  this table in wide form.
- `parse_logs.py`: the parser that produced both. It reads the job lists and job logs as
  they come back from the GitHub Actions API, so re-running it needs those responses
  saved next to it. It writes JSON, which this repository gitignores, hence the TSV.
  Appendix B of the review gives the endpoints and the log lines each number comes from.

Julia was not available where this was written, so nothing here was executed. The two
claims that need a CI run rather than a reading are marked as such in the review: the
size of the cache saving and the size of the coverage saving. Both are read off the
first `main` run after the change.

## For the agent with Julia

Section 12 of the review is written for you. In short:

- Phase A needs no Julia. It changes `.github/workflows/ci.yml`, `downgrade.yml`,
  `downstream.yml` and `test/runtests.jl`, and section 10 has the design notes for the
  cache fix, including the two traps that make the obvious version of it a no-op.
- Phase C is yours: fewer distinct model types in the heaviest fork-owned test files, one
  file per pull request, each timed locally with `TEST_GROUP=<group>` before and after.
- Re-time `test/energy_source_tags_integration.jl` first. It grew from three model types
  to five when #72 merged, after the measurement in this review, so its 17.3 min is
  already stale.
