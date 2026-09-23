# Instruction for PR #95: one blend factor for the partition, one per source tag

For the session that owns PR #95 (`claude/energy-source-tag-updraft`, worktree
`../ClimaAtmosResiDyn-upd`). Written on 2026-09-23 by the G3 session, against
#95's head `dbe7435c`. The owner decided change A on 2026-09-23. Change B is
recommended, and it sits in the same lines. Both must land before #95 merges,
because the G3 plan builds the water tags on this code.

## Why

`ShareDifferences` in `energy_source_tags.jl` (about lines 1990-2040 at
`dbe7435c`) computes one blend factor `θ` per cell, over **every** tag. Two
consequences follow.

 1. **Source tags throttle the partition.** A source tag (an overlay: a tag
    with sources, not one of the region tags that partition the domain) often
    holds a tiny share of a cell's energy. If the plume carries a little more of
    it than the cell's bound allows, `θ` drops for all tags. In a scalar check,
    an overlay holding 1e-6 of the cell's energy cut the region tags' mixing
    there from `θ = 1` to `θ = 0.091`. So the region tags' mixing then depends on
    which overlays are configured. That contradicts the docstring's "A source
    tag's exchange stands alone, as its other fluxes do". It bites at fronts,
    where the updraft brings a tag into air that holds little of it, such as
    `sfc` near the inversion. D4 carries four overlays (`rad`, `sfc`, `sub`,
    `mp`), so the effect is in the D4 numbers.
 2. **The environment can go slightly negative.** The bound uses the room
    `ρĀ − ρaʲAʲ`. The environment's shares stay non-negative only if the room is
    also at most `ρa⁰A⁰`. The two agree only when the subdomains' energies add
    up to the cell's, which they do not quite (`K`, `p/ρ`, the diagnosed
    environment). With `A⁰` 1% low, the scalar check gives an environment share
    of −1.0e-4. So the commit message's "non-negative without clipping" holds
    only when the energies add up.

## Change A (decided): the partition shares one factor, and each source tag has its own

 - The partition's tags (`partition[i]` true, from `_energy_partition_flags`)
   share one factor, `θ_P`: the smallest admissible factor over the partition
   tags only. Their shares then still sum to one, and their exchange still sums
   to zero at every face.
 - Each source tag (`partition[i]` false) gets its own factor `θᵢ` from its own
   bound. Its exchange stands alone, as documented, so this does not touch the
   zero sum.

## Change B (recommended): the room is the smaller of the two bounds

`room = min(ρĀ − ρaʲAʲ, ρa⁰A⁰) / (ρaʲAʲ)`. This keeps both properties: no
updraft holds more of a tag than the cell, and no environment share goes
negative. Where the energies add up, it is today's room.

## The code

Replace the call operator of `ShareDifferences` with the following, keeping the
struct, its constructor and the `no_exchange` guard as they are. The per-tag
scale keeps `dbe7435c`'s order of operations,
`-θ * (ρaʲ * Aʲ) / (ρa⁰ * A⁰)`. So wherever a tag's factor is unchanged, its
result is bit for bit today's.

```julia
@inline function (::ShareDifferences{partition, environment})(
    εʲ,
    ε̄,
    ρ,
    ρaʲ,
    ρa⁰,
    Aʲ,
    A⁰,
    Ā,
) where {partition, environment}
    FT = typeof(ρ)
    N = length(partition)
    total = _partition_total(ε̄, partition)
    totalʲ = _partition_total(εʲ, partition)
    no_exchange = ... # unchanged
    no_exchange && return ntuple(_ -> zero(FT), Val(N))
    # How far a tag's share in the updraft may exceed its share in the grid
    # mean, per unit of that share. The updraft may hold at most the cell's own
    # energy of a tag, `ρaʲ φʲᵢ Aʲ ≤ ρ φ̄ᵢ Ā`, and the environment may not be left
    # with a negative share, which needs `ρa⁰ A⁰` in place of `ρĀ - ρaʲAʲ`. The
    # two agree when the subdomains' energies add up to the cell's. Where they
    # do not, the smaller one binds.
    room = min(ρ * Ā - ρaʲ * Aʲ, ρa⁰ * A⁰) / (ρaʲ * Aʲ)
    # The partition shares one factor, so its shares keep summing to one and its
    # exchange sums to zero. A source tag's exchange stands alone, so each
    # source tag has its own factor, and a scarce one cannot slow the
    # partition's mixing.
    θ = _partition_blend_factor(ε̄, εʲ, total, totalʲ, room, partition)
    return ntuple(Val(N)) do i
        θᵢ = partition[i] ? θ : _blend_factor(ε̄, εʲ, total, totalʲ, room, i)
        # The environment makes room for what the updraft takes, in proportion
        # to the energy each carries, so its difference is the updraft's,
        # reversed and scaled.
        scale = environment ? -θᵢ * (ρaʲ * Aʲ) / (ρa⁰ * A⁰) : θᵢ
        scale *
        (_subdomain_share(εʲ, totalʲ, i) - _subdomain_share(ε̄, total, i))
    end
end

# The partition's common factor: the smallest over its tags. A helper, so that
# `θ` is bound once. A variable reassigned in a loop and captured by the
# `ntuple` closure is boxed, and the kernel then allocates.
@inline function _partition_blend_factor(ε̄, εʲ, total, totalʲ, room, partition)
    θ = one(room)
    for i in 1:length(partition)
        θ = partition[i] ?
            min(θ, _blend_factor(ε̄, εʲ, total, totalʲ, room, i)) : θ
    end
    return θ
end

# The largest factor in `[0, 1]` by which tag `i`'s share in the updraft may
# move from its share in the grid mean, so that the tag stays inside `room`.
@inline function _blend_factor(ε̄, εʲ, total, totalʲ, room, i)
    mean_share = _subdomain_share(ε̄, total, i)
    difference = _subdomain_share(εʲ, totalʲ, i) - mean_share
    limit = mean_share * room
    FT = typeof(limit)
    return difference > limit ?
           min(one(FT), max(limit, zero(FT)) / difference) : one(FT)
end
```

