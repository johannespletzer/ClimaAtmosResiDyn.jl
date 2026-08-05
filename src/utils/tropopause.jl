#####
##### WMO lapse-rate (thermal) tropopause
#####
##### Column-wise diagnosis of the tropopause height from the model
##### temperature profile. Used as a diagnostic (`ztrop`) and as the lower
##### boundary of the stratospheric passive tracers (see
##### `parameterized_tendencies/chemistry/stratospheric_passive_tracers.jl`).
#####

import ClimaCore: Fields, Geometry, Operators, Spaces

"""
    TropopauseParameters{FT}(;
        lapse_rate_threshold = 2e-3,
        consistency_depth = 2e3,
        search_min_height = 5e3,
        search_max_height = 25e3,
    )

Parameters of the WMO lapse-rate tropopause definition:

> The first tropopause is the lowest level at which the lapse rate decreases
> to 2 K/km or less, provided also that the average lapse rate between this
> level and all higher levels within 2 km does not exceed 2 K/km.

# Fields

  - `lapse_rate_threshold`: the 2 K/km threshold, in K m⁻¹.
  - `consistency_depth`: the 2 km depth over which the averaged lapse rate
    must stay below the threshold, in m.
  - `search_min_height`: candidate levels below this height are rejected, in
    m. This excludes boundary-layer and subsidence inversions, which
    otherwise satisfy the lapse-rate criterion. The WMO definition uses a
    pressure limit (500 hPa) for the same purpose.
  - `search_max_height`: candidate levels above this height are rejected, in
    m. Guards against picking up the stratopause in columns where the
    tropospheric lapse rate never recovers.
"""
Base.@kwdef struct TropopauseParameters{FT}
    lapse_rate_threshold::FT = 2e-3
    consistency_depth::FT = 2e3
    search_min_height::FT = 5e3
    search_max_height::FT = 25e3
end

# Height used where the lapse-rate scan finds no tropopause on a grid without
# latitude coordinates (a column or box). On the sphere the latitude-dependent
# `climatological_tropopause_height` is used instead.
const DEFAULT_TROPOPAUSE_HEIGHT = 12_000

"""
    climatological_tropopause_height(lat)

Latitude-dependent tropopause height in m, 17 km at the equator falling to
9 km at the poles. Only used as a fallback in columns where the lapse-rate
scan finds no tropopause; a nonzero `ztrop_missing` diagnostic means this
fallback is in use and the temperature profile should be inspected.
"""
@inline climatological_tropopause_height(lat) =
    oftype(lat, 17_000) - oftype(lat, 8_000) * sind(lat)^2

"""
    wmo_tropopause_scan_step(
        state, T, z,
        lapse_rate_threshold, consistency_depth,
        search_min_height, search_max_height,
    )

One bottom-to-top step of the WMO lapse-rate tropopause scan, written as a
state transition so that a whole column can be swept with
`Operators.column_accumulate!`.

`state` carries, for one column:

  - `T_previous`, `z_previous`: the level below, which supplies the lapse rate
    across the layer between it and this level. `T_previous == 0` marks the
    bottom level, where no level below exists.
  - `T_candidate`, `z_candidate`: the active candidate tropopause, or zeros
    when no candidate is active.
  - `z_tropopause`: zero until a candidate has been confirmed, and the
    confirmed height from then on. Once set it is never revised, so the scan
    returns the *lowest* level satisfying the definition.

A candidate is opened at the lowest level in `[search_min_height,
search_max_height]` whose lapse rate over the layer above it has fallen to the
threshold. It is confirmed once the scan has climbed `consistency_depth` above
it without the mean lapse rate from the candidate to any intervening level
exceeding the threshold, and dropped as soon as one of them does — in which
case the level below the current one is immediately retested as a new
candidate.
"""
@inline function wmo_tropopause_scan_step(
    state,
    T,
    z,
    lapse_rate_threshold,
    consistency_depth,
    search_min_height,
    search_max_height,
)
    (; T_previous, z_previous, T_candidate, z_candidate, z_tropopause) = state

    z_zero = zero(z)
    found = z_tropopause > z_zero
    has_candidate = z_candidate > z_zero

    # Lapse rate across the layer below, positive where temperature falls with
    # height. This is the lapse rate *above* the previous level, so the
    # previous level becomes the candidate, not this one. The tropopause is the
    # level where the atmosphere stops cooling, not the first level after it.
    #
    # Both branches of every `ifelse` are evaluated, so each denominator is
    # kept away from zero and the guard picks the meaningful branch.
    Δz_previous = z - z_previous
    has_level_below = (Δz_previous > z_zero) & (T_previous > zero(T_previous))
    lapse_rate = ifelse(
        has_level_below,
        (T_previous - T) / ifelse(has_level_below, Δz_previous, one(z)),
        2 * lapse_rate_threshold,  # fails the threshold test below
    )

    # Mean lapse rate from the active candidate up to this level.
    Δz_candidate = z - z_candidate
    mean_lapse_rate =
        (T_candidate - T) /
        ifelse(Δz_candidate > z_zero, Δz_candidate, one(z))

    candidate_holds = has_candidate & (mean_lapse_rate <= lapse_rate_threshold)
    candidate_confirmed = candidate_holds & (Δz_candidate >= consistency_depth)
    candidate_dropped = has_candidate & !candidate_holds

    opens_candidate =
        (!has_candidate | candidate_dropped) &
        has_level_below &
        (lapse_rate <= lapse_rate_threshold) &
        (z_previous >= search_min_height) &
        (z_previous <= search_max_height)

    # `opens_candidate` and `candidate_holds` are mutually exclusive. The
    # first needs no active candidate, or one just dropped; the second needs an
    # active candidate that was not dropped.
    new_z_candidate = ifelse(
        found,
        z_candidate,
        ifelse(
            opens_candidate,
            z_previous,
            ifelse(candidate_holds, z_candidate, z_zero),
        ),
    )
    new_T_candidate = ifelse(
        found,
        T_candidate,
        ifelse(
            opens_candidate,
            T_previous,
            ifelse(candidate_holds, T_candidate, zero(T)),
        ),
    )
    new_z_tropopause = ifelse(
        found,
        z_tropopause,
        ifelse(candidate_confirmed, z_candidate, z_zero),
    )

    return (;
        T_previous = T,
        z_previous = z,
        T_candidate = new_T_candidate,
        z_candidate = new_z_candidate,
        z_tropopause = new_z_tropopause,
    )
