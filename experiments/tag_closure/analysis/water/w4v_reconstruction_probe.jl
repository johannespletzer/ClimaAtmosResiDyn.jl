# WP4a-V (design/ZERO_M_RECONSTRUCTION_CHECK.md): on a copies run's own state,
# after every step, the rain-weighted error of the grid rule's and the default
# mode's reconstructed subdomain shares against the copies' own.
#
#   LABEL=base DT=150 ZELEM=82 NEWTON=10 OUTDIR=... \
#       julia --project=<env at WP4a's code> w4v_reconstruction_probe.jl
#
# It runs W26's TRMM 0M copies column (`configs/w4a_trmm0m_copies_6h.yml`,
# without its diagnostics) at the rung's `dt`, levels and Newton iterations, the
# copies started from the default mode's plume as the D4-W driver starts them.
# After each step, for each tag `i` and subdomain `k` (updraft j, environment 0):
#   grid     φ̄ᵢ = water_tag_fraction(ρq_tagᵢ, ρq_tot);
#   recon    #104's `SplitShare` on the plume and share differences that
#            `water_exchange_inputs!` and `ShareDifferences` give for the run's
#            grid tags, as the default mode's split takes them;
#   ref      the copies' shares, as #104's copies split takes them.
# and the column integrals of |Δᵏ| |φ_cand − φ_ref| and of |Δᵏ|. It writes them
# per step to OUTDIR/<run>.csv and prints E_grid and E_recon per tag over the
# run and over hours 3 to 6, with the exchange's activity and the repairs.
import ClimaAtmos as CA
import YAML
const lazy = CA.lazy

label = get(ENV, "LABEL", "base")
dt = parse(Int, get(ENV, "DT", "150"))
z_elem = parse(Int, get(ENV, "ZELEM", "82"))
newton = parse(Int, get(ENV, "NEWTON", "10"))
outdir = get(ENV, "OUTDIR", pwd())
mkpath(outdir)
here = @__DIR__
dict = Dict{String, Any}(
    YAML.load_file(joinpath(here, "..", "..", "configs", "w4a_trmm0m_copies_6h.yml")),
)
dict["diagnostics"] = []
dict["toml"] = [joinpath(pkgdir(CA), path) for path in dict["toml"]]
dict["output_dir"] = mktempdir(pwd())
dict["dt"] = "$(dt)secs"
dict["z_elem"] = z_elem
dict["max_newton_iters_ode"] = newton
# A shorter run, for a smoke test of the probe only.
haskey(ENV, "T_END") && (dict["t_end"] = ENV["T_END"])
run_name = "w4v_$(label)"
simulation = CA.get_simulation(CA.AtmosConfig(dict; job_id = run_name))
integrator = simulation.integrator
Y = integrator.u
p = integrator.p
model = p.atmos.water_tagging_model
turbconv_model = p.atmos.turbconv_model
@assert CA.has_water_tag_updraft_copies(model)
CA.start_water_tag_copies_from_plume!(Y, p)
CA.set_precomputed_quantities!(Y, p, integrator.t)
@info "probing" run_name dt z_elem newton

# The default mode's exchange scratch, which a copies run does not allocate,
# next to the run's own cache in a proxy that the exchange's inputs read.
FT = eltype(Y.c.ρ)
tag_values() = CA.Fields.Field(NTuple{length(model.tags), FT}, axes(Y.c))
extra = (;
    ᶠq_tag_sgs_flux = CA.Fields.Field(CA.ClimaCore.Geometry.Contravariant3Vector{FT}, axes(Y.f)),
    ᶜq_tag_mean = tag_values(),
    ᶜq_tag_plume = tag_values(),
    ᶜq_tag_environment = tag_values(),
    ᶜq_tag_environment_density = similar(Y.c.ρ),
    ᶜq_tag_room = similar(Y.c.ρ),
    ᶜq_tag_water_ratio = similar(Y.c.ρ),
)
proxy = (;
    atmos = p.atmos,
    params = p.params,
    precomputed = p.precomputed,
    core = p.core,
    numerics = p.numerics,
    dt = p.dt,
    scratch = merge(p.scratch, extra),
)
partition_of(::Val{P}) where {P} = P
tags = model.tags
names = map(CA.tag_name, tags)
column(ᶜx) = (
    out = similar(p.scratch.ᶠtemp_field_level);
    CA.Operators.column_integral_definite!(out, ᶜx);
    only(parent(out))
)
# Where the exchange is off (no room, no water) or its bound binds.
function exchange_state(ε̄, εʲ, room, ratio, partition)
    total = CA._partition_total(ε̄, partition)
    totalʲ = CA._partition_total(εʲ, partition)
    off = (room < 0) | (ratio <= 0) | (total <= 0) | (totalʲ <= 0)
    off && return 0
    θ = CA._partition_blend_factor(ε̄, εʲ, total, totalʲ, room, partition)
    return θ < 1 ? 2 : 1