`partition` is a type parameter, so `partition[i]` is a compile-time constant
and the loops unroll as before. Keep indexing the tuples, not `map`, for the
reason the existing comment gives.

**Checked on 2026-09-23 in a standalone Julia 1.11 script** holding this code
and `dbe7435c`'s, in Float32 and Float64:
 - it allocates exactly what `dbe7435c`'s allocates in the same harness;
 - in a cell where no bound binds, its result is equal (`==`) to `dbe7435c`'s;
 - tests 1 to 5 below hold with the values given.

A first version that kept `θ` in the operator and updated it in the loop
allocated 352 bytes, because of the boxing described in the helper's comment.

## Tests

Add them to the existing `ShareDifferences` testset in
`test/energy_source_tags_tests.jl`, in Float32 and Float64. The values come from
the scalar check, with `ρ = 1`, `ρaʲ = 0.1`, `ρa⁰ = 0.9` and `Aʲ = A⁰ = Ā = 1`
unless stated. Shares here are the fractions the specific values give after
normalising over the partition.

 1. **A scarce source tag leaves the partition alone.** Partition mean
    `(0.2, 0.8)` and plume `(0.3, 0.7)`, with and without a source tag of mean
    `1e-6` and plume `1e-4`. The partition's differences must be equal (`==`) in
    both cases, with `θ_P = 1` (updraft shares `(0.3, 0.7)`). The source tag's
    own factor is `1/11 ≈ 0.0909`, and its bound holds:
    `ρaʲ φʲ Aʲ ≤ ρ φ̄ Ā + eps`.
 2. **The review's counterexample still holds.** Mean `(0.01, 0.99)`, plume
    `(0.93842, 0.06158)`: `θ_P ≈ 0.0969`, updraft shares `(0.1, 0.9)`, the
    share-weighted inventory `ρaʲAʲφʲᵢ + ρa⁰A⁰φ⁰ᵢ = (0.01, 0.99)`, and the
    environment's shares ≥ 0.
 3. **The energies do not add up.** As test 2 with `A⁰ = 0.99`: the environment's
    smallest share is ≥ −4 eps (today −1.0e-4), with `θ_P ≈ 0.0960`. The script
    measured −9.3e-10 in Float32 and −1.7e-18 in Float64: the share sits
    exactly at its bound, up to rounding. The inventory is within 1% of the
    cell's, which is the mismatch itself, and is documented.
 4. **Zero sum.** In every case above, the partition's updraft differences and
    environment differences each sum to zero within a few `eps`.
 5. **Unchanged where nothing binds.** For a cell where no tag's bound binds,
    the result equals `dbe7435c`'s (`==`). Compare against
    `θ = 1, scale = -(ρaʲ * Aʲ) / (ρa⁰ * A⁰)` directly.
 6. The existing allocation check of the exchange (at most 8 bytes) still
    passes.

## Documentation

 - The docstring of `sgs_exchange_of_energy_source_tags!`, paragraph "No
   subdomain may carry more …": say that the partition's tags share one
   factor, each source tag has its own, and the room is the smaller of the two
   bounds. The environment's shares are then non-negative by construction.
   Where the subdomains' energies do not add up to the cell's, the
   share-weighted inventory is off by that mismatch.
 - `docs/src/energy_source_tags.md`, section "The updraft's mixing of
   provenance": the same, in two sentences.
 - NEWS, if #95's entry describes the bound.

## Validation

 1. The groups that run `energy_source_tags_tests.jl`, plus
    `tagging_source_edmf`, `tagging_source_increment` and
    `tagging_source_updraft`. The model's fields are untouched, since this is
    tag code only. The integration tests' parity checks confirm it.
 2. D4: `v3_upd_default` again at the new head. Compare it with
    `v3_upd_copies/output_0000` using the verifier on branch
    `claude/g3-programme`:

    ```
    python /dss/dsshome1/0D/di38kez/git/Clima/ClimaAtmosResiDyn-exp/experiments/tag_closure/analysis/evidence/compare_runs.py \
        --reference <scratch>/tag_closure/output/v3_upd_copies/output_0000 \
        --run <scratch>/tag_closure/output/v3_upd_default/output_<new> \
        --hours 1,6,12,24
    ```

    Use explicit output directories, never `output_active`. Report G1's
    criterion 4b (24 h: L1 ≤ 2%, L∞ ≤ 5% for every tag), and the 1 h numbers
    beside those of the `dbe7435c` run. The copies runs do not change: in copies
    mode neither the donor flux nor the exchange runs.
 3. The default runs of the R2 ladder are superseded by this change and need
    running again at the new head. Their copies runs stay valid.
 4. A FINDINGS entry with the before and after numbers.

## Not part of this change

The plume, copies mode, the switch's default, the offset and all model code
stay as they are.

## Report back

Report the new head SHA, the test results, the D4 numbers, and the CI run, so
that the G3 plan's assumption ("#95 merged with the partition-only factor") can
be checked against the merged code.

A possible commit message: "Bound the exchange's partition by one factor and
each source tag by its own".
