###
### Stratospheric passive tracers
###
###
### A family of passive, chemically inert tracers whose only source is a
### constant production rate inside a (latitude band × height band) source
### region, and whose only sink is removal below the model tropopause. Once
### the burden of a tracer stops drifting, its source and sink balance and its
### lifetime follows from
###
###     τ = M / S
###
### with `M` the global burden (kg) and `S` the global source rate (kg s⁻¹).
### `M` and `S` are both reported by the tracer-budget callback, so `τ` never
### relies on the prescribed production rate being interpreted correctly.
###
### The source regions tile the model domain above the tropopause: latitude
### bands cover the whole sphere, height bands stack from the tropopause to
### the model top, and every grid point above the tropopause belongs to
### exactly one (latitude, height) region. Each region feeds one tracer, so a
### tracer's lifetime refers to one well-defined part of the stratosphere.
###

import ClimaComms
import ClimaCore: Fields, Spaces

"""
    TropopauseRelativeHeight()

Measure tracer source heights from the local tropopause, so that the source
regions follow the tropopause and tile the stratosphere everywhere. This is
the default: it keeps sources out of the removal region and gives the
lowermost stratosphere a source at every latitude.
"""
struct TropopauseRelativeHeight end

"""
    GeometricHeight()

Measure tracer source heights from sea level, giving source regions at fixed
altitudes. Regions that fall below the local tropopause are removed as fast as
they are produced, so their lifetimes approach `loss_timescale`.
"""
struct GeometricHeight end

# Diagnostics are registered once, at load time, for a fixed grid of source
# regions (see `stratospheric_tracer_diagnostics.jl`); a model with more bands
# than this would carry tracers with no way to output them.
const MAX_TRACER_LATITUDE_BANDS = 12
const MAX_TRACER_HEIGHT_BANDS = 12

"""
    StratosphericPassiveTracers{NY, NZ, FT, HC, TP} <: AbstractChemistryModel

`NY * NZ` passive tracers, one per (latitude band, height band) source region.

Region `(i, k)` is the set of points with latitude in
`(latitude_lower_edges[i], latitude_upper_edges[i]]` and height in
`(height_lower_edges[k], height_upper_edges[k]]`, where height is measured
from the local tropopause (`TropopauseRelativeHeight`) or from sea level
(`GeometricHeight`). The outermost edges are infinite, so the regions tile the
domain: every point above the tropopause belongs to exactly one region.

Tracer `(i, k)` is stored in `Y.c.ρq_gas_y<i>z<k>` (see
[`stratospheric_tracer_symbol`](@ref)) and is ordered with the latitude index
varying fastest.

# Fields

  - `latitude_lower_edges`, `latitude_upper_edges`: latitude band edges, in
    degrees.
  - `height_lower_edges`, `height_upper_edges`: height band edges, in m,
    relative to `height_coordinate`'s reference.
  - `production_rate`: production of tracer mass fraction inside the source
    region, in s⁻¹. Its value sets the magnitude of the tracer but not its
    lifetime, which is a ratio of two quantities that are both linear in it.
  - `loss_timescale`: e-folding time of the relaxation to zero below the
    tropopause, in s. Should be short compared with the lifetimes being
    measured, and long compared with the model timestep.
  - `height_coordinate`: [`TropopauseRelativeHeight`](@ref) or
    [`GeometricHeight`](@ref).
  - `tropopause`: [`TropopauseParameters`](@ref) of the WMO lapse-rate
    tropopause that bounds the tracers from below.
"""
struct StratosphericPassiveTracers{NY, NZ, FT, HC, TP} <: AbstractChemistryModel
    latitude_lower_edges::NTuple{NY, FT}
    latitude_upper_edges::NTuple{NY, FT}
    height_lower_edges::NTuple{NZ, FT}
    height_upper_edges::NTuple{NZ, FT}
    production_rate::FT
    loss_timescale::FT
    height_coordinate::HC
    tropopause::TP
end

