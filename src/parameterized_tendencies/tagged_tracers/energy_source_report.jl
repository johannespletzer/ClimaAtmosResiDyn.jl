#####
##### The residual report of the energy source tags (G4.4)
#####
##### Beside the closure check's integrals, the report says where the residual
##### sits, how fast the loss rule flushes it and the level it would settle at,
##### how far the partitioned total is from zero, and whether the overlays
##### leave their bounds. It describes the residual; it is not a verdict.
##### Every function here reads the state and the tags' caches and writes only
##### scratch fields. Each reduction is collective, so every process calls it.
##### The design is design/RESIDUAL_REPORT.md on the record branch.

# The largest and smallest value of a field over the whole domain, reduced
# across processes. `Base.maximum` on a `Field` does not reduce across them.
function _global_extremum(ᶜfield, op)
    local_value = op === max ? maximum(parent(ᶜfield)) : minimum(parent(ᶜfield))
    buffer = [local_value]
    ClimaComms.allreduce!(ClimaComms.context(ᶜfield), buffer, op)
    return buffer[1]
end

# The height of a cell where `ᶜvalue` equals `target`, the highest where several
# do, or `NaN` where none does. `ᶜvalue` is overwritten.
function _height_of!(ᶜvalue, target, Y)
    FT = eltype(ᶜvalue)
    ᶜz = Fields.coordinate_field(Y.c).z
    @. ᶜvalue = ifelse(ᶜvalue == target, ᶜz, typemin(FT))
    z = _global_extremum(ᶜvalue, max)
    return isfinite(z) ? z : FT(NaN)
end

# The residual `R = E - Σ partition tags` per cell, into `ᶜR`.
function _fill_energy_source_residual!(ᶜR, Y, model)
    ᶜparent = _energy_source_parent_field(Y, model.offset)
    @. ᶜR = ᶜparent
    for name in energy_source_region_tag_state_names(model)
        ᶜtag = getproperty(Y.c, name)
        @. ᶜR -= ᶜtag
    end
    return ᶜR
end

"""
    energy_source_headroom(Y, p, model)

U9, the offset's headroom, for the closure table of the energy source tags:

  - `headroom_min`: the smallest `E/ρ = e_tot + c` in the domain, in J/kg,
    reduced across processes;
  - `headroom_min_z`: the height of that cell, the highest where several tie.

`nonpositive_fraction` moves only once a cell has crossed `E ≤ 0`. The headroom
shows the margin before that. It changes no run: a diagnostic never ends one
by default (`DEFAULT_CLOSURE_ABORT_LEVELS`). Collective.
"""
function energy_source_headroom(Y, p, model::EnergySourceTaggingModel)
    ᶜtmp = p.scratch.ᶜtemp_scalar_2
    ᶜparent = _energy_source_parent_field(Y, model.offset)
    @. ᶜtmp = ᶜparent / Y.c.ρ
    headroom_min = _global_extremum(ᶜtmp, min)
    headroom_min_z = _height_of!(ᶜtmp, headroom_min, Y)
    return (; headroom_min, headroom_min_z)
end

"""
    energy_source_closure_columns(Y, p, model, closure)

The energy source tags' own columns of their closure table: the headroom
([`energy_source_headroom`](@ref)), and, where each tag keeps its ledgers:

  - `source_partition_valid`: 1 where the pure region tags' masks are a
    verified partition ([`energy_source_partition_verified`](@ref)), 0
    elsewhere;
  - `source_throughput`: the gross source throughput since the start of the
    run, in J ([`energy_source_throughput`](@ref));
  - `gross_over_throughput`: the row's gross residual over it (G4.5).

Only a verified partition counts each unit of source energy once. Elsewhere
the throughput and the ratio are `NaN`, and so is the ratio where the
throughput is zero. The ratio's scale is set by the sources, not by the energy
reference as `gross_relative`'s is; the residual itself still grows with the
offset. `throughput_tolerance` warns on it. A window's throughput is the
difference of two rows. Collective.
"""
function energy_source_closure_columns(Y, p, model::EnergySourceTaggingModel, closure)
    headroom = energy_source_headroom(Y, p, model)
    throughput = energy_source_throughput(Y, p, model)
    isnothing(throughput) && return headroom
    columns = _energy_source_throughput_column(throughput, p.tagging)
    # `NaN > 0` is false, so the ratio is `NaN` without a verified partition.
    gross_over_throughput =
        columns.source_throughput > 0 ?
        Float64(closure.gross_residual) / columns.source_throughput : NaN
    return (; headroom..., columns..., gross_over_throughput)
end