end

t_end = CA.time_to_seconds(dict["t_end"])
header = ["t_seconds", "weight", "off_weight", "binding_weight"]
for name in names
    append!(header, ["grid_$(name)", "recon_$(name)", "ref_n2_$(name)"])
end
rows = Vector{Vector{Float64}}()
ᶜstate = similar(Y.c.ρ)
ᶜnorm⁰ = similar(Y.c.ρ)
while CA.time_to_seconds(integrator.t) < t_end - 1e-6
    CA.CTS.step!(integrator)
    ᶜΔʲ = CA._rainout_updraft(Y, p)
    ᶜΔ⁰ = CA._rainout_environment(Y, p)
    ᶜw = @. lazy(abs(ᶜΔʲ) + abs(ᶜΔ⁰))
    weight = column(ᶜw)
    CA.water_tag_share_norm!(p, Y)
    ᶜS = p.scratch.ᶜtagging_q_share_norm
    inputs = CA.water_exchange_inputs!(Y, proxy, turbconv_model, model)
    (; ᶜεʲ, ᶜε̄, ᶜroom, ᶜwater_ratio, flags) = inputs
    partition = partition_of(flags)
    ᶜΔφ⁰ = CA.ShareDifferences(flags, true).(ᶜεʲ, ᶜε̄, ᶜroom, ᶜwater_ratio)
    ᶜΔφʲ = CA.ShareDifferences(flags, false).(ᶜεʲ, ᶜε̄, ᶜroom, ᶜwater_ratio)
    @. ᶜstate = exchange_state(ᶜε̄, ᶜεʲ, ᶜroom, ᶜwater_ratio, $(Ref(partition)))
    ᶜoff = @. lazy(ifelse(ᶜstate == 0, ᶜw, zero(ᶜw)))
    ᶜbinding = @. lazy(ifelse(ᶜstate == 2, ᶜw, zero(ᶜw)))
    off_weight = column(ᶜoff)
    binding_weight = column(ᶜbinding)
    # The copies' environment norm over the partition, as the copies' split
    # renormalizes by.
    ᶜsgsʲ = Y.c.sgsʲs.:(1)
    ᶜq_tot⁰ = CA.ᶜspecific_env_value(CA.MatrixFields.@name(q_tot), Y, p)
    ᶜnorm⁰ .= 0
    for tag in tags
        CA._is_partition_tag(tag) || continue
        ᶜχ⁰ = CA.ᶜspecific_env_value(CA.water_tag_copy_field_name(tag), Y, p)
        @. ᶜnorm⁰ += CA.water_tag_fraction(ᶜχ⁰, ᶜq_tot⁰)
    end
    row = [CA.time_to_seconds(integrator.t), weight, off_weight, binding_weight]
    for (i, tag) in enumerate(tags)
        share = CA.SplitShare(flags, Val(i))
        ᶜρq_tag = CA.tag_field(Y.c, tag)
        ᶜφ̄ = @. lazy(CA.water_tag_fraction(ᶜρq_tag, Y.c.ρq_tot))
        ᶜrecʲ = @. lazy(share(ᶜε̄, ᶜΔφʲ, ᶜS, ᶜφ̄))
        ᶜrec⁰ = @. lazy(share(ᶜε̄, ᶜΔφ⁰, ᶜS, ᶜφ̄))
        ᶜχʲ = CA.updraft_copy_field(ᶜsgsʲ, tag)
        ᶜχ⁰ = CA.ᶜspecific_env_value(CA.water_tag_copy_field_name(tag), Y, p)
        ᶜrefʲ = @. lazy(CA.water_tag_fraction(ᶜχʲ, ᶜsgsʲ.q_tot))
        ᶜref⁰ =
            CA._is_partition_tag(tag) ?
            (@. lazy(
                ifelse(
                    ᶜnorm⁰ > 0,
                    ᶜS * CA.water_tag_fraction(ᶜχ⁰, ᶜq_tot⁰) / ᶜnorm⁰,
                    ᶜφ̄,
                ),
            )) : (@. lazy(CA.water_tag_fraction(ᶜχ⁰, ᶜq_tot⁰)))
        ᶜgrid_error =
            @. lazy(abs(ᶜΔʲ) * abs(ᶜφ̄ - ᶜrefʲ) + abs(ᶜΔ⁰) * abs(ᶜφ̄ - ᶜref⁰))
        ᶜrecon_error = @. lazy(
            abs(ᶜΔʲ) * abs(ᶜrecʲ - ᶜrefʲ) + abs(ᶜΔ⁰) * abs(ᶜrec⁰ - ᶜref⁰)
        )
        # The reference's own shares, to set against the other rungs'.
        ᶜref_share = @. lazy(abs(ᶜΔʲ) * ᶜrefʲ + abs(ᶜΔ⁰) * ᶜref⁰)
        grid = column(ᶜgrid_error)
        recon = column(ᶜrecon_error)
        refsum = column(ᶜref_share)
        append!(row, [grid, recon, refsum])
    end
    push!(rows, row)
