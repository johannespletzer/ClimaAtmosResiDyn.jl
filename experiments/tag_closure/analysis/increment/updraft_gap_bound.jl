#=
A bound on the updraft gap (UPDRAFT_GAP.md) from a sphere run's daily
checkpoints. No new run is needed.

    julia --project=<the run's .buildkite> updraft_gap_bound.jl <run> [offset] [days]

The energy source tags have no copy in the updraft. So the sub-grid mass flux
moves each tag by the share it has in the cell the flux leaves, while the
updraft itself carries air from lower down. This script estimates what an
updraft copy would add, per tag, and sets it against the tags' own daily
change. It is an estimate:

  - the mass flux is `M = ρaʲ (wʲ - w)` on faces, with the updraft's density
    taken as the grid mean's;
  - the fraction `f` of surface air left in the updraft at each level comes
    from the mixing line of `q_tot`: the updraft at a level is taken as a
    mixture of the updraft at the lowest level and the environment there;
  - the updraft's share of tag `k` is then `φʲ = f φ(lowest level) + (1 - f) φ`;
  - the gap's flux is `M (φʲ - φ) e`, with `e = E/ρ` the grid mean's specific
    total, taken from the cell the flux leaves. Its divergence is the gap's
    tendency of the tag. It sums to zero over the partition.

It prints, per day: the mass flux's turnover of the air below 10 km, the
fraction of surface air in the updraft, and per tag the part of the tag the
gap would move in a day against the part it actually changed that day, for
the tropics (|lat| < 30°) and elsewhere.
=#
import ClimaAtmos as CA
import ClimaComms
import ClimaCore: InputOutput, Fields, Geometry, Spaces
import Statistics: median

const ROOT = "/dss/dsstbyfs02/scratch/0D/di38kez/tag_closure/output"
const TAGS = (:tropics, :extratropics, :sfc, :rad, :new_tropics, :new_extratropics)

function read_state(run, day)
    dir = last(sort(filter(isdir, readdir(joinpath(ROOT, run); join = true))))
    path = joinpath(dir, "day$(day).0.hdf5")
    isfile(path) || return nothing
    reader = InputOutput.HDF5Reader(path, ClimaComms.SingletonCommsContext())
    Y = InputOutput.read_field(reader, "Y")
    close(reader)
    return Y
end

# The gap's tendency of one tag, and the fields it is built from.
function gap_tendency(Y, c, name)
    FT = eltype(Y)
    ρ = Y.c.ρ
    ρa = Y.c.sgsʲs.:(1).ρa
    ᶜE = @. Y.c.ρe_tot + c * ρ
    ᶜe = @. ᶜE / ρ
    ᶜtag = getproperty(Y.c, name)
    ᶜφ = @. ᶜtag / ᶜE
    # The fraction of surface air in the updraft, from `q_tot`'s mixing line.
    qʲ = Y.c.sgsʲs.:(1).q_tot
    q = @. Y.c.ρq_tot / ρ
    q_env = @. (Y.c.ρq_tot - ρa * qʲ) / max(ρ - ρa, eps(FT) * ρ)
    qʲ_bottom = Fields.level(qʲ, 1)
    φ_bottom = Fields.level(ᶜφ, 1)
    ᶜf = @. ifelse(
        (ρa > 1e-3 * ρ) & (abs(qʲ_bottom - q_env) > 1e-6),
        clamp((qʲ - q_env) / (qʲ_bottom - q_env), FT(0), FT(1)),
        FT(0),
    )
    ᶜδφ = @. ᶜf * (φ_bottom - ᶜφ)
    # The mass flux on faces, upward positive, zero where there is no updraft.
    ᶠw = Geometry.WVector.(Y.f.u₃)
    ᶠwʲ = Geometry.WVector.(Y.f.sgsʲs.:(1).u₃)
    ᶠM = @. CA.ᶠinterp(ρa) * (ᶠwʲ.components.data.:1 - ᶠw.components.data.:1)
    # The gap's flux takes `δφ · e` from the cell it leaves.
    ᶠflux = @. CA.ᶠupwind1(CA.CT3(Geometry.WVector(ᶠM)), ᶜδφ * ᶜe)
    ᶜtendency = @. -CA.ᶜadvdivᵥ(ᶠflux)
    return (; ᶜtendency, ᶜf, ᶠM, ᶜE)
end

function main(run, c, days)
    for day in days
        Y = read_state(run, day)
        Y_next = read_state(run, day + 1)
        (isnothing(Y) || isnothing(Y_next)) && continue
        FT = eltype(Y)
        lat = Fields.coordinate_field(Y.c).lat
        z = Fields.coordinate_field(Y.c).z
        tropics = @. ifelse(abs(lat) < 30, one(FT), zero(FT))
        elsewhere = @. one(FT) - tropics
        below_10km = @. ifelse(z < 10000, one(FT), zero(FT))

        # The turnover of the air below 10 km by the mass flux: the column's
        # mass there over the largest upward mass flux in the column.
        (; ᶜf, ᶠM) = gap_tendency(Y, FT(c), :ρe_src_sfc)
        column_mass = zeros(axes(Fields.level(Y.f, CA.half)))
        CA.Operators.column_integral_definite!(column_mass, @. Y.c.ρ * below_10km)
        M = parent(ᶠM)
        M_max = dropdims(maximum(max.(M, 0); dims = 1); dims = 1)
        turnover_days = vec(parent(column_mass)) ./ max.(vec(M_max), 1e-12) ./ 86400
        f_values = filter(>(0), vec(parent(ᶜf)))
        println("== $run, day $day")
        println(
            "  turnover of the air below 10 km by the mass flux, days: ",
            "median $(round(median(turnover_days), sigdigits = 3)), ",
            "10th percentile $(round(sort(turnover_days)[max(1, length(turnover_days) ÷ 10)], sigdigits = 3)); ",
            "columns under 1 day: $(round(100 * count(<(1), turnover_days) / length(turnover_days), digits = 1))%",
        )
        isempty(f_values) || println(
            "  surface air in the updraft, where there is one: median f $(round(median(f_values), digits = 3))",
        )

        println("  per tag: the part it would move in a day, against the part it changed (tropics | elsewhere)")
        for tag in TAGS
            name = Symbol(:ρe_src_, tag)
            hasproperty(Y.c, name) || continue
            (; ᶜtendency) = gap_tendency(Y, FT(c), name)
            ᶜtag = getproperty(Y.c, name)
            # The next day's state is read with spaces of its own, so the two
            # are compared by their data.
            ᶜchange = similar(ᶜtag)
            parent(ᶜchange) .= parent(getproperty(Y_next.c, name)) .- parent(ᶜtag)
            parts = map((tropics, elsewhere)) do mask
                amount = sum(@. abs(ᶜtag) * mask)
                moved = sum(@. abs(ᶜtendency) * mask) * 86400
                changed = sum(@. abs(ᶜchange) * mask)
                amount > 0 ? (moved / amount, changed / amount) : (NaN, NaN)
            end
            println(
                "    $(rpad(tag, 17)) gap $(round(parts[1][1], sigdigits = 3)), changed $(round(parts[1][2], sigdigits = 3))",
                " | gap $(round(parts[2][1], sigdigits = 3)), changed $(round(parts[2][2], sigdigits = 3))",
            )
        end
    end
end

run = length(ARGS) >= 1 ? ARGS[1] : "g2_v2_sphere"
offset = length(ARGS) >= 2 ? parse(Float64, ARGS[2]) : 110495.0
days = length(ARGS) >= 3 ? eval(Meta.parse(ARGS[3])) : 1:9
main(run, offset, days)
