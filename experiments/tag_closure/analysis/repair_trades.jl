#=
Where the repair's large trades between the region tags sit on the sphere (C5 of
OPERATIONAL_TODO.md, FINDINGS E27 and E35).

    julia +1.11 --project=.buildkite experiments/tag_closure/analysis/repair_trades.jl

It reads the hourly NetCDF on scratch and writes nothing into the runs. Two
pairs, each the same atmosphere with the repair on and off:
  - tracer transport: `c6_sphere_repair` against `c6_sphere_no_repair`;
  - the enthalpy audit: `c10_sphere_enthalpy_repair` against `c9_sphere_enthalpy`.

The region tags `tropics` and `extratropics` meet at 20° latitude, where their
masks cross in a tanh 2° wide. E19 argued that transport undershoots at that
edge make the region tags negative. If so, the repair trades there.

For each pair it prints:
  - the extremes of the two region ledgers, `e_src_fix_<region>`, and where;
  - how far the two ledgers cancel, since the partition repair keeps their sum;
  - the share of the ledgers' gross, mass-weighted, by latitude row and by
    level, beside the share of the mass;
  - the same shares for the negative parts of the region tags without the
    repair;
  - how the gross grows by the hour, and its share near the edge.

The ledger is cumulative and stays where the repair acted, while the tags move.
The negative parts are a snapshot. So the two profiles are compared by where
they sit, not by value.

Mass weights take a hydrostatic density from `ta` with a surface pressure of
1e5 Pa, as `formA_followup.jl` does. Everything is on the remapped lat-lon grid,
so the numbers are approximate.
=#

import NCDatasets
using Printf

const BASE = "/dss/dsstbyfs02/scratch/0D/di38kez/tag_closure/output"
const R_d = 287.05
const grav = 9.80616
const EDGE = 20.0
# Rows within this many degrees of the edge count as near it. The grid spacing
# is 5.14°, so this takes the one row on each side of each edge, at 18.0° and
# 23.1°.
const NEAR = 7.0

function read_field(run, name)
    dir = joinpath(BASE, run, "output_active")
    files = filter(n -> startswith(n, name * "_") && endswith(n, "_inst.nc"), readdir(dir))
    length(files) == 1 || error("$run $name: $files")
    NCDatasets.NCDataset(joinpath(dir, only(files))) do ds
        v = ds[name]
        order = [
            findfirst(==(d), collect(NCDatasets.dimnames(v))) for
            d in ("lon", "lat", "z", "time")
        ]
        permutedims(Array(v.var), order)
    end
end

function coordinates(run)
    dir = joinpath(BASE, run, "output_active")
    f = only(filter(n -> startswith(n, "ta_"), readdir(dir)))
    NCDatasets.NCDataset(joinpath(dir, f)) do ds
        Array(ds["lon"].var),
        Array(ds["lat"].var),
        Array(ds["z"].var),
        Array(ds["time"].var)
    end
end

const lon, lat, z, time = coordinates("c6_sphere_repair")
const nx, ny, nz, nt = length(lon), length(lat), length(z), length(time)
# The remapped grid repeats 180° as −180°. The repeated column is left out.
const nx_unique = abs(lon[end] - lon[1] - 360) < 1e-6 ? nx - 1 : nx
const near_edge = [abs(abs(φ) - EDGE) <= NEAR for φ in lat]

function layer_thickness()
    faces = zeros(nz + 1)
    for k in 1:nz
        faces[k + 1] = 2z[k] - faces[k]
    end
    return diff(faces)
end
const dz = layer_thickness()

function hydrostatic_density(ta)
    ρ = similar(ta)
    for t in axes(ta, 4), j in 1:ny, i in 1:nx
        log_p = log(1e5) - grav * z[1] / (R_d * ta[i, j, 1, t])
        ρ[i, j, 1, t] = exp(log_p) / (R_d * ta[i, j, 1, t])
        for k in 2:nz
            mean_t = (ta[i, j, k, t] + ta[i, j, k - 1, t]) / 2
            log_p -= grav * (z[k] - z[k - 1]) / (R_d * mean_t)
            ρ[i, j, k, t] = exp(log_p) / (R_d * ta[i, j, k, t])
        end
    end
    return ρ
end

# Mass weight of each cell at time index t, in arbitrary units.
mass(ρ, t) = [
    (i <= nx_unique ? 1.0 : 0.0) * cosd(lat[j]) * dz[k] * ρ[i, j, k, t] for
    i in 1:nx, j in 1:ny, k in 1:nz
]

