import ClimaCore: Limiters

"""
    _should_apply_limiter_to_tracer(ρχ_name, species) -> Bool

Determine if a limiter should be applied to a specific tracer.

# Arguments

  - `ρχ_name::Symbol`: Tracer variable name (e.g., `:ρq_tot`)
  - `species`: Configuration — `nothing`: apply to all; `()`: apply to none;
    `Tuple{Symbol,...}`: apply only if `ρχ_name ∈ species`

Tagged tracers are always excluded, for a different reason per family. Tagged
energies (`ρe_tag_*`) can be legitimately negative (e.g. accumulated cooling),
so nonnegativity limiting would silently corrupt them. Tagged waters
(`ρq_tag_*`) are non-negative but must not be limited independently of each
other: a per-tag shape-preserving adjustment has no reason to sum to the
parent's, so it would break `Σᵢ ρq_tag_i = ρq_tot`. They instead follow the
parent's correction through [`rescale_water_tags!`](@ref).

# Returns

`true` if the limiter should be applied, `false` otherwise.
"""
function _should_apply_limiter_to_tracer(ρχ_name, species)
    if is_tagged_tracer_name(ρχ_name)
        return false
    elseif isnothing(species)
        return true  # Apply to all tracers
    elseif species isa Tuple
        return ρχ_name in species
    else
        error("Invalid species configuration type: $(typeof(species))")
    end
end

"""
    limiters_func!(Y, p, t, ref_Y)

Apply tracer limiters to the prognostic state `Y` in place.

Supports two limiter types configured via `p.numerics`:

For the VerticalMassBorrowingLimiter, if `p.numerics.vertical_water_borrowing_limiter`
is configured, it uses that limiter with `p.numerics.vertical_water_borrowing_species` for species selection.
The limiter enforces strict nonnegativity using a single threshold value (0.0) that applies uniformly
to all tracers for which the limiter is used. The limiter instance is created as
`Limiters.VerticalMassBorrowingLimiter((0.0,))` in the cache. The species configuration is used to
filter which tracers the limiter is applied to before calling `apply_limiter!` (since `apply_limiter!`
doesn't support a species keyword argument). If species is `nothing` (default), the limiter is applied
to all tracers. Otherwise, only tracers matching the specified tuple of names will have the limiter
applied.

When the limiter is applied to total water (ρq_tot), the effective tendency Δ(ρq_tot) is
deduced from the pre- and post-limited states. To keep mass and energy consistent
(https://clima.github.io/ClimaAtmos.jl/dev/microphysics/), density
and total energy are updated.

 1. **SEM Quasimonotone Limiter** (`sem_quasimonotone_limiter`):
    Computes bounds from `ref_Y` and applies spectral element limiting.

 2. **Vertical Mass Borrowing Limiter** (`vertical_water_borrowing_limiter`):
    Enforces strict nonnegativity by borrowing mass vertically.
    Species filtering via `vertical_water_borrowing_species`.

# Arguments

  - `Y`: Current state vector (modified in place)
  - `p`: Cache containing `p.numerics` limiter configuration
  - `t`: Current simulation time
  - `ref_Y`: Reference state for bounds computation
"""
NVTX.@annotate function limiters_func!(Y, p, t, ref_Y)
    (;
        sem_quasimonotone_limiter,
        vertical_water_borrowing_limiter,
        vertical_water_borrowing_species,
    ) =
        p.numerics

    # Apply general (SEM quasimonotone) limiter if configured.
    # When ρq_tot is limited, update ρ and ρe_tot for mass and energy consistency.
    if !isnothing(sem_quasimonotone_limiter)
        if hasproperty(Y.c, :ρq_tot)
            p.scratch.ᶜtemp_scalar_2 .= Y.c.ρq_tot
        end
        for ρχ_name in filter(is_tracer_var, propertynames(Y.c))
            # Tagged energy tracers are left unlimited so that they receive
            # the same treatment as ρe_tot, which is not limited either. A
            # shape-preserving adjustment applied to the tags but not to
            # ρe_tot would show up as tagging closure error.
            #
            # Tagged water tracers are skipped for the opposite reason: ρq_tot
            # *is* limited, but limiting each tag independently has no reason to
            # reproduce the parent's adjustment, so it would break
            # Σᵢ ρq_tag_i = ρq_tot. They follow the parent through
            # `rescale_water_tags!` below instead.
            is_tagged_tracer_name(ρχ_name) && continue
            Limiters.compute_bounds!(
                sem_quasimonotone_limiter,
                ref_Y.c.:($ρχ_name),
                ref_Y.c.ρ,
            )
            Limiters.apply_limiter!(Y.c.:($ρχ_name), Y.c.ρ, sem_quasimonotone_limiter)
        end
        if hasproperty(Y.c, :ρq_tot)
            # `ᶜtemp_scalar_2` still holds the pre-limiter ρq_tot here
            rescale_water_tags!(Y, p, p.scratch.ᶜtemp_scalar_2)
            @. p.scratch.ᶜtemp_scalar_2 = Y.c.ρq_tot - p.scratch.ᶜtemp_scalar_2
            enforce_mass_energy_consistency!(Y, p, p.scratch.ᶜtemp_scalar_2)
        end
    end

    # Apply vertical water borrowing limiter if configured
    # Our state stores ρχ (tracer density). Store χ in scratch, apply limiter, then write ρχ back.
    # When ρq_tot is limited, update ρ and ρe_tot for mass and energy consistency.
    if !isnothing(vertical_water_borrowing_limiter)
        # `vertical_water_borrowing_species` holds `Symbol`s (see
        # `vertical_water_borrowing_species_from_config`), and the per-tracer
        # loop below tests `Symbol`s too, so this guard must use one as well: a
        # `@name(ρq_tot)` never compares equal to `:ρq_tot`, which silently
        # skipped the snapshot, `rescale_water_tags!` and the mass/energy
        # consistency update whenever the species list was set explicitly.
        if _should_apply_limiter_to_tracer(
            :ρq_tot,
            vertical_water_borrowing_species,
        ) &&
           hasproperty(Y.c, :ρq_tot)
            p.scratch.ᶜtemp_scalar_2 .= Y.c.ρq_tot
        end
        ᶜχ = p.scratch.ᶜtemp_scalar
        for ρχ_name in filter(is_tracer_var, propertynames(Y.c))
            if _should_apply_limiter_to_tracer(ρχ_name, vertical_water_borrowing_species)
                ρχ = getproperty(Y.c, ρχ_name)
                ᶜχ .= specific.(ρχ, Y.c.ρ)
                Limiters.apply_limiter!(ᶜχ, Y.c.ρ, vertical_water_borrowing_limiter)
                ρχ .= ᶜχ .* Y.c.ρ
            end
        end
        # Must match the `Symbol` test used to open this bracket above.
        if _should_apply_limiter_to_tracer(
            :ρq_tot,
            vertical_water_borrowing_species,
        ) &&
           hasproperty(Y.c, :ρq_tot)
            # `ᶜtemp_scalar_2` still holds the pre-limiter ρq_tot here
            rescale_water_tags!(Y, p, p.scratch.ᶜtemp_scalar_2)
            @. p.scratch.ᶜtemp_scalar_2 = Y.c.ρq_tot - p.scratch.ᶜtemp_scalar_2
            enforce_mass_energy_consistency!(Y, p, p.scratch.ᶜtemp_scalar_2)
        end
    end
    return nothing
end
