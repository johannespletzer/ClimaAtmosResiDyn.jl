# Chemistry component callbacks
function default_model_callbacks(
    chemistry::AtmosChem;
    dt_tracer_budget = "10days",
    output_dir,
    dt,
    t_start,
    t_end,
    checkpoint_frequency,
    kwargs...,
)
    return tracer_budget_callback(
        chemistry.chemistry_model,
        dt_tracer_budget,
        output_dir,
        dt,
        t_start,
        t_end,
        checkpoint_frequency,
    )
end

tracer_budget_callback(
    chemistry_model,
    dt_tracer_budget,
    output_dir,
    dt,
    t_start,
    t_end,
    checkpoint_frequency,
) = ()

"""
    tracer_budget_callback(
        chemistry_model::StratosphericPassiveTracers,
        dt_tracer_budget, output_dir, dt, t_start, t_end, checkpoint_frequency,
    )

Periodically append the global burden, source rate and loss rate of every
stratospheric passive tracer to `stratospheric_tracer_budget.csv` in the
output directory. These are the quantities the residence time
`burden / source` is computed from, and their drift is what tells you whether
the tracers have reached equilibrium yet.
"""
function tracer_budget_callback(
    chemistry_model::StratosphericPassiveTracers,
    dt_tracer_budget,
    output_dir,
    dt,
    t_start,
    t_end,
    checkpoint_frequency,
)
    budget_period_seconds = time_to_seconds(dt_tracer_budget)
    isfinite(budget_period_seconds) || return ()

    if !isnothing(checkpoint_frequency) && checkpoint_frequency != Inf
        rounded_period = Dates.Second(round(Int, budget_period_seconds))
        isdivisible(checkpoint_frequency, rounded_period) || @warn(
            "tracer budget period ($rounded_period) is not an even divisor of \
            the checkpoint frequency ($checkpoint_frequency); the budget table \
            will contain duplicated rows after a restart."
        )
    end

    budget_period = ITime(budget_period_seconds)
    budget_period, _, _, _ = promote(budget_period, t_start, dt, t_end)

    affect!(integrator) =
        tracer_budget_callback!(integrator, output_dir, chemistry_model)
    return (call_every_dt(affect!, budget_period),)
end

# Tagging component callbacks
"""
    default_model_callbacks(tagging::AtmosTagging; water_closure_check = nothing,
                            energy_closure_check = nothing,
                            energy_source_closure_check = nothing, kwargs...)

Install the online tag closure checks of the three tag families.

The families are checked separately, on their own cadence and against their own
tolerance, because their residuals are not comparable. The energy tags never
receive implicit transport or EDMFX SGS mass fluxes, so their residual is
legitimately the larger one. The energy source tags default to one tolerance per
transport: 1.0 for `tracer`, 0.1 for `enthalpy` and 0.01 for
`enthalpy_increment`. Their residual is normalized by a quantity whose zero is a
convention, so it is not comparable across runs that use different energy
references.

Each block also carries a `void_above` level, above which the check warns once
and marks its rows `closure_void` while the run goes on, also after a restart.
Only water has a default one, for the same reason: see
[`DEFAULT_CLOSURE_VOID_LEVELS`](@ref). An `abort_above`
level ends the run instead, only where a user sets it: see
[`DEFAULT_CLOSURE_ABORT_LEVELS`](@ref).

Each block also carries an `audit` flag, off by default, which adds a second
table splitting the residual into the parts that mean different things. See
[`tag_audit`](@ref).

The water block also carries `negative_water_void_above`, `1e-4` by default:
the check reports the parent's own negative water, from the raw `ρq_tot`, and
marks its rows `negative_water_void` past the level. The tags' per-step
callback compares the same ratio with the level at the end of every accepted
step, so an excursion between two rows marks the next one. See
[`negative_water_rows`](@ref) and [`check_negative_water_step!`](@ref).
"""
function default_model_callbacks(
    tagging::AtmosTagging;
    water_closure_check = nothing,
    energy_closure_check = nothing,
    energy_source_closure_check = nothing,
    output_dir,
    dt,
    t_start,
    t_end,
    checkpoint_frequency,
    kwargs...,
)
    scheduling = (; output_dir, dt, t_start, t_end, checkpoint_frequency)
    return (
        tag_ledger_gross_callback(tagging, water_closure_check)...,
        tag_closure_callback(
            water_closure_check,
            tagging.water_tagging_model;
            family = "water",
            # The partition's target, the parent's non-negative water. Under
            # `water_tag_precipitation: true` it is the sum of the three
            # compartments' non-negative parts.
            total_name = water_closure_total(tagging.water_tagging_model),
            # The region tags, with their rain and snow parts under
            # `water_tag_precipitation: true`.
            state_names = water_partition_state_names,
            config_key = "water_closure_check",
            tracer_key = "water_tracers",
            extra_audit = water_extra_audit(tagging.water_tagging_model),
            # The parent's own negative water, from the raw `ρq_tot`.
            reads_negative_water = true,
            scheduling...,
        )...,
        tag_closure_callback(
            energy_closure_check,
            tagging.tagging_model;
            family = "energy",
            total_name = :ρe_tot,
            state_names = region_tag_state_names,
            config_key = "energy_closure_check",
            tracer_key = "energy_tracers",
            scheduling...,
        )...,
        tag_closure_callback(
            energy_source_closure_check,
            tagging.energy_source_tagging_model;
            family = "energy_source",
            total_name = energy_source_closure_total(
                tagging.energy_source_tagging_model,
            ),
            state_names = energy_source_region_tag_state_names,
            config_key = "energy_source_closure_check",
            tracer_key = "energy_source_tags",
            extra_audit = energy_source_extra_audit(
                tagging.energy_source_tagging_model,
            ),
            extra_closure = energy_source_extra_closure(
                tagging.energy_source_tagging_model,
            ),
            scheduling...,
        )...,
    )