"""
    StratosphericPassiveTracers(FT; kwargs...)

Build a [`StratosphericPassiveTracers`](@ref) whose source regions tile the
domain above the tropopause.

# Keyword arguments

  - `n_latitude_bands = 6`: number of latitude bands, of equal width in
    latitude, covering the sphere from pole to pole.
  - `n_height_bands = 8`: number of height bands. The topmost band is
    open-ended, so the regions reach the model top whatever it is.
  - `band_depth = 5000`: thickness of each height band except the topmost, in
    m.
  - `lowest_band_base = 0`: height of the bottom of the lowest band above the
    reference, in m. The default puts the lowest source immediately above the
    tropopause.
  - `production_rate = 1e-10`: see [`StratosphericPassiveTracers`](@ref).
  - `loss_timescale = 21600` (6 hours): see
    [`StratosphericPassiveTracers`](@ref).
  - `height_coordinate = TropopauseRelativeHeight()`
  - `tropopause = TropopauseParameters{FT}()`
"""
function StratosphericPassiveTracers(
    ::Type{FT};
    n_latitude_bands::Int = 6,
    n_height_bands::Int = 8,
    band_depth = 5000,
    lowest_band_base = 0,
    production_rate = 1e-10,
    loss_timescale = 21600,
    height_coordinate = TropopauseRelativeHeight(),
    tropopause = TropopauseParameters{FT}(),
) where {FT}
    n_latitude_bands >= 1 ||
        error("n_latitude_bands must be at least 1, got $n_latitude_bands")
    n_height_bands >= 1 ||
        error("n_height_bands must be at least 1, got $n_height_bands")
    n_latitude_bands <= MAX_TRACER_LATITUDE_BANDS || error(
        "n_latitude_bands must be at most $MAX_TRACER_LATITUDE_BANDS \
        (diagnostics are registered up to that many bands), got $n_latitude_bands",
    )
    n_height_bands <= MAX_TRACER_HEIGHT_BANDS || error(
        "n_height_bands must be at most $MAX_TRACER_HEIGHT_BANDS \
        (diagnostics are registered up to that many bands), got $n_height_bands",
    )
    band_depth > 0 || error("band_depth must be positive, got $band_depth")
    loss_timescale > 0 ||
        error("loss_timescale must be positive, got $loss_timescale")

    # Infinite outer edges make the bands a partition of the sphere: no point
    # is left without a source region because of rounding at ±90 degrees.
    band_width = FT(180) / n_latitude_bands
    latitude_lower_edges = ntuple(n_latitude_bands) do i
        i == 1 ? FT(-Inf) : FT(-90) + (i - 1) * band_width
    end
    latitude_upper_edges = ntuple(n_latitude_bands) do i
        i == n_latitude_bands ? FT(Inf) : FT(-90) + i * band_width
    end

    # Likewise the topmost height band is open-ended, so the source regions
    # reach the model top.
    height_lower_edges = ntuple(n_height_bands) do k
        FT(lowest_band_base) + (k - 1) * FT(band_depth)
    end
    height_upper_edges = ntuple(n_height_bands) do k
        k == n_height_bands ? FT(Inf) :
        FT(lowest_band_base) + k * FT(band_depth)
    end

    return StratosphericPassiveTracers(
        latitude_lower_edges,
        latitude_upper_edges,
        height_lower_edges,
        height_upper_edges,
        FT(production_rate),
        FT(loss_timescale),
        height_coordinate,
        tropopause,
    )
end

"""
    n_latitude_bands(chemistry_model)
    n_height_bands(chemistry_model)
    n_tracers(chemistry_model)

Size of the source-region grid of a [`StratosphericPassiveTracers`](@ref).
"""
n_latitude_bands(::StratosphericPassiveTracers{NY}) where {NY} = NY
n_height_bands(::StratosphericPassiveTracers{NY, NZ}) where {NY, NZ} = NZ
n_tracers(::StratosphericPassiveTracers{NY, NZ}) where {NY, NZ} = NY * NZ

"""
    stratospheric_tracer_symbol(i, k)

Name of the density-weighted tracer fed by the source region in latitude band
`i` and height band `k`, e.g. `:ρq_gas_y01z03`. The corresponding specific
tracer, used for diagnostics, drops the leading `ρ`.
"""
stratospheric_tracer_symbol(i, k) =
    Symbol("ρq_gas_y", lpad(i, 2, '0'), "z", lpad(k, 2, '0'))