where(I) = @sprintf("lon %.1f, lat %.1f, z %.0f m", lon[I[1]], lat[I[2]], z[I[3]])

function by_row(weighted)
    total = sum(weighted)
    return [sum(weighted[:, j, :]) / total for j in 1:ny]
end
function by_level(weighted)
    total = sum(weighted)
    return [sum(weighted[:, :, k]) / total for k in 1:nz]
end
near_share(row_shares) = sum(row_shares[near_edge])

function report(label, repair_run, twin_run)
    println(
        "\n",
        "="^78,
        "\n",
        label,
        ": ",
        repair_run,
        " against ",
        twin_run,
        "\n",
        "="^78,
    )
    ρ = hydrostatic_density(read_field(repair_run, "ta"))
    fix = Dict(
        r => read_field(repair_run, "e_src_fix_" * r) for r in ("tropics", "extratropics")
    )
    twin =
        Dict(r => read_field(twin_run, "e_src_" * r) for r in ("tropics", "extratropics"))
    T = nt
    W = mass(ρ, T)

    println("\nextremes of the region ledgers at t = $(time[T]) s, J/kg")
    for r in ("tropics", "extratropics")
        f = fix[r][:, :, :, T]
        imax, imin = argmax(f), argmin(f)
        @printf("  %-13s max %10.1f at %s\n", r, f[imax], where(imax))
        @printf("  %-13s min %10.1f at %s\n", r, f[imin], where(imin))
    end
    f_sum = fix["tropics"][:, :, :, T] .+ fix["extratropics"][:, :, :, T]
    @printf(
        "  largest |sum of the two ledgers| %.3g J/kg, against a largest |ledger| of %.3g\n",
        maximum(abs, f_sum), maximum(abs, fix["tropics"][:, :, :, T]))

    gross = W .* abs.(fix["tropics"][:, :, :, T])
    lifted_tropics = W .* max.(fix["tropics"][:, :, :, T], 0)
    lifted_extra = W .* max.(fix["extratropics"][:, :, :, T], 0)
    negative =
        W .* (
            abs.(min.(twin["tropics"][:, :, :, T], 0)) .+
            abs.(min.(twin["extratropics"][:, :, :, T], 0))
        )
    in_extratropics = [abs(φ) > EDGE for φ in lat]

    println("\nwhich tag the repair lifted, as a share of the tropics ledger's gross")
    @printf("  tropics lifted (ledger > 0): %.3f, of which outside the tropics %.3f\n",
        sum(lifted_tropics) / sum(gross),
        sum(lifted_tropics[:, in_extratropics, :]) / sum(lifted_tropics))
    @printf("  extratropics lifted:         %.3f, of which inside the tropics %.3f\n",
        sum(lifted_extra) / sum(gross),
        sum(lifted_extra[:, .!in_extratropics, :]) / sum(lifted_extra))

    rows_mass, rows_gross, rows_negative = by_row(W), by_row(gross), by_row(negative)
    println(
        "\nby latitude row: share of mass, of the ledger's gross, of the twin's negative parts",
    )
    println("  lat      mass   ledger  negative")
    for j in 1:ny
        @printf("  %6.1f  %6.3f  %6.3f  %6.3f%s\n", lat[j], rows_mass[j], rows_gross[j],
            rows_negative[j], near_edge[j] ? "  near the edge" : "")
    end
    @printf("  within %.0f° of the edge: mass %.3f, ledger %.3f, negative parts %.3f\n",
        NEAR, near_share(rows_mass), near_share(rows_gross), near_share(rows_negative))

    levels_mass, levels_gross, levels_negative =
        by_level(W), by_level(gross), by_level(negative)
    println(
        "\nby level: share of mass, of the ledger's gross, of the twin's negative parts",
    )
    println("  z, m      mass   ledger  negative")
    for k in 1:nz
        @printf(
            "  %7.0f  %6.3f  %6.3f  %6.3f\n",
            z[k],
            levels_mass[k],
            levels_gross[k],
            levels_negative[k]
        )
    end

    println("\nby hour: the ledger's gross, relative to 24 h, and its share near the edge")
    for t in 2:nt
        g = mass(ρ, t) .* abs.(fix["tropics"][:, :, :, t])
        @printf("  %4.0f h  %.3f  near the edge %.3f\n", time[t] / 3600,
            sum(g) / sum(gross), near_share(by_row(g)))
    end

    front_report(repair_run, twin_run, ρ, fix, twin)
