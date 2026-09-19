#=
An estimate of the updraft gap (UPDRAFT_GAP.md) from a sphere run's daily
checkpoints. No new run is needed.

    julia --project=<the run's .buildkite> updraft_gap_estimate.jl <run> [offset] [first:last day]

The energy source tags have no copy in the updraft. So the sub-grid mass flux
moves each tag by the share it has in the cell the flux leaves, while the
updraft itself carries air from lower down. This script estimates the rate at
which an updraft copy of the tags would start to differ from them, on the
state of each checkpoint. It is an initial rate, not a bound, and it cannot be
added up over days: a copy would re-mix the lowest levels within a day or two.
Reviewed on 2026-09-19 (claude_work/updraft_gap/review/review_bound.md).

With one updraft of mass fraction `σ = ρaʲ/ρ` and mass flux
`M = ρaʲ (wʲ - w)`, the flux a copy would add to tag `k`, beyond what the
donor sharing moves, is `M (φʲ - φ) eʲ / (1 - σ)` (the review, section 1).
Here:

  - `φ` is the tag's share of `E`, the partition's normalised by their sum as
    the model does, and `eʲ ≈ e = E/ρ`, within 1 to 3% in the tropics;
  - `φʲ = f φ(lowest level) + (1 - f) φ` is the updraft's share, with `f` the
    fraction of air from the lowest level in the updraft, from the mixing line
    of `q_tot` between the updraft at the lowest level and the environment.
    Points off the line (`f` outside 0 to 1) and levels where rain and snow
    are more than 10% of the updraft's water are left out;
  - the face value is taken two ways, as a bracket: upwind, and centred as the
    model's own sub-grid flux is under `edmfx_sgsflux_upwinding: none`. With
    the updraft two to four cells deep, the two differ by a factor of 2 to 4.

It prints per day, for the tropics (|lat| < 30°) and elsewhere:

  - the fraction of each tag relocated in a day, `½∫|tendency| / ∫|tag|`;
  - the fraction of each tag below the face nearest 1.5 km that the gap would
    lift above it in a day;
  - how fast the gap would raise the tag's centroid, in m a day, against how
    far the centroid actually moved to the next checkpoint;
  - the updraft's depth, the turnover of the air below its top by the mass
    flux (area-weighted), and `f` per level, weighted by `M`.
=#
import ClimaAtmos as CA
import ClimaComms
import ClimaCore: InputOutput, Fields, Geometry, Spaces, Operators

const ROOT = "/dss/dsstbyfs02/scratch/0D/di38kez/tag_closure/output"
const TAGS = (:tropics, :extratropics, :sfc, :rad, :new_tropics, :new_extratropics)
const PARTITION = (:tropics, :extratropics)

# A day's checkpoint, from any of the run's output directories.
function read_state(run, day)
    for dir in reverse(sort(filter(isdir, readdir(joinpath(ROOT, run); join = true))))
        path = joinpath(dir, "day$(day).0.hdf5")
        isfile(path) || continue
        reader = InputOutput.HDF5Reader(path, ClimaComms.SingletonCommsContext())
        Y = InputOutput.read_field(reader, "Y")
        close(reader)
        return Y
    end
    @warn "No checkpoint for day $day of $run"
    return nothing
end

