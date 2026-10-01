#=
C's revision, 11.11.11 item 5: the autodiff Jacobians, tags on and off.

    julia --project=<env with ClimaAtmos at the model commit> cr_autodiff_parity.jl

Optional: `CREV_AD_CASES` (default `sparse,dense`) and `CREV_AD_STEPS` (default 6).

It builds the integration column of `test/tagged_water_integration.jl` (the
restart testset's `test_dict`: tags `upper`, `lower`, `evap`, the closure check,
and `water_tag_transport: increment`) with

  - `sparse`: `use_auto_jacobian: true`, `z_elem` 30, the band below zero is the
    bottom 5 cells;
  - `dense`: `use_dense_jacobian: true`, `z_elem` 10 as in the CI's dense
    configurations, the band is the bottom 3 cells.

For each case it runs a tagged simulation and one without the tags in lockstep,
step by step. Before the first step the parent's water in the band is made
negative (`ρq_tot = -ρq_tot / 2`), as the band parity test does, so that the
rule acts: the surface flux brings water into the bottom cell, the rule
withholds that gain from the tags, and the ledger `q_tag_exp_negative` takes it.

After every step it compares every model field of the two runs with `isequal`.
A field that differs only in the sign of a zero is reported apart, with the
number of cells. It also checks that every tag field and every ledger is
finite, and reports `∫n' dz` where the rule acted: `n'` is the follower's
negative part after the stage (`n + δL - g`, 11.11.3), which the cache keeps for
the last implicit stage of the step. The integral is `sum` over the column, the
same as the probe drivers' `sum` (weights are the cells' heights).

`implicit_tendency!` runs on duals inside the Jacobian: a run that completes
with the tags has evaluated the bracket on them. The exit status is 1 if any
model field differs (signed zero included), any tag or ledger is not finite, or
the rule never acted, or the cache has no `n'` (the tags run `water_tag_transport:
increment`, so the follower is exercised). Lines start with `CREV_AD`.
=#
using Printf
import ClimaComms
ClimaComms.@import_required_backends
import ClimaAtmos as CA

# The test's regions, the same partition of unity.
upper_region() = Dict{String, Any}(
    "type" => "tanh_altitude",
    "z_center" => 600.0,
    "width" => 100.0,
)
lower_region() = merge(upper_region(), Dict{String, Any}("above" => false))

base_config(tags; extra = Dict{String, Any}()) = merge(
    Dict{String, Any}(
        "config" => "column",
        "initial_condition" => "DYCOMS_RF02",
        "z_max" => 1500.0,
        "z_elem" => 30,
        "z_stretch" => false,
        "microphysics_model" => "0M",
        "dt" => "10secs",
        "t_end" => "100secs",
        "FLOAT_TYPE" => "Float64",
        "output_default_diagnostics" => false,
        "water_tracers" => tags,
        # The follower: it keeps `ᶜq_tag_negative_change` (n') in the cache.
        "water_tag_transport" => "increment",
    ),
    extra,
)

const CASES = Dict(
    "sparse" => (;
        z_elem = 30,
        band = 1:5,
        jacobian = Dict{String, Any}("use_auto_jacobian" => true),
    ),
    "dense" => (;
        z_elem = 10,
        band = 1:3,
        jacobian = Dict{String, Any}("use_dense_jacobian" => true),
    ),
)
const STEPS = parse(Int, get(ENV, "CREV_AD_STEPS", "6"))
const CASE_NAMES = split(get(ENV, "CREV_AD_CASES", "sparse,dense"), ",")

tags() = [
    Dict{String, Any}("name" => "upper", "region" => upper_region()),
    Dict{String, Any}("name" => "lower", "region" => lower_region()),
    Dict{String, Any}("name" => "evap", "source" => "surface_flux"),
]

function dicts(case)
    closure_check = Dict{String, Any}(
        "period" => "10secs",
        "void_above" => 1.0e-30,
        "audit" => true,
    )
    extra = merge(
        Dict{String, Any}(
            "t_end" => "$(10 * STEPS)secs",
            "z_elem" => case.z_elem,
            "water_closure_check" => closure_check,
        ),
        case.jacobian,
    )
    tagged = base_config(tags(); extra)
    plain = filter(
        e -> !(first(e) in ("water_tracers", "water_closure_check", "water_tag_transport")),
        tagged,
    )
    return tagged, plain
end

function build(dict, job_id)
    config = CA.AtmosConfig(
        merge(dict, Dict{String, Any}("output_dir" => mktempdir(pwd())));
        job_id,
    )
    println(
        "CREV_AD $job_id jacobian ",
        nameof(typeof(CA.jacobian_from_parsed_args(config.parsed_args))),
    )
    return CA.get_simulation(config)
end

column_values(field) = vec(Array(parent(field)))