"""
    check_energy_source_throughput_partition(tagging, check)

Refuse `throughput_tolerance` where the pure region tags' masks are not a
verified partition ([`energy_source_partition_verified`](@ref)). The level is
compared with `gross_over_throughput`, which is `NaN` there, so it could never
warn. `tagging` is the cache, `p.tagging`, and `check` the energy source
closure check, or `nothing`. The masks are known only once the cache is built,
so `AtmosSimulation` calls this at setup, before the callbacks. A no-op
without the level or without the tags.
"""
check_energy_source_throughput_partition(tagging, ::Nothing) = nothing
function check_energy_source_throughput_partition(tagging, check)
    isnothing(get(check, :throughput_tolerance, nothing)) && return nothing
    isnothing(tagging) && return nothing
    hasproperty(tagging, :energy_source_partition_deviation) || return nothing
    deviation = tagging.energy_source_partition_deviation
    energy_source_partition_verified(deviation) && return nothing
    tolerance = energy_source_partition_tolerance(typeof(deviation))
    return error(
        "`energy_source_closure_check` sets `throughput_tolerance`, which \
        compares the gross residual with the gross source throughput. The \
        throughput counts each unit of source energy once only where the \
        masks of the region tags without sources sum to 1. These sum to 1 only \
        to within $deviation, more than the $tolerance allowed, so the \
        throughput and the ratio are `NaN` and the level could never warn. \
        Use regions that sum to 1, such as a region and its complement via \
        `inside: false` or `above: false`, or drop `throughput_tolerance`.",
    )
end

"""
    energy_source_residual_report(Y, p, model, closure, t, previous)

The residual report of the energy source tags, as more columns of their audit
table (G4.4). `R = E - Σ partition tags` per cell, and `G` is `closure`'s
`gross_residual`.

Where the residual sits:

  - `residual_max`: the largest `|R|/ρ`, in J/kg; `residual_max_z`, its height;
  - `residual_peak_level`: the level whose layer holds the largest part of the
    gross, counted from the surface; `residual_peak_fraction`, that part over
    the sum of the layers; `residual_peak_z`, the level's volume-mean height.

Where the residual is zero everywhere there is no peak and no maximum to
place, so `residual_peak_level`, `residual_peak_fraction`, `residual_peak_z`
and `residual_max_z` are `NaN`.

The overlays, the tags that carry sources, against the partition they overlay
(A5):

  - `overlay_negative_mass_fraction`: the air mass where any overlay is
    negative, over the domain's air mass;
  - `overlay_excess`: the integral of `Σ_overlays max(tag - Σ partition, 0)`,
    in J, where an overlay holds more than the partition's sum;
  - `overlay_excess_mass_fraction`: the air mass where any overlay does.

The flush and the settling level (synergy 4), where the tags keep their
ledgers per tag, and so the residual's source ledger `e_src_led_src_res`. That
ledger is the net residual source attribution. It is the loss rule's flush only
where the pure region tags' masks are a verified partition
([`energy_source_partition_verified`](@ref)). Elsewhere every column below is
`NaN`:

  - `flush_gross`: `F`, the per-step gross of that ledger since the start of
    the run, in J: what the loss rule flushed from the residual;
  - `flush_rate`: `λ = ΔF / (Ḡ Δt)`, per day, over the interval since the
    previous check, `Ḡ` the mean of the two checks' `G`;
  - `production_rate`: `P = (ΔG + ΔF) / Δt`, in J per day, what everything
    else added to the residual;
  - `settling_level`: `G* = P/λ`, the gross at which the two would balance,
    and `settling_ratio`, `G*/G`;
  - `forecast_defined`: 1 where `settling_level` is a number, 0 elsewhere.

`previous` is a `Ref` that holds the last check's `(t, G, F)`, or `nothing`.
The first check, and the first after a restart, have no interval, and write
`NaN` for the rates. A balance needs `P > 0`: where the rest of the run did
not add to the residual, it only decays, and `settling_level` is `NaN`
([`energy_source_forecast`](@ref)). `λ` is not constant (E74), so `G*` is an
order of magnitude, not a prediction. Collective.
"""
function energy_source_residual_report(
    Y,
    p,
    model::EnergySourceTaggingModel,
    closure,
    t,
    previous,
)
    ᶜR = p.scratch.ᶜtemp_scalar
    ᶜtmp = p.scratch.ᶜtemp_scalar_2
    FT = eltype(ᶜR)
    _fill_energy_source_residual!(ᶜR, Y, model)

    # The local maximum per unit mass, and where it is. A zero residual has
    # its maximum in every cell, so it has no height.
    @. ᶜtmp = abs(ᶜR) / Y.c.ρ
    residual_max = _global_extremum(ᶜtmp, max)
    residual_max_z =
        residual_max > 0 ? _height_of!(ᶜtmp, residual_max, Y) : FT(NaN)

    # The gross per layer. On a column a level's sum is its layer's integral
    # per unit area; on a sphere, over the whole layer. Every process has the
    # same layers, so every process takes the same branch below.
    @. ᶜtmp = abs(ᶜR)
    nlevels = Spaces.nlevels(axes(ᶜtmp))
    layers = [Float64(sum(Fields.level(ᶜtmp, level))) for level in 1:nlevels]
    total = sum(layers)
    residual_peak_level = NaN
    residual_peak_fraction = NaN
    residual_peak_z = NaN
    if total > 0
        peak = argmax(layers)
        residual_peak_level = Float64(peak)
        residual_peak_fraction = layers[peak] / total
        @. ᶜtmp = one(FT)
        volume = sum(Fields.level(ᶜtmp, peak))
        ᶜz = Fields.coordinate_field(Y.c).z
        @. ᶜtmp = ᶜz
        residual_peak_z = Float64(sum(Fields.level(ᶜtmp, peak)) / volume)
    end

    # The overlays against the partition's sum, `E - R`.
    overlay_names = Tuple(
        Symbol(:ρe_src_, tag_name(tag)) for
        tag in model.tags if !isempty(tag.sources)
    )
    mass = sum(Y.c.ρ)
    overlay_negative_mass_fraction = FT(NaN)
    overlay_excess = FT(NaN)
    overlay_excess_mass_fraction = FT(NaN)
    if !isempty(overlay_names)
        @. ᶜtmp = typemax(FT)
        for name in overlay_names
            ᶜtag = getproperty(Y.c, name)
            @. ᶜtmp = min(ᶜtmp, ᶜtag)
        end
        @. ᶜtmp = ifelse(ᶜtmp < zero(FT), Y.c.ρ, zero(FT))
        overlay_negative_mass_fraction = sum(ᶜtmp) / mass
        ᶜparent = _energy_source_parent_field(Y, model.offset)
        @. ᶜR = ᶜparent - ᶜR
        @. ᶜtmp = zero(FT)
        for name in overlay_names
            ᶜtag = getproperty(Y.c, name)
            @. ᶜtmp += max(ᶜtag - ᶜR, zero(FT))
        end
        overlay_excess = sum(ᶜtmp)
        @. ᶜtmp = ifelse(ᶜtmp > zero(FT), Y.c.ρ, zero(FT))
        overlay_excess_mass_fraction = sum(ᶜtmp) / mass
    end

    return (;
        residual_max,
        residual_max_z,
        residual_peak_level,
        residual_peak_fraction,
        residual_peak_z,
        overlay_negative_mass_fraction,
        overlay_excess,
        overlay_excess_mass_fraction,
        _energy_source_forecast(p, closure, t, previous)...,
    )