# The mixing fraction, the mass flux and the tag's gap tendencies (upwind and
# centred), for one tag.
function gap(Y, c, tag)
    FT = eltype(Y)
    ρ = Y.c.ρ
    ρa = Y.c.sgsʲs.:(1).ρa
    σ = @. ρa / ρ
    ᶜE = @. Y.c.ρe_tot + c * ρ
    ᶜe = @. ᶜE / ρ
    ᶜtag = getproperty(Y.c, Symbol(:ρe_src_, tag))
    if tag in PARTITION
        ᶜsum = zero.(ρ)
        for name in PARTITION
            ᶜpart = getproperty(Y.c, Symbol(:ρe_src_, name))
            @. ᶜsum += ᶜpart
        end
        ᶜφ = @. ᶜtag / ᶜsum
    else
        ᶜφ = @. ᶜtag / ᶜE
    end
    # The mixing line of `q_tot`, left out off the line and where it rains.
    qʲ = Y.c.sgsʲs.:(1).q_tot
    precipitation = @. Y.c.sgsʲs.:(1).q_rai + Y.c.sgsʲs.:(1).q_sno
    q_env = @. (Y.c.ρq_tot - ρa * qʲ) / max(ρ - ρa, eps(FT) * ρ)
    qʲ_bottom = Fields.level(qʲ, 1)
    φ_bottom = Fields.level(ᶜφ, 1)
    ᶜraw = @. ifelse(
        abs(qʲ_bottom - q_env) > FT(1e-6),
        (qʲ - q_env) / (qʲ_bottom - q_env),
        FT(NaN),
    )
    ᶜused = @. (σ > FT(1e-3)) & (ᶜraw >= 0) & (ᶜraw <= 1) &
       (precipitation <= FT(0.1) * max(qʲ, eps(FT)))
    ᶜf = @. ifelse(ᶜused, ᶜraw, FT(0))
    ᶜχ = @. ᶜf * (φ_bottom - ᶜφ) * ᶜe / (1 - σ)
    ᶠw = Geometry.WVector.(Y.f.u₃)
    ᶠwʲ = Geometry.WVector.(Y.f.sgsʲs.:(1).u₃)
    ᶠM = @. CA.ᶠinterp(ρa) * (ᶠwʲ.components.data.:1 - ᶠw.components.data.:1)
    ᶠM³ = @. CA.CT3(Geometry.WVector(ᶠM))
    ᶠupwind = @. CA.ᶠupwind1(ᶠM³, ᶜχ)
    ᶠcentred = @. ᶠM³ * CA.ᶠinterp(ᶜχ)
    return (;
        ᶜtag,
        ᶜf,
        ᶜraw,
        ᶜused,
        σ,
        ᶠM,
        ᶠupwind,
        ᶠcentred,
        upwind = (@. -CA.ᶜadvdivᵥ(ᶠupwind)),
        centred = (@. -CA.ᶜadvdivᵥ(ᶠcentred)),
    )
end

# The tag's centroid height over a region, `∫ z·tag / ∫ tag`.
centroid(ᶜtag, ᶜz, mask) = sum(@. ᶜz * ᶜtag * mask) / sum(@. ᶜtag * mask)

