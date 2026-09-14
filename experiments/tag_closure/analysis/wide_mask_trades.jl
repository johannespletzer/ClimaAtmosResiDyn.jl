#=
Whether the region mask's step makes the repair's trades (FINDINGS E46): the
region ledgers of C6's sphere with the named 2° masks against the same sphere
with the masks 10° wide.

    julia +1.11 --project=.buildkite experiments/tag_closure/analysis/wide_mask_trades.jl

It reads the hourly NetCDF of `c6_sphere_repair` and `c6_sphere_wide_mask` on
scratch. The atmospheres are identical, so the density is the same in both. For
each run it prints:
  - the extremes of `e_src_fix_tropics` at 24 h, and where;
  - the mass-weighted gross of that ledger, by the hour, relative to the 2° run
    at 24 h;
  - its share by latitude row at 24 h, beside the mass;
  - the gross of the source tags' ledgers, which the mask does not touch
    directly.

Mass weights take a hydrostatic density from `ta` with a surface pressure of
1e5 Pa, as `repair_trades.jl` does, on the remapped lat-lon grid.
=#

import NCDatasets
using Printf

const BASE = "/dss/dsstbyfs02/scratch/0D/di38kez/tag_closure/output"
const R_d = 287.05
const grav = 9.80616
const RUNS = ("c6_sphere_repair", "c6_sphere_wide_mask")

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

const lon, lat, z, time = NCDatasets.NCDataset(
    joinpath(BASE, RUNS[1], "output_active", "ta_1h_inst.nc"),
) do ds
    Array(ds["lon"].var), Array(ds["lat"].var), Array(ds["z"].var), Array(ds["time"].var)
end
const nx, ny, nz, nt = length(lon), length(lat), length(z), length(time)
const nx_unique = abs(lon[end] - lon[1] - 360) < 1e-6 ? nx - 1 : nx

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
            log_p -=
                grav * (z[k] - z[k - 1]) / (R_d * (ta[i, j, k, t] + ta[i, j, k - 1, t]) / 2)
            ρ[i, j, k, t] = exp(log_p) / (R_d * ta[i, j, k, t])
        end
    end
    return ρ
end

mass(ρ, t) = [
    (i <= nx_unique ? 1.0 : 0.0) * cosd(lat[j]) * dz[k] * ρ[i, j, k, t] for
    i in 1:nx, j in 1:ny, k in 1:nz
]
gross(ρ, field, t) = sum(mass(ρ, t) .* abs.(field[:, :, :, t]))
where(I) = @sprintf("lon %.1f, lat %.1f, z %.0f m", lon[I[1]], lat[I[2]], z[I[3]])

ρ = hydrostatic_density(read_field(RUNS[1], "ta"))
fix = Dict(run => read_field(run, "e_src_fix_tropics") for run in RUNS)
source_names = (
    "e_src_fix_sfc",
    "e_src_fix_rad",
    "e_src_fix_new_tropics",
    "e_src_fix_new_extratropics",
)
reference = gross(ρ, fix[RUNS[1]], nt)

for run in RUNS
    f = fix[run][:, :, :, nt]
    imax, imin = argmax(f), argmin(f)
    println("\n", run)
    @printf("  e_src_fix_tropics at 24 h: max %.1f J/kg at %s\n", f[imax], where(imax))
    @printf("                              min %.1f J/kg at %s\n", f[imin], where(imin))
    @printf(
        "  gross at 24 h, relative to %s: %.3f\n",
        RUNS[1],
        gross(ρ, fix[run], nt) / reference
    )
    for name in source_names
        @printf("  gross of %s at 24 h, relative to the region ledger of %s: %.4f\n",
            name, RUNS[1], gross(ρ, read_field(run, name), nt) / reference)
    end
end

println("\nthe tropics ledger's gross by the hour, relative to $(RUNS[1]) at 24 h:")
println("  hour   2° mask   10° mask")
for t in 2:nt
    @printf("  %4.0f   %7.3f   %8.3f\n", time[t] / 3600,
        gross(ρ, fix[RUNS[1]], t) / reference, gross(ρ, fix[RUNS[2]], t) / reference)
end

println(
    "\nshare of each run's tropics ledger gross by latitude row at 24 h, both hemispheres:",
)
println("  |lat|    mass   2° mask   10° mask")
W = mass(ρ, nt)
rows(field) = (g = W .* abs.(field[:, :, :, nt]); [sum(g[:, j, :]) for j in 1:ny] ./ sum(g))
mass_rows = [sum(W[:, j, :]) for j in 1:ny] ./ sum(W)
narrow, wide = rows(fix[RUNS[1]]), rows(fix[RUNS[2]])
for j in 1:ny
    lat[j] > 0 || continue
    mirror = findfirst(l -> isapprox(l, -lat[j]; atol = 1e-6), lat)
    @printf("  %5.1f   %6.3f   %6.3f   %8.3f\n", lat[j], mass_rows[j] + mass_rows[mirror],
        narrow[j] + narrow[mirror], wide[j] + wide[mirror])
end