end

open(joinpath(outdir, "$run_name.csv"), "w") do io
    println(io, join(header, ","))
    for row in rows
        println(io, join(repr.(row), ","))
    end
end
function report(selected, what)
    weight = sum(row[2] for row in selected)
    for (i, name) in enumerate(names)
        grid = sum(row[4 + 3(i - 1) + 1] for row in selected) / weight
        recon = sum(row[4 + 3(i - 1) + 2] for row in selected) / weight
        println(
            "RESULT run=$run_name $what tag=$name E_grid=$grid E_recon=$recon " *
            "ratio=$(recon / grid)",
        )
    end
    off = sum(row[3] for row in selected) / weight
    binding = sum(row[4] for row in selected) / weight
    println("RESULT run=$run_name $what exchange_off_fraction=$off bound_binding_fraction=$binding")
end
report(rows, "all")
report(filter(row -> row[1] > 3 * 3600, rows), "hours3to6")
closure = CA.tag_closure(Y, p, :ρq_tot, CA.water_region_tag_state_names(model))
repair = sum(
    sum(abs, parent(getproperty(p.tagging.ᶜwater_fix, name))) for
    name in CA.water_region_tag_state_names(model)
)
ᶜsgsʲ = Y.c.sgsʲs.:(1)
ᶜcopy_sum = zero.(ᶜsgsʲ.q_tot)
for tag in tags
    CA._is_partition_tag(tag) && (ᶜcopy_sum .+= CA.updraft_copy_field(ᶜsgsʲ, tag))
end
ᶜcopy_error = @. lazy(abs(ᶜsgsʲ.ρa * (ᶜcopy_sum - ᶜsgsʲ.q_tot)))
ᶜcopy_water = @. lazy(abs(ᶜsgsʲ.ρa * ᶜsgsʲ.q_tot))
copy_residual = column(ᶜcopy_error) / max(column(ᶜcopy_water), eps(FT))
println(
    "RESULT run=$run_name closure_gross=$(closure.gross_relative) " *
    "partition_repair=$(repair / closure.scale) copies_residual_final=$copy_residual steps=$(length(rows))",
)