"""
    stratospheric_tracer_symbols(n_latitude, n_height)

All tracer names, with the latitude index varying fastest. Every iteration
over tracers — the prognostic state, the tendency, the budget — uses this
order.
"""
stratospheric_tracer_symbols(n_latitude, n_height) = Tuple(
    stratospheric_tracer_symbol(i, k) for k in 1:n_height for
    i in 1:n_latitude
)

stratospheric_tracer_symbols(chem::StratosphericPassiveTracers) =
    stratospheric_tracer_symbols(n_latitude_bands(chem), n_height_bands(chem))

"""
    stratospheric_tracer_fields(ᶜfields, chemistry_model)

Tuple of the tracer subfields of `ᶜfields` (either `Y.c` or `Yₜ.c`), in the
order given by [`stratospheric_tracer_symbols`](@ref).

The tuple is homogeneous — every entry is a scalar center `Field` — so it can
be indexed with a loop variable without losing type stability, which is what
lets the tendency loop over tracers at runtime instead of unrolling `NY * NZ`
broadcasts.
"""
@generated function stratospheric_tracer_fields(
    ᶜfields,
    ::StratosphericPassiveTracers{NY, NZ},
) where {NY, NZ}
    accessors = map(stratospheric_tracer_symbols(NY, NZ)) do name
        :(getproperty(ᶜfields, $(QuoteNode(name))))
    end
    return :(tuple($(accessors...)))
end

"""
    stratospheric_tracer_source(
        ρ, z, lat, source_reference,
        latitude_lower, latitude_upper, height_lower, height_upper,
        production_rate,
    )

Production of density-weighted tracer, in kg m⁻³ s⁻¹, at one point.

The source is proportional to air density, so it raises the tracer mass
fraction at the uniform rate `production_rate` throughout the source region
rather than piling mass into whichever part of the region happens to be
thickest. Bands are half-open (`lower < · <= upper`) so that neighbouring
bands neither overlap nor leave a gap, and so that the tropopause level
itself — height exactly zero — belongs to the removal region rather than to
the lowest source band.
"""
@inline function stratospheric_tracer_source(
    ρ,
    z,
    lat,
    source_reference,
    latitude_lower,
    latitude_upper,
    height_lower,
    height_upper,
    production_rate,
)
    height = z - source_reference
    in_source_region =
        (lat > latitude_lower) &
        (lat <= latitude_upper) &
        (height > height_lower) &
        (height <= height_upper)
    return ifelse(in_source_region, ρ * production_rate, zero(ρ))
end

"""
    stratospheric_tracer_loss(ρχ, z, z_tropopause, inverse_loss_timescale)

Removal of density-weighted tracer, in kg m⁻³ s⁻¹, at one point.

Everything at or below the tropopause relaxes to zero on `loss_timescale`,
which is the tracers' only sink and the boundary condition that makes their
lifetimes finite. Negative values, which the advection scheme can produce, are
clipped so that the sink cannot turn into a source and amplify them.
"""
@inline function stratospheric_tracer_loss(
    ρχ,
    z,
    z_tropopause,
    inverse_loss_timescale,
)
    return ifelse(
        z <= z_tropopause,
        max(ρχ, zero(ρχ)) * inverse_loss_timescale,
        zero(ρχ),
    )
end

"""
    set_source_reference_height!(ᶜreference, ᶜz_tropopause, height_coordinate)

Fill `ᶜreference` with the height that tracer source bands are measured from.
"""
set_source_reference_height!(
    ᶜreference,
    ᶜz_tropopause,
    ::TropopauseRelativeHeight,
) = (ᶜreference .= ᶜz_tropopause)

set_source_reference_height!(ᶜreference, ᶜz_tropopause, ::GeometricHeight) =
    (ᶜreference .= zero(eltype(ᶜreference)))

"""
    stratospheric_tracer_scratch(p)

The scratch fields used by both the tracer tendency and the tracer budget:
the tropopause scan workspace, the tropopause height, and the source
reference height.
"""
stratospheric_tracer_scratch(p) = (
    p.scratch.ᶜtemp_scalar,
    p.scratch.ᶜtemp_scalar_2,
    p.scratch.ᶜtemp_scalar_3,
)