end

tag_closure_callback(::Nothing, tagging_model; kwargs...) = ()

# The per-step gross of the tags' state ledgers, after every step, where the
# tags keep any. It reads the state and writes only its own cache. With water
# tags, the same callback compares the parent's negative water with the water
# check's `negative_water_void_above`. It comes before the closure checks, so a
# row in the same step already sees the flag.
tag_ledger_gross_callback(tagging, water_closure_check = nothing) =
    isempty(tag_state_ledger_names(tagging)) ? () :
    (
        call_every_n_steps(
            tag_ledger_step_affect(
                negative_water_step_level(
                    water_closure_check,
                    tagging.water_tagging_model,
                ),
            ),
            1;
            skip_first = true,
        ),
    )

# The per-step callback's work. The level of the check at every step is fixed
# in the closure: a number, or `nothing` for no check.
tag_ledger_step_affect(negative_water_void_above) =
    integrator ->
        accumulate_tag_ledger_gross!(integrator, negative_water_void_above)

"""
    negative_water_step_level(water_closure_check, water_tagging_model)

The level that the check at every accepted step compares the parent's
negative water with: the water check's `negative_water_void_above`. It is
`nothing` without water tags, without a water check, or where the key is `~`.
Then the step does no work for it.
"""
negative_water_step_level(water_closure_check, water_tagging_model) =
    (isnothing(water_closure_check) || isnothing(water_tagging_model)) ?
    nothing : get(water_closure_check, :negative_water_void_above, nothing)

# The water family's own audit columns, under prognostic EDMF and under
# increment transport, as a function of `(Y, p, closure, t)`, or `nothing`
# without the tags.
water_extra_audit(::Nothing) = nothing
water_extra_audit(model) =
    (Y, p, closure, t) -> water_tag_extra_audit(Y, p, model, closure.scale)

# The energy source family's own audit columns, as a function of
# `(Y, p, closure, t)`, or `nothing` without the tags: the family's audit, then
# the residual report. The report's forecast needs the previous check, which the
# `Ref` keeps. A restart builds a new one.
energy_source_extra_audit(::Nothing) = nothing
function energy_source_extra_audit(model)
    previous = Ref{Any}(nothing)
    return (Y, p, closure, t) -> merge(
        energy_source_audit(Y, p, model, closure.scale),
        energy_source_residual_report(Y, p, model, closure, t, previous),
    )
end

# The energy source family's own closure columns, the offset's headroom and the
# source throughput, as a function of `(Y, p, closure)`, or `nothing`
# without the tags.
energy_source_extra_closure(::Nothing) = nothing
energy_source_extra_closure(model) =
    (Y, p, closure) -> energy_source_closure_columns(Y, p, model, closure)