function day_report(run, c, day)
    Y = read_state(run, day)
    Y_next = read_state(run, day + 1)
    (isnothing(Y) || isnothing(Y_next)) && return nothing
    FT = eltype(Y)
    coordinates = Fields.coordinate_field(Y.c)
    ᶜz = coordinates.z
    ᶠz = Fields.coordinate_field(Y.f).z
    tropics = @. ifelse(abs(coordinates.lat) < 30, one(FT), zero(FT))
    regions = (("tropics", tropics), ("elsewhere", @. one(FT) - tropics))
    println("== $run, day $day")

    # The updraft: its top, the turnover below it, and f per level.
    (; ᶠM, ᶜf, ᶜraw, σ) = gap(Y, FT(c), :sfc)
    M = parent(ᶠM)
    M_max = dropdims(maximum(max.(M, 0); dims = 1); dims = 1)
    top_face = map(CartesianIndices(M_max)) do index
        column = max.(M[:, index], 0)
        something(findlast(>(0.01 * M_max[index]), column), 1)
    end
    ρ = parent(Y.c.ρ)
    Δz = parent(Fields.Δz_field(Y.c))
    zf = parent(ᶠz)
    area = parent(Fields.local_geometry_field(Fields.level(Y.c, 1)).WJ)
    tropical = parent(Fields.level(tropics, 1)) .> 0
    for (label, in_region) in (("tropics", tropical), ("elsewhere", .!tropical))
        turnover = Float64[]
        weights = Float64[]
        depth = Float64[]
        for index in CartesianIndices(M_max)
            in_region[1, index] || continue
            M_max[index] > 1e-6 || continue
            k = top_face[index]
            mass = sum(ρ[1:(k - 1), index] .* Δz[1:(k - 1), index])
            push!(turnover, mass / M_max[index] / 86400)
            push!(weights, area[1, index])
            push!(depth, zf[k, index])
        end
        isempty(turnover) && continue
        fast = sum(weights[turnover .< 1]) / sum(area[1, :, :, 1, :][in_region[1, :, :, 1, :]])
        println(
            "  $label: updraft top, area-weighted mean $(round(sum(depth .* weights) / sum(weights), sigdigits = 3)) m; ",
            "area whose air below the top turns over within a day: $(round(100 * fast, digits = 1))%",
        )
    end
    f = parent(ᶜf)
    raw = parent(ᶜraw)
    s = parent(σ)
    Mc = 0.5 .* (max.(M[1:(end - 1), :, :, :, :], 0) .+ max.(M[2:end, :, :, :, :], 0))
    print("  f per level, M-weighted (clamped share): ")
    for k in 2:min(6, size(f, 1))
        updraft = s[k, :, :, :, :] .> 1e-3
        used = updraft .& (f[k, :, :, :, :] .> 0)
        clamped = updraft .& ((raw[k, :, :, :, :] .> 1) .| (raw[k, :, :, :, :] .< 0))
        weight = Mc[k, :, :, :, :] .* used
        sum(weight) > 0 || continue
        print(
            "L$k $(round(sum(f[k, :, :, :, :] .* weight) / sum(weight), digits = 2)) ",
            "($(round(100 * count(clamped) / max(count(updraft), 1), digits = 0))%)  ",
        )
    end
    println()

    # Per tag.
    reference = argmin(abs.(vec(zf[:, 1, 1, 1, 1]) .- 1500))
    println(
        "  per tag, upwind | centred: relocated a day; lifted above $(round(zf[reference, 1, 1, 1, 1], digits = 0)) m a day; ",
        "centroid rise, m a day (actual change to the next day)",
    )
    for tag in TAGS
        hasproperty(Y.c, Symbol(:ρe_src_, tag)) || continue
        (; ᶜtag, upwind, centred, ᶠupwind, ᶠcentred) = gap(Y, FT(c), tag)
        ᶜnext = similar(ᶜtag)
        parent(ᶜnext) .= parent(getproperty(Y_next.c, Symbol(:ρe_src_, tag)))
        for (label, mask) in regions
            amount = sum(@. abs(ᶜtag) * mask)
            amount > 0 || continue
            below = sum(@. ᶜtag * mask * (ᶜz < zf[reference, 1, 1, 1, 1]))
            columns = parent(Fields.level(mask, 1))
            # The horizontal area of each column: the lowest cell's volume
            # weight over its height.
            area_region =
                parent(Fields.local_geometry_field(Fields.level(Y.c, 1)).WJ) ./
                parent(Fields.level(Fields.Δz_field(Y.c), 1)) .* columns
            values = map(((ᶜtendency = upwind, ᶠflux = ᶠupwind), (ᶜtendency = centred, ᶠflux = ᶠcentred))) do case
                relocated = 0.5 * sum(@. abs(case.ᶜtendency) * mask) * 86400 / amount
                lift = parent(Geometry.WVector.(case.ᶠflux))[reference, :, :, :, :]
                lifted = below > 0 ? sum(lift .* area_region[1, :, :, :, :]) * 86400 / below : NaN
                rise = sum(@. ᶜz * case.ᶜtendency * mask) / sum(@. ᶜtag * mask) * 86400
                (relocated, lifted, rise)
            end
            actual = centroid(ᶜnext, ᶜz, mask) - centroid(ᶜtag, ᶜz, mask)
            println(
                "    $(rpad(tag, 17)) $(rpad(label, 9)) ",
                "$(round(values[1][1], sigdigits = 2)) | $(round(values[2][1], sigdigits = 2));  ",
                "$(round(values[1][2], sigdigits = 2)) | $(round(values[2][2], sigdigits = 2));  ",
                "$(round(values[1][3], sigdigits = 3)) | $(round(values[2][3], sigdigits = 3)) ",
                "($(round(actual, sigdigits = 3)))",
            )
        end
    end
    return nothing
end

function parse_days(text)
    parts = split(text, ":")
    return parse(Int, parts[1]):parse(Int, parts[end])
end

run = length(ARGS) >= 1 ? ARGS[1] : "g2_v2_sphere"
offset = length(ARGS) >= 2 ? parse(Float64, ARGS[2]) : 110495.0
days = length(ARGS) >= 3 ? parse_days(ARGS[3]) : 1:9
for day in days
    day_report(run, offset, day)
end