end

"""
    set_tropopause_height!(ᶜz_tropopause, ᶜscratch, ᶜT, tropopause_params)

Fill `ᶜz_tropopause` with the WMO lapse-rate tropopause height of each column,
broadcast to every level of that column, so that `z < ᶜz_tropopause` is a
pointwise test for "below the tropopause". `ᶜscratch` is overwritten.

The diagnosis takes two column sweeps:

 1. A bottom-to-top scan ([`wmo_tropopause_scan_step`](@ref)) that writes zero
    below the level where the tropopause is confirmed and the tropopause
    height at and above it. Confirmation happens `consistency_depth` above the
    tropopause itself, so this partial result is still zero in the layer
    immediately above the tropopause.
 2. A top-to-bottom running maximum, which carries the single nonzero value
    down the whole column.

Columns where the scan finds nothing keep a zero after the first sweep and are
filled with [`climatological_tropopause_height`](@ref).
"""
function set_tropopause_height!(
    ᶜz_tropopause,
    ᶜscratch,
    ᶜT,
    tropopause_params::TropopauseParameters,
)
    space = axes(ᶜT)
    FT = Spaces.undertype(space)
    ᶜz = Fields.coordinate_field(space).z

    lapse_rate_threshold = FT(tropopause_params.lapse_rate_threshold)
    consistency_depth = FT(tropopause_params.consistency_depth)
    search_min_height = FT(tropopause_params.search_min_height)
    search_max_height = FT(tropopause_params.search_max_height)

    input = @. lazy(tuple(ᶜT, ᶜz))
    Operators.column_accumulate!(
        ᶜscratch,
        input;
        init = (;
            T_previous = FT(0),
            z_previous = FT(0),
            T_candidate = FT(0),
            z_candidate = FT(0),
            z_tropopause = FT(0),
        ),
        transform = state -> state.z_tropopause,
    ) do state, (T, z)
        wmo_tropopause_scan_step(
            state,
            T,
            z,
            lapse_rate_threshold,
            consistency_depth,
            search_min_height,
            search_max_height,
        )
    end

    Operators.column_accumulate!(
        max,
        ᶜz_tropopause,
        ᶜscratch;
        init = FT(0),
        reverse = true,
    )

    return fill_missing_tropopause!(ᶜz_tropopause)
end

"""
    fill_missing_tropopause!(ᶜz_tropopause)

Replace the zeros left by [`set_tropopause_height!`](@ref) in columns where
the lapse-rate scan found no tropopause with a climatological estimate.
"""
function fill_missing_tropopause!(ᶜz_tropopause)
    space = axes(ᶜz_tropopause)
    FT = Spaces.undertype(space)
    coordinates = Fields.coordinate_field(space)
    if eltype(coordinates) <: Geometry.LatLongZPoint
        ᶜlat = coordinates.lat
        @. ᶜz_tropopause = ifelse(
            ᶜz_tropopause > 0,
            ᶜz_tropopause,
            climatological_tropopause_height(ᶜlat),
        )
    else
        z_fallback = FT(DEFAULT_TROPOPAUSE_HEIGHT)
        @. ᶜz_tropopause =
            ifelse(ᶜz_tropopause > 0, ᶜz_tropopause, z_fallback)
    end
    return ᶜz_tropopause
end

"""
    latitude_field(space)

Latitude coordinate field of `space`, in degrees. Errors on grids without
latitude (columns, boxes and planes), which the latitude-banded tracer sources
cannot be defined on.
"""
function latitude_field(space)
    coordinates = Fields.coordinate_field(space)
    eltype(coordinates) <: Geometry.LatLongZPoint || error(
        "latitude-dependent sources require a spherical grid, but this grid \
        has coordinates of type $(eltype(coordinates))",
    )
    return coordinates.lat
end