"""
    chemistry_tendency!(Yₜ, Y, p, t, chemistry_model::StratosphericPassiveTracers)

Add the source and the sub-tropopause sink of every passive tracer to `Yₜ`.
"""
function chemistry_tendency!(
    Yₜ,
    Y,
    p,
    t,
    chemistry_model::StratosphericPassiveTracers,
)
    ᶜscan_scratch, ᶜz_tropopause, ᶜsource_reference =
        stratospheric_tracer_scratch(p)
    set_tropopause_height!(
        ᶜz_tropopause,
        ᶜscan_scratch,
        p.precomputed.ᶜT,
        chemistry_model.tropopause,
    )
    set_source_reference_height!(
        ᶜsource_reference,
        ᶜz_tropopause,
        chemistry_model.height_coordinate,
    )

    ᶜρ = Y.c.ρ
    space = axes(ᶜρ)
    ᶜz = Fields.coordinate_field(space).z
    ᶜlat = latitude_field(space)

    tracers = stratospheric_tracer_fields(Y.c, chemistry_model)
    tendencies = stratospheric_tracer_fields(Yₜ.c, chemistry_model)

    (; production_rate) = chemistry_model
    inverse_loss_timescale = inv(chemistry_model.loss_timescale)

    tracer_index = 0
    @inbounds for k in 1:n_height_bands(chemistry_model),
        i in 1:n_latitude_bands(chemistry_model)

        tracer_index += 1
        latitude_lower = chemistry_model.latitude_lower_edges[i]
        latitude_upper = chemistry_model.latitude_upper_edges[i]
        height_lower = chemistry_model.height_lower_edges[k]
        height_upper = chemistry_model.height_upper_edges[k]
        ᶜρχ = tracers[tracer_index]
        ᶜρχₜ = tendencies[tracer_index]

        @. ᶜρχₜ +=
            stratospheric_tracer_source(
                ᶜρ,
                ᶜz,
                ᶜlat,
                ᶜsource_reference,
                latitude_lower,
                latitude_upper,
                height_lower,
                height_upper,
                production_rate,
            ) - stratospheric_tracer_loss(
                ᶜρχ,
                ᶜz,
                ᶜz_tropopause,
                inverse_loss_timescale,
            )
    end
    return nothing
end

"""
    stratospheric_tracer_budget(Y, p, chemistry_model)

Global burden, source rate and loss rate of every passive tracer, as three
vectors ordered by [`stratospheric_tracer_symbols`](@ref).

The burden is in kg, the rates in kg s⁻¹, and each is a volume integral over
the whole domain, so the lifetime of a tracer in equilibrium is
`burden / source`. Reporting the *diagnosed* source, rather than the
prescribed production rate, keeps the lifetime correct even where a source
region is clipped by the model top or by the tropopause.

Every entry involves a global reduction, so this is meant to be called from a
callback at output frequency, not from the tendency.
"""
function stratospheric_tracer_budget(
    Y,
    p,
    chemistry_model::StratosphericPassiveTracers,
)
    ᶜscan_scratch, ᶜz_tropopause, ᶜsource_reference =
        stratospheric_tracer_scratch(p)
    set_tropopause_height!(
        ᶜz_tropopause,
        ᶜscan_scratch,
        p.precomputed.ᶜT,
        chemistry_model.tropopause,
    )
    set_source_reference_height!(
        ᶜsource_reference,
        ᶜz_tropopause,
        chemistry_model.height_coordinate,
    )

    ᶜρ = Y.c.ρ
    space = axes(ᶜρ)
    FT = Spaces.undertype(space)
    ᶜz = Fields.coordinate_field(space).z
    ᶜlat = latitude_field(space)

    # `ᶜscan_scratch` is free again: the tropopause scan has already been
    # reduced into `ᶜz_tropopause`.
    ᶜwork = ᶜscan_scratch

    tracers = stratospheric_tracer_fields(Y.c, chemistry_model)
    (; production_rate) = chemistry_model
    inverse_loss_timescale = inv(chemistry_model.loss_timescale)

    n = n_tracers(chemistry_model)
    burden = zeros(FT, n)
    source = zeros(FT, n)
    loss = zeros(FT, n)

    tracer_index = 0
    @inbounds for k in 1:n_height_bands(chemistry_model),
        i in 1:n_latitude_bands(chemistry_model)

        tracer_index += 1
        latitude_lower = chemistry_model.latitude_lower_edges[i]
        latitude_upper = chemistry_model.latitude_upper_edges[i]
        height_lower = chemistry_model.height_lower_edges[k]
        height_upper = chemistry_model.height_upper_edges[k]
        ᶜρχ = tracers[tracer_index]

        burden[tracer_index] = sum(ᶜρχ)

        @. ᶜwork = stratospheric_tracer_source(
            ᶜρ,
            ᶜz,
            ᶜlat,
            ᶜsource_reference,
            latitude_lower,
            latitude_upper,
            height_lower,
            height_upper,
            production_rate,
        )
        source[tracer_index] = sum(ᶜwork)

        @. ᶜwork = stratospheric_tracer_loss(
            ᶜρχ,
            ᶜz,
            ᶜz_tropopause,
            inverse_loss_timescale,
        )
        loss[tracer_index] = sum(ᶜwork)
    end
    return (; burden, source, loss)
