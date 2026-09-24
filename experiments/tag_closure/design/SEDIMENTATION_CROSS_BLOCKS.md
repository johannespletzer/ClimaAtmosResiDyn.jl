# The tags' sedimentation cross blocks: the design note of WP5b

Written on 2026-09-24. The owner chose this fix on 2026-09-24 over routing the
column's total through the bottom face. It is for the explicit-1M lag that
W23 measured and that the owner's review of #102 (point 3) asked to settle.
`file:line` references are to `claude/water-tags-edmf-wp5` at `e29384ee`.

## 1. The lag

With 1M microphysics, `ρq_tot`'s implicit sedimentation has a cross block to
each falling species `ρqₚ` (`update_sedimentation_jacobian!`,
`manual_sparse_jacobian.jl:1234-1237`). Each tag falls with its share of the
same flux (`sediment_water_tags!`, `tagged_water.jl:560-620`). The tag's
Jacobian row holds only its own diagonal (`update_water_tag_sedimentation_block!`,
`manual_sparse_jacobian.jl:1304-1330`).

So one Newton iteration moves `ρq_tot` with the updated species `Δρqₚ`, and
the tags with the old ones. The difference includes the surface outflow, so it
changes the column's total. The follower cannot move that part (W23, W24).

On W23's column with microphysics stepped explicitly, this was 0.8% of the
water an hour. With implicit microphysics the same terms exist, and W24 left
2.6e-5 out in a day.

## 2. The blocks

A tag's tendency is `-precipdivᵥ(ᶠρ ᶠtop_bias(-wₚ qₚ φ̂ᵢ))`, summed over the
species, where `φ̂ᵢ` is the tag's share of the falling species:
- for a partition tag, `water_tag_sediment_share`, the partition-normalized
  share;
- for a source tag, `water_tag_source_sediment_share`.

Its derivative with respect to `ρqₚ`, at fixed `φ̂ᵢ`, is `φ̂ᵢ` times the
parent's cross block:

    ∂(ρq_tagᵢ)ₜ/∂ρqₚ = B · ᶠtop_bias · Diag(WVector(-wₚ φ̂ᵢ / ρ)),

with `B = p.scratch.ᶜbidiagonal_adjoint_matrix_c3`, which the parent's block
also uses. Over a closed partition the shares sum to one, so the partition's
cross blocks sum to the parent's.

The share's own dependence on `ρq_tot` and `ρ` stays out, as now. The
diagonal (`∂φ̂/∂ρq_tag`) stays as it is. Copies (updraft) are a second step
(section 5).

## 3. The solve: back-substitution, the parent untouched

A tag with these blocks is no longer uncoupled in today's sense
(`uncoupled_jacobian_names`, `manual_sparse_jacobian.jl:735-751`: "its only
block is its own diagonal"). But the coupling is one way:
- the tag's row names species columns;
- no row other than its own names the tag's column.

The split solver keeps such a field apart. It solves the coupled fields first,
exactly as now. Then, for each uncoupled field, it forms `R_tag − Σₚ C_tag,ₚ
ΔYₚ` in one scratch field and solves the tag's own block on it.

The coupled system's rows, name tree and solver are unchanged, so the parent's
`ΔY` is the same computation, bit for bit (`split_jacobian_solver`,
`manual_sparse_jacobian.jl:790-850`).

Without the split (`split_uncoupled_fields = false`, `AutoSparseJacobian`),
the nested arrowhead solve sees the new blocks only in the tags' rows. The
tags' columns enter no other row, so the parent's rows and their iterates are
unchanged there too. The tags' result can differ from the split's where the
nested solve is iterative. The split then no longer reproduces the unsplit
solve for these tags, and its docstring says so.

## 4. Tests

- **Unit: the split's back-substitution.** On a small column with a
  sedimenting species and a tag with a cross block, the split solve equals
  the exact block-lower-triangular solution to rounding. The coupled fields'
  `ΔY` is bit for bit that of the solve without the tag's cross block.
- **Unit: the field lists.** A field whose only other blocks are in its own
  row stays uncoupled. A field named as a column by another row does not.
- **Unit: the blocks.** On a column, the partition tags' cross blocks sum to
  the parent's.
- **Integration.** Under 1M and a tag, the parent is bit for bit the same with
  the cross blocks and without, on both the implicit and the explicit path.
  With the follower and one Newton iteration, W23's explicit column closes
  within the budget.

## 5. The experiment, and what follows

The owner's review's distinguishing experiment, on W23's column (DYCOMS 1M
EDMF, microphysics explicit, one hour, one Newton iteration):
- default and copies;
- tracer and follower;
- cross blocks off (#102's head) and on.

It reports the net and gross closure, `q_tag_inc_left`, the per-tag agreement
with the copies, the smallest tag value, the partition repair, and the parent's
parity. Implicit 1M (D4-W, a day) checks that nothing else moved.

If the follower then closes the explicit path within the budget, #102's
refusal of `increment` there is lifted, and the default follows G3_PLAN 4.3.

**Copies.** The copies lag alike (W23: 7.8e-3). Their rows are in the coupled
system, since they are updraft fields. Their cross blocks to the updraft
species would enter the nested solve directly, and are the second step.
