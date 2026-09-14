# Draft: a ClimaCore issue on the compile time of field-name sets

A local draft for decision 3 of `OPERATIONAL_TODO.md`, written on 2026-09-14.
**Not filed.** Filing it is outward-facing, and the owner decides. The text
below the line is what would go to `CliMA/ClimaCore.jl`. The numbers come from
FINDINGS E44d and E44e, and from the reproducer at the end.

---

## `FieldMatrixWithSolver` compile time grows about as the fourth power of the number of fields

### Summary

Building a `FieldMatrixWithSolver` spends almost all of its time in inference,
on `FieldNameSet` operations. The inner constructor of `FieldNameSet` checks
every value against every other value for duplicates and overlaps
(`field_name_set.jl:39-58`). Those checks run at compile time, through
UnrolledUtilities. A `FieldMatrixKeys` over `n` fields holds up to `n²` name
pairs, so building one costs of order `n⁴` checks. `partition_blocks`
(`field_matrix_solver.jl:108-118`) builds four such sets per level of a nested
solver, with `cartesian_product` and `set_complement`.

In ClimaAtmos this makes the build time grow much faster than the number of
prognostic tracers. A model with many tracers that only have a diagonal
Jacobian block pays for them at every level of the nested solver.

### What we measured

ClimaCore 0.16.0, UnrolledUtilities 0.1.10, Julia 1.11.9, CPU.

**In ClimaAtmos** (a ClimaAtmos fork, a single column; E44d). Energy tracers
with only a diagonal block were added to the state. Julia's inference timer,
`Core.Compiler.Timings`, split `get_simulation` into inference and the rest:

| column | tracers | `get_simulation`, s | in inference, s | outside it, s |
|:-- | --:| --:| --:| --:|
| EDMF | 0 | 731.4 | 568.7 | 158.0 |
| EDMF | 2 | 955.4 | 791.5 | 162.1 |
| EDMF | 8 | 2,639.6 | 2,457.3 | 177.5 |
| 0-moment | 0 | 120.5 | 62.0 | 58.3 |
| 0-moment | 8 | 217.6 | 149.1 | 68.1 |

  - The 40 methods whose inference time grows most make all of the growth.
    All are in UnrolledUtilities and in `MatrixFields`' name sets. On the EDMF
    column, `==` on tuples of `FieldName`s grows from 88,597 specializations to
    412,854.
  - Built on its own on the 0-moment column, `FieldMatrixWithSolver` takes
    14.1 s with 13 blocks and 89.2 s with 21. Of the 88 s, 86 are in
    `field_matrix_solver_cache`, and half of that is `partition_blocks` at the
    top level.
  - With 8 tracers and 5 more diagonal-only fields, the EDMF column did not
    finish building in two hours.

**Reproducer, ClimaCore only** (below). A column with `ρ`, `ρe`, a face `w`
coupled to both, and `n` extra center scalars with only a diagonal block, solved
with `ApproximateBlockArrowheadIterativeSolve(@name(c.ρ), @name(c.ρe))`. First
call of `FieldMatrixWithSolver`, in a fresh process:

| extra scalars | fields | blocks | `FieldMatrixWithSolver`, s |
|:-- | --:| --:| --:|
| 0 | 3 | 7 | 3.1 |
| 4 | 7 | 11 | 10.4 |
| 8 | 11 | 15 | 28.1 |
| 12 | 15 | 19 | 67.3 |
| 16 | 19 | 23 | 170.3 |

A second build of the same solver takes under 1 ms. From 15 fields to 19 the
time grows 2.53 times, and `(19/15)⁴` is 2.57. The runs shared a login node with
other work, and an earlier run gave the same times to within 4%.

### Why moving the fields into their own group does not help

We tried to keep the extra fields out of the expensive part by solving them
first, in a `BlockLowerTriangularSolve` of their own. It took 95.2 s against
89.2 s. `set_complement` (`field_name_set.jl:132`) takes the complement from
the `FieldNameTree` of the whole state, so every level of the nested solver
still carries every field.

What worked, in ClimaAtmos: solve the diagonal-only fields outside
`FieldMatrixSolver`, one field at a time, and build the nested solver against a
`FieldNameTree` of the other fields only (`replace_name_tree`). The build of the
0-moment column's solver went from 89.2 s to 13.6 s, and the EDMF column with 8
tracers and 5 records builds in 21 minutes against more than two hours. The
increments are bit for bit the same. But it reaches into internals:
`FieldNameTree`, `FieldVectorKeys`, `replace_name_tree`,
`field_matrix_solver_cache`, `check_field_matrix_solver` and
`run_field_matrix_solver!`.

### Suggestions

In order of how little they change:

 1. **Skip the checks where the result is valid by construction.**
    `cartesian_product` of two valid `FieldVectorKeys` has no duplicates and no
    overlaps, if its inputs have none. Neither does a `setdiff` or a
    `replace_name_tree` of a valid set. An unchecked inner constructor for
    these internal paths would remove the `n⁴` term where it is paid most.
 2. **Check fewer pairs.** For a `FieldVectorKeys`, overlap means one name is a
    prefix of the other. In a sorted order, a name and the names it overlaps
    are neighbours, so comparing neighbours finds duplicates and overlaps. We
    have not worked out the same for name pairs, or whether a sort can be done
    at compile time as cheaply.
 3. **Let a solver algorithm name fields to solve on their own.** For example a
    `BlockDiagonalSolve` over fields that couple to nothing, handled before the
    nested solver and left out of its name tree. This is what ClimaAtmos does
    by hand now.

We are happy to test a change against the ClimaAtmos columns above.

### Reproducer

    julia --project=<an environment with ClimaCore> climacore_nameset_repro.jl <n>

(The script is `analysis/climacore_nameset_repro.jl` in the experiment branch.
Paste it inline when filing.)

---

## Notes for the owner

  - **Line numbers** are for ClimaCore 0.16.0 in the terrabyte depot.
  - **"A ClimaAtmos fork"** is this repository. Name it, or not, as you prefer.
  - **Suggestion 1** is the smallest change and the most likely to be accepted.
    Whether it is enough is unmeasured: `partition_blocks` also indexes the
    matrix with those sets, which goes through `setdiff` and `union_values`.
  - **If ClimaCore fixes it,** #76's split solver could go, or use public API.