end

# The per-step gross of the residual's source ledger since the start of the
# run, or `nothing` where the tags keep no ledger per tag.
_energy_source_flush_gross(::Nothing) = nothing
function _energy_source_flush_gross(steps)
    haskey(steps.ledgers, ENERGY_SOURCE_RESIDUAL_LEDGER) || return nothing
    ledger = getproperty(steps.ledgers, ENERGY_SOURCE_RESIDUAL_LEDGER)
    return Float64(sum(ledger.ᶜgross))
end

"""
    energy_source_forecast(G₀, F₀, t₀, G, F, t)

Synergy 4 from two checks, `(t₀, G₀, F₀)` and `(t, G, F)`, with `t` in
seconds, `G` the gross residual and `F` the gross flush, both in J:
`(; flush_rate, production_rate, settling_level, settling_ratio, forecast_defined)`, the rates per day.

  - `flush_rate` is `NaN` where the interval is empty, the mean gross is zero,
    or nothing was flushed, since the rate is then not defined.
  - `production_rate` is `NaN` only where the interval is empty. It can be
    zero or negative: then the rest of the run took from the residual, or
    added nothing, over the interval.
  - `settling_level` needs both rates, and a positive production. Without
    one the residual only decays, and there is no positive level to settle
    at, so it is `NaN`. `settling_ratio` also needs `G > 0`.
  - `forecast_defined` is 1 where `settling_level` is a number, 0 elsewhere.
"""
function energy_source_forecast(G₀, F₀, t₀, G, F, t)
    days = (t - t₀) / 86400
    mean_gross = (G + G₀) / 2
    flushed = F - F₀
    rated = days > 0 && mean_gross > 0 && flushed > 0
    flush_rate = rated ? flushed / (mean_gross * days) : NaN
    production_rate = days > 0 ? (G - G₀ + flushed) / days : NaN
    # A negative level would be no balance at all: the residual decays.
    defined = rated && production_rate > 0
    settling_level = defined ? production_rate / flush_rate : NaN
    settling_ratio = defined && G > 0 ? settling_level / G : NaN
    return (;
        flush_rate,
        production_rate,
        settling_level,
        settling_ratio,
        forecast_defined = Int(defined),
    )
end

function _energy_source_forecast(p, closure, t, previous)
    F = _energy_source_flush_gross(_tag_ledger_steps(p.tagging))
    isnothing(F) && return (;)
    G = Float64(closure.gross_residual)
    last = previous[]
    previous[] = (; t = Float64(t), G, F)
    no_rates = (;
        flush_rate = NaN,
        production_rate = NaN,
        settling_level = NaN,
        settling_ratio = NaN,
        forecast_defined = 0,
    )
    # Without a verified partition the ledger is the net residual source
    # attribution, not the flush, so no rate is read from it.
    energy_source_partition_verified(p.tagging) ||
        return (; flush_gross = NaN, no_rates...)
    rates =
        isnothing(last) ? no_rates :
        energy_source_forecast(last.G, last.F, last.t, G, F, Float64(t))
    return (; flush_gross = F, rates...)
end