end

# Seconds in a Julian year, the unit lifetimes are reported in.
const SECONDS_PER_YEAR = 365.25 * 86400

"""
    tracer_budget_header()

Column names of the tracer-budget table written by
[`write_tracer_budget!`](@ref).
"""
tracer_budget_header() = join(
    (
        "time",
        "tracer",
        "latitude_lower",
        "latitude_upper",
        "height_lower",
        "height_upper",
        "burden",
        "source",
        "loss",
        "lifetime",
        "lifetime_years",
        "imbalance",
    ),
    ",",
)

"""
    tracer_budget_path(output_dir)

Path of the tracer-budget table.
"""
tracer_budget_path(output_dir) =
    joinpath(output_dir, "stratospheric_tracer_budget.csv")

"""
    write_tracer_budget!(output_dir, t, chemistry_model, budget)

Append one row per tracer to the tracer-budget table, creating it (with a
header) if it does not exist yet. Called on the root process only.

`lifetime` is `burden / source`, in s, and is the quantity the experiment
exists to measure; it is meaningful once `imbalance = (source - loss) / source`
has settled near zero, which is what "the tracers are in equilibrium" means.
"""
function write_tracer_budget!(output_dir, t, chemistry_model, budget)
    (; burden, source, loss) = budget
    path = tracer_budget_path(output_dir)
    write_header = !isfile(path) || filesize(path) == 0
    open(path, "a") do io
        write_header && println(io, tracer_budget_header())
        names = stratospheric_tracer_symbols(chemistry_model)
        tracer_index = 0
        for k in 1:n_height_bands(chemistry_model),
            i in 1:n_latitude_bands(chemistry_model)

            tracer_index += 1
            source_rate = source[tracer_index]
            lifetime = source_rate > 0 ? burden[tracer_index] / source_rate : NaN
            imbalance =
                source_rate > 0 ?
                (source_rate - loss[tracer_index]) / source_rate : NaN
            # The outermost latitude edges are infinite so that the bands
            # partition the sphere; report them as the poles they stand for.
            println(
                io,
                join(
                    (
                        t,
                        names[tracer_index],
                        max(chemistry_model.latitude_lower_edges[i], -90),
                        min(chemistry_model.latitude_upper_edges[i], 90),
                        chemistry_model.height_lower_edges[k],
                        chemistry_model.height_upper_edges[k],
                        burden[tracer_index],
                        source_rate,
                        loss[tracer_index],
                        lifetime,
                        lifetime / SECONDS_PER_YEAR,
                        imbalance,
                    ),
                    ",",
                ),
            )
        end
    end
    return nothing
end

"""
    tracer_budget_callback!(integrator, output_dir, chemistry_model)

Compute the tracer budget and append it to the tracer-budget table. The budget
itself is collective — every process takes part in the global reductions — but
only the root process writes.
"""
function tracer_budget_callback!(integrator, output_dir, chemistry_model)
    Y = integrator.u
    budget = stratospheric_tracer_budget(Y, integrator.p, chemistry_model)
    if ClimaComms.iamroot(ClimaComms.context(Y.c))
        write_tracer_budget!(
            output_dir,
            Float64(integrator.t),
            chemistry_model,
            budget,
        )
    end
    return nothing
end