# `:identical` (isequal), `:signed_zero` (equal, but a zero has the other
# sign) or `:differs`, with the number of cells that differ and the largest
# absolute difference.
function compare(a, b)
    x, y = column_values(a), column_values(b)
    isequal(x, y) && return (:identical, 0, 0.0)
    differ = [i for i in eachindex(x) if !isequal(x[i], y[i])]
    signed_zero = count(i -> x[i] == y[i], differ)
    largest = maximum(abs(x[i] - y[i]) for i in differ if !isnan(x[i] - y[i]); init = 0.0)
    verdict = signed_zero == length(differ) ? :signed_zero : :differs
    return (verdict, length(differ), largest)
end

function model_fields(Y)
    (; c = propertynames(Y.c), f = propertynames(Y.f))
end

function run_case(label)
    case = CASES[label]
    tagged_dict, plain_dict = dicts(case)
    tagged = build(tagged_dict, "crev_ad_$(label)_tags")
    plain = build(plain_dict, "crev_ad_$(label)_plain")
    Y = tagged.integrator.u
    Y_plain = plain.integrator.u
    band = case.band
    # The band below zero in both runs, as the band parity test does.
    for sim in (tagged, plain)
        water = parent(sim.integrator.u.c.ρq_tot)
        water[band] .= .-water[band] ./ 2
    end
    # The tags' own fields: what the tagged run has and the plain one has not.
    tag_only = [name for name in propertynames(Y.c) if !hasproperty(Y_plain.c, name)]
    println("CREV_AD $label tag and ledger fields: ", join(tag_only, " "))
    @assert hasproperty(Y.c, :q_tag_exp_negative)
    @assert propertynames(Y.f) == propertynames(Y_plain.f)
    has_n = hasproperty(tagged.integrator.p.tagging, :ᶜq_tag_negative_change)
    has_n || println(
        "CREV_AD $label: FAIL, the cache has no ᶜq_tag_negative_change; ",
        "the follower is not exercised",
    )
    ok = has_n
    L_before = 0.0
    acted_steps = Int[]
    n_at_acted = Float64[]
    L_total = Float64[]
    for step in 1:STEPS
        CA.CTS.step!(tagged.integrator)
        CA.CTS.step!(plain.integrator)
        t = Float64(tagged.integrator.t)
        @assert Float64(plain.integrator.t) == t
        # Every model field, both spaces.
        differing = String[]
        signed = String[]
        for (space, names) in pairs(model_fields(Y_plain))
            for name in names
                a = getproperty(getproperty(Y, space), name)
                b = getproperty(getproperty(Y_plain, space), name)
                verdict, n, largest = compare(a, b)
                verdict == :identical && continue
                entry = @sprintf("%s.%s (%d cells, largest %.3e)", space, name, n, largest)
                push!(verdict == :signed_zero ? signed : differing, entry)
            end
        end
        finite = all(tag_only) do name
            all(isfinite, parent(getproperty(Y.c, name)))
        end
        L = column_values(Y.c.q_tag_exp_negative)
        L_sum = Float64(sum(Y.c.q_tag_exp_negative))
        acted = L_sum > L_before
        L_before = L_sum
        n_sum =
            has_n ? Float64(sum(tagged.integrator.p.tagging.ᶜq_tag_negative_change)) : NaN
        if acted
            push!(acted_steps, step)
            push!(n_at_acted, n_sum)
        end
        push!(L_total, L_sum)
        band_negative = all(<(0), column_values(Y_plain.c.ρq_tot)[band])
        @printf(
            "CREV_AD %s step %d t=%.1f: fields %s; signed-zero only: %s; finite tags and ledgers: %s; band below zero (plain): %s; ∫L dz = %.6e (acted: %s), ∫n' dz = %.6e, L[1] = %.6e\n",
            label,
            step,
            t,
            isempty(differing) ? "all isequal" : "DIFFER " * join(differing, "; "),
            isempty(signed) ? "none" : join(signed, "; "),
            finite,
            band_negative,
            L_sum,
            acted,
            n_sum,
            L[1],
        )
        ok &= isempty(differing) && isempty(signed) && finite
        # Where the rule acted, n' must have been computed and be finite.
        ok &= !acted || isfinite(n_sum)
    end
    ok &= !isempty(acted_steps)
    println(
        "CREV_AD $label summary: the rule acted in ",
        length(acted_steps),
        " of ",
        STEPS,
        " steps; ∫n' dz where it acted: ",
        isempty(n_at_acted) ? "none" :
        @sprintf("min %.6e, max %.6e", minimum(n_at_acted), maximum(n_at_acted)),
        "; final ∫L dz = ",
        L_total[end],
        "; every model field isequal at every step: ",
        ok,
    )
    return ok
end

function main()
    results = Dict(label => run_case(label) for label in CASE_NAMES)
    for label in CASE_NAMES
        println("CREV_AD RESULT $label: ", results[label] ? "PASS" : "FAIL")
    end
    all(values(results)) || exit(1)
end

main()