end

# The latitude where the tropics tag's share of the two region tags falls below
# one half, going poleward from the equator, for one longitude, level, time and
# hemisphere. It is interpolated linearly between rows. NaN where it never falls.
function front_latitude(tropics, extratropics, i, k, t, rows)
    share(j) = tropics[i, j, k, t] / (tropics[i, j, k, t] + extratropics[i, j, k, t])
    previous = share(rows[1])
    previous < 0.5 && return abs(lat[rows[1]])
    for m in 2:length(rows)
        current = share(rows[m])
        if current < 0.5
            φ0, φ1 = abs(lat[rows[m - 1]]), abs(lat[rows[m]])
            return φ0 + (previous - 0.5) / (previous - current) * (φ1 - φ0)
        end
        previous = current
    end
    return NaN
end

const BIN = 2.5
const BINS = -30.0:BIN:30.0
bin_index(d) = clamp(floor(Int, (d - first(BINS)) / BIN) + 1, 1, length(BINS))

# Where the repair acts and where the tags go negative, measured from the front
# between the two region tags at that hour rather than from the fixed edge. The
# ledger's hourly increments are placed against the front at the start of their
# hour, and the twin's negative parts against the twin's own front.
function front_report(repair_run, twin_run, ρ, fix, twin)
    tags =
        Dict(r => read_field(repair_run, "e_src_" * r) for r in ("tropics", "extratropics"))
    north = [j for j in 1:ny if lat[j] > 0]
    south = reverse([j for j in 1:ny if lat[j] < 0])
    mass_bins, ledger_bins, negative_bins =
        zeros(length(BINS)), zeros(length(BINS)), zeros(length(BINS))
    fronts = Float64[]
    for t in 2:nt
        W = mass(ρ, t)
        for i in 1:nx_unique, k in 1:nz, rows in (north, south)
            φ_repair =
                front_latitude(tags["tropics"], tags["extratropics"], i, k, t - 1, rows)
            φ_twin = front_latitude(twin["tropics"], twin["extratropics"], i, k, t, rows)
            push!(fronts, φ_repair)
            for j in rows
                if !isnan(φ_repair)
                    b = bin_index(abs(lat[j]) - φ_repair)
                    mass_bins[b] += W[i, j, k]
                    ledger_bins[b] +=
                        W[i, j, k] *
                        abs(fix["tropics"][i, j, k, t] - fix["tropics"][i, j, k, t - 1])
                end
                if !isnan(φ_twin)
                    negative =
                        min(twin["tropics"][i, j, k, t], 0) +
                        min(twin["extratropics"][i, j, k, t], 0)
                    negative_bins[bin_index(abs(lat[j]) - φ_twin)] +=
                        W[i, j, k] * abs(negative)
                end
            end
        end
    end
    valid = filter(!isnan, fronts)
    @printf("\nthe front between the region tags, over all hours, longitudes and levels:\n")
    @printf(
        "  latitude median %.1f°, 10%% to 90%% %.1f° to %.1f°, never found in %.3f of cases\n",
        sort(valid)[cld(length(valid), 2)], sort(valid)[cld(length(valid), 10)],
        sort(valid)[cld(9 * length(valid), 10)], 1 - length(valid) / length(fronts))
    println("\nby distance from the front, poleward positive, summed over the hours:")
    println(
        "  share of mass, of the ledger's hourly increments, of the twin's negative parts",
    )
    println("  distance, °     mass   ledger  negative")
    for (b, d) in enumerate(BINS)
        label =
            b == 1 ? "below $(d + BIN)" :
            b == length(BINS) ? "$(d) and beyond" : "$(d) to $(d + BIN)"
        @printf("  %-14s %6.3f  %6.3f  %6.3f\n", label, mass_bins[b] / sum(mass_bins),
            ledger_bins[b] / sum(ledger_bins), negative_bins[b] / sum(negative_bins))
    end
    within(x, r) = sum(x[[abs(d + BIN / 2) <= r for d in BINS]]) / sum(x)
    for r in (5.0, 10.0)
        @printf(
            "  within %.0f° of the front: mass %.3f, ledger %.3f, negative parts %.3f\n",
            r, within(mass_bins, r), within(ledger_bins, r), within(negative_bins, r))
    end
end

report("tracer transport", "c6_sphere_repair", "c6_sphere_no_repair")
report("the enthalpy audit", "c10_sphere_enthalpy_repair", "c9_sphere_enthalpy")
