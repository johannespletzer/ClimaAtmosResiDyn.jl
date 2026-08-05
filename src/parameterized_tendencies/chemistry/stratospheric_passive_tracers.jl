###
### Stratospheric passive tracers
###
###
### Passive, chemically inert tracers. Each has one source, a constant
### production rate inside a (latitude band × height band) region, and one
### sink, removal below the model tropopause. Once a tracer's burden stops
### drifting, source and sink balance and its lifetime is
###
###     τ = M / S
###
### with `M` the global burden (kg) and `S` the global source rate (kg s⁻¹).
### The tracer-budget callback reports both, so `τ` never depends on reading
### the prescribed production rate correctly.
###
### The source regions are small, well-separated boxes. They sample the domain
### above the tropopause instead of tiling it: narrow latitude bands from pole
### to pole, and shallow height bands stacked above the local tropopause. A
### small box is what makes its lifetime meaningful, because a tracer emitted
### over a deep layer or a wide latitude range reports an average over
### conditions that can differ by years. Gaps between the boxes are therefore
### deliberate.
###

import ClimaComms
import ClimaCore: Fields, Spaces

"""
    TropopauseRelativeHeight()

Measure tracer source heights from the local tropopause, so that the source
boxes follow it. This is the default: it keeps every box a fixed distance
above the sink whatever the latitude, which is what makes lifetimes from
different latitude bands comparable.
"""
struct TropopauseRelativeHeight end

"""
    GeometricHeight()

Measure tracer source heights from sea level, giving source regions at fixed
altitudes. Regions that fall below the local tropopause are removed as fast as
they are produced, so their lifetimes approach `loss_timescale`.
"""
struct GeometricHeight end

"""
    StratosphericPassiveTracers{NY, NZ, FT, HC, TP} <: AbstractChemistryModel

`NY * NZ` passive tracers, one per (latitude band, height band) source region.

Region `(i, k)` is the set of points with latitude in
`(latitude_lower_edges[i], latitude_upper_edges[i]]` and height in
`(height_lower_edges[k], height_upper_edges[k]]`, where height is measured
from the local tropopause (`TropopauseRelativeHeight`) or from sea level
(`GeometricHeight`). The boxes never overlap, so no point feeds two tracers,
but they do not cover the domain — they sample it.

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

Build a [`StratosphericPassiveTracers`](@ref) whose source boxes sample the
domain above the tropopause.

# Keyword arguments

  - `n_latitude_bands = 6`: number of latitude boxes. They are centred on the
    midpoints of that many equal divisions of pole to pole, so they sample the
    full range symmetrically about the equator.
  - `latitude_width = 10`: width of each latitude box, in degrees. Must not
    exceed the spacing between boxes, or they would overlap.
  - `n_height_bands = 8`: number of height boxes, stacked above the reference.
  - `band_depth = 2000`: depth of each height box, in m. Must not exceed
    `band_spacing`.
  - `band_spacing = 5000`: distance between the bottoms of successive height
    boxes, in m. With the defaults the boxes sample 0–37 km above the
    tropopause in 2 km slices.
  - `lowest_band_base = 0`: height of the bottom of the lowest box above the
    reference, in m. The default puts the lowest source immediately above the
    tropopause; raise it to separate that box from the sink.
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
    latitude_width = 10,
    band_depth = 2000,
    band_spacing = 5000,
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
    latitude_width > 0 ||
        error("latitude_width must be positive, got $latitude_width")
    band_depth > 0 || error("band_depth must be positive, got $band_depth")
    band_spacing > 0 ||
        error("band_spacing must be positive, got $band_spacing")
    loss_timescale > 0 ||
        error("loss_timescale must be positive, got $loss_timescale")

    # Latitude boxes sit at the centres of `n_latitude_bands` equal divisions
    # from pole to pole, so they sample the range symmetrically about the
    # equator. A box wider than its division would overlap its neighbour, and
    # one point would then feed two tracers.
    latitude_interval = FT(180) / n_latitude_bands
    latitude_width <= latitude_interval || error(
        "latitude_width ($latitude_width) exceeds the $latitude_interval degree \
        spacing of $n_latitude_bands bands, so the boxes would overlap",
    )
    half_width = FT(latitude_width) / 2
    latitude_centers = ntuple(n_latitude_bands) do i
        FT(-90) + (i - FT(0.5)) * latitude_interval
    end
    latitude_lower_edges = map(center -> center - half_width, latitude_centers)
    latitude_upper_edges = map(center -> center + half_width, latitude_centers)

    # Height boxes are stacked every `band_spacing` above the reference and are
    # `band_depth` deep, so they sample the column rather than tiling it. The
    # same non-overlap condition applies.
    band_depth <= band_spacing || error(
        "band_depth ($band_depth) exceeds band_spacing ($band_spacing), so the \
        boxes would overlap",
    )
    height_lower_edges = ntuple(n_height_bands) do k
        FT(lowest_band_base) + (k - 1) * FT(band_spacing)
    end
    height_upper_edges =
        map(lower -> lower + FT(band_depth), height_lower_edges)

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
        "lifetime_from_loss",
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
            loss_rate = loss[tracer_index]
            lifetime = source_rate > 0 ? burden[tracer_index] / source_rate : NaN
            # `burden / loss` is the same lifetime measured against the sink
            # instead of the source. The two agree only in equilibrium; before
            # it they bracket the answer. While the tracer fills,
            # `burden / source` is just the elapsed time and rises to the
            # lifetime from below, while the sink has barely started, so
            # `burden / loss` falls to it from above. Their convergence tells
            # you how much longer a run needs.
            lifetime_from_loss =
                loss_rate > 0 ? burden[tracer_index] / loss_rate : NaN
            imbalance =
                source_rate > 0 ? (source_rate - loss_rate) / source_rate : NaN
            println(
                io,
                join(
                    (
                        t,
                        names[tracer_index],
                        chemistry_model.latitude_lower_edges[i],
                        chemistry_model.latitude_upper_edges[i],
                        chemistry_model.height_lower_edges[k],
                        chemistry_model.height_upper_edges[k],
                        burden[tracer_index],
                        source_rate,
                        loss_rate,
                        lifetime,
                        lifetime / SECONDS_PER_YEAR,
                        lifetime_from_loss,
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