"""
    tag_closure_callback(check, tagging_model; family, total_name, state_names,
                         config_key, tracer_key, output_dir, dt, t_start, t_end,
                         checkpoint_frequency)

Build the periodic closure-check callback of one tag family, or `()` when the
family's `check` block is absent.

Both ways of asking for a check that cannot be computed are refused here, at
setup, rather than left to fail or mislead mid-run.

The divisor check is spelled out here rather than left to `scheduled_callback`,
whose warning is about reproducibility. This callback adds no tendency, so a
restart cannot make the run irreproducible; what it does is append to a table,
so the cost of a period that does not divide the checkpoint frequency is
duplicated rows. Same as `tracer_budget_callback` next door.
"""
function tag_closure_callback(
    check,
    tagging_model;
    family,
    total_name,
    state_names,
    config_key,
    tracer_key,
    output_dir,
    dt,
    t_start,
    t_end,
    checkpoint_frequency,
    extra_audit = nothing,
    extra_closure = nothing,
    reads_negative_water = false,
)
    isnothing(tagging_model) && error(
        "`$config_key` is set but `$tracer_key` is not, so there are no tags \
        to check. Configure `$tracer_key`, or drop `$config_key`.",
    )
    tag_state_names = state_names(tagging_model)
    isempty(tag_state_names) && error(
        "`$config_key` needs at least one `$tracer_key` entry that has a \
        `region` and no `source`. Closure is the sum of those tags against the \
        field they partition; a tag carrying a `source` starts at zero and is \
        not part of the partition.",
    )
    period_seconds = time_to_seconds(check.period)
    if !isnothing(checkpoint_frequency) && checkpoint_frequency != Inf
        rounded_period = Dates.Second(round(Int, period_seconds))
        isdivisible(checkpoint_frequency, rounded_period) || @warn(
            "`$config_key` period ($rounded_period) is not an even divisor of \
            the checkpoint frequency ($checkpoint_frequency); the closure \
            table will contain duplicated rows after a restart."
        )
    end

    period = ITime(period_seconds)
    period, _, _, _ = promote(period, t_start, dt, t_end)

    # A check with a reference at spin-up takes the residual once, at the
    # spin-up time, and every row reports the residual since. That callback comes first,
    # so that a row due at the same time already has the reference.
    spin_up = get(check, :spin_up, nothing)
    reference = isnothing(spin_up) ? nothing : Ref{Any}(nothing)
    # Past the void level every later row is marked `closure_void`. The flag
    # lives in the cache, not here, so that a checkpoint carries it through a
    # restart (`tag_closure_checkpoint.jl`).
    void_above = get(check, :void_above, nothing)
    family_key = Symbol(family)
    # The energy source tags' second warning level, against the source
    # throughput.
    throughput_tolerance = get(check, :throughput_tolerance, nothing)
    # The water check also reads the parent's negative water. Its flag lives in
    # the cache for the same reason. Its accumulator sits in the tags' step
    # cache, beside their ledgers.
    negative_water_void_above = get(check, :negative_water_void_above, nothing)
    negative_water(p) =
        reads_negative_water ?
        (;
            void_above = negative_water_void_above,
            voided = negative_water_voided(p, family_key),
            accumulator = negative_water_accumulator(p.tagging),
        ) : nothing
    affect!(integrator) = tag_closure_callback!(
        integrator,
        output_dir,
        family,
        total_name,
        tag_state_names,
        check.tolerance,
        check.abort_above,
        check.audit;
        reference,
        extra_audit,
        extra_closure,
        void_above,
        voided = tag_closure_voided(integrator.p, family_key),
        throughput_tolerance,
        negative_water = negative_water(integrator.p),
    )
    periodic = call_every_dt(affect!, period)
    isnothing(spin_up) && return (periodic,)
    spin_up_time = ITime(time_to_seconds(spin_up))
    spin_up_time, _, _, _ = promote(spin_up_time, t_start, dt, t_end)
    reference_affect!(integrator) = take_tag_closure_reference!(
        integrator,
        reference,
        total_name,
        tag_state_names,
    )
    return (
        call_every_dt(reference_affect!, spin_up_time; skip_first = true),
        periodic,
    )
end
