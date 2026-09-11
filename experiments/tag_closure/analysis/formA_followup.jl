#=
Why form A does not close on the gray sphere, under tracer transport (C7) and
under the enthalpy audit (C9, C10). A reviewer agent wrote these three scripts
on 2026-09-11 and ran them on the terrabyte login node, against the runs' hourly
NetCDF on scratch. They read output only.

    julia +1.11 --project=.buildkite experiments/tag_closure/analysis/formA_mechanism.jl
    julia +1.11 --project=.buildkite experiments/tag_closure/analysis/formA_followup.jl
    julia +1.11 --project=.buildkite experiments/tag_closure/analysis/formA_last.jl

`formA_mechanism.jl`:
  - whether C6's and C7's shared tags are identical;
  - the worst form-A points and what the tags hold there;
  - C7 against the first-order C6 run;
  - whether negative overlays freeze in place under the audit;
  - whether subtracting the repair's ledgers gives the no-repair gap;
  - where the audit's gap sits, and how it cancels per level.
`formA_followup.jl`:
  - E30 over the whole sphere;
  - the worst column;
  - form A's global integrals;
  - the node where the minimum freezes.
`formA_last.jl`:
  - the loss clamp's point;
  - the tags' roughness.

The integrals take a hydrostatic density, from `ta` with a surface pressure of
1e5 Pa, on the lat-lon grid, so they are approximate. See FINDINGS E35 to E38.
Outputs are in `output/formA_mechanism/`.
=#

import NCDatasets
using Printf

const BASE = "/dss/dsstbyfs02/scratch/0D/di38kez/tag_closure/output"
function rd(run, name)
    dir = joinpath(BASE, run, "output_active")
    files = filter(n -> startswith(n, name * "_") && endswith(n, "_inst.nc"), readdir(dir))
    length(files) == 1 || error("$run $name: $files")
    NCDatasets.NCDataset(joinpath(dir, only(files))) do ds
        v = ds[name]
        dn = collect(NCDatasets.dimnames(v))
        order = [findfirst(==(d), dn) for d in ("lon", "lat", "z", "time")]
        permutedims(Array(v.var), order)
    end
end
function coords()
    dir = joinpath(BASE, "c7_sphere_mp", "output_active")
    f = only(filter(n -> startswith(n, "e_src_sfc_"), readdir(dir)))
    NCDatasets.NCDataset(joinpath(dir, f)) do ds
        (
            Array(ds["lon"].var),
            Array(ds["lat"].var),
            Array(ds["z"].var),
            Array(ds["time"].var),
        )
    end
end
const lon, lat, z, time = coords()
const nx, ny, nz, nt = length(lon), length(lat), length(z), length(time)
const R_d = 287.05;
const grav = 9.80616
ld(run, names) = Dict(
    n => rd(run, n == "ta" || startswith(n, "e_prc") ? n : "e_src_" * n) for n in names
)
names = [
    "sfc",
    "rad",
    "mp",
    "new_tropics",
    "new_extratropics",
    "ta",
    "e_prc_surface_flux",
    "e_prc_radiation",
]
C7 = ld("c7_sphere_mp", names)
C9 = ld("c9_sphere_enthalpy", names)
C10 = ld(
    "c10_sphere_enthalpy_repair",
    [names; ["fix_sfc", "fix_rad", "fix_mp", "fix_new_tropics", "fix_new_extratropics"]],
)
C6 = ld("c6_sphere_no_repair", ["sfc", "rad", "new_tropics", "new_extratropics"])
C6fo = ld("c6_sphere_first_order", ["sfc", "rad", "new_tropics", "new_extratropics"])
newsum(d) = d["new_tropics"] .+ d["new_extratropics"]
G7 = newsum(C7) .- C7["sfc"] .- C7["rad"] .- C7["mp"]
G9 = newsum(C9) .- C9["sfc"] .- C9["rad"] .- C9["mp"]
G10 = newsum(C10) .- C10["sfc"] .- C10["rad"] .- C10["mp"]
G6 = newsum(C6) .- C6["sfc"] .- C6["rad"]
G6fo = newsum(C6fo) .- C6fo["sfc"] .- C6fo["rad"]
maxabs(a) = isempty(a) ? 0.0 : maximum(abs, a)
T = nt

println(
    "=== A. E30 over the whole sphere: G7 (van Leer) against G6fo - mp7 (first order, mp content removed)",
)
for t in (7, 13, 25)
    for thr in (1.0, 5.0, Inf)
        m = abs.(C7["mp"][:, :, :, t]) .< thr
        a = G7[:, :, :, t][m];
        b = (G6fo[:, :, :, t] .- C7["mp"][:, :, :, t])[m]
        @printf(
            "  t=%2dh |mp7|<%-4s frac %.2f: max|G7| %.3f  max|G6fo-mp7| %.3f | sum|G7| %.3e  sum|G6fo-mp7| %.3e\n",
            time[t] / 3600, string(thr), count(m) / length(m), maxabs(a), maxabs(b),
            sum(abs, a), sum(abs, b))
    end
end
# Where does G6fo - mp7 peak, and how big is mp there (the approximation error scales with mp)?
b = G6fo[:, :, :, T] .- C7["mp"][:, :, :, T];
Ib = argmax(abs.(b))
@printf(
    "  peak of |G6fo-mp7| at 24h: %.3f at (i=%d,j=%d,k=%d), mp7 there %.2f, G7 there %.3f\n",
    b[Ib],
    Ib[1],
    Ib[2],
    Ib[3],
    C7["mp"][Ib, T],
    G7[Ib, T]
)

# Approximate hydrostatic density from ta, p_s = 1e5 Pa.
zf = zeros(nz + 1);
for k in 1:nz
    ;
    zf[k + 1] = 2z[k] - zf[k];
end
dz = diff(zf)
function rho(ta)
    ρ = similar(ta)
    for t in axes(ta, 4), j in 1:ny, i in 1:nx
        lp = log(1e5) - grav * z[1] / (R_d * ta[i, j, 1, t])
        ρ[i, j, 1, t] = exp(lp) / (R_d * ta[i, j, 1, t])
        for k in 2:nz
            lp -=
                grav * (z[k] - z[k - 1]) / (R_d * (ta[i, j, k, t] + ta[i, j, k - 1, t]) / 2)
            ρ[i, j, k, t] = exp(lp) / (R_d * ta[i, j, k, t])
        end
    end
    ρ
end
ρ = rho(C7["ta"])  # identical atmosphere in all runs
iend = abs(lon[end] - lon[1] - 360) < 1e-6 ? nx - 1 : nx
W = [(i <= iend ? 1.0 : 0.0) * cosd(lat[j]) * dz[k] for i in 1:nx, j in 1:ny, k in 1:nz]
integ(f, t) = sum(W .* ρ[:, :, :, t] .* f[:, :, :, t])

println(
    "\n=== B. G7 in the worst column (63,33) at 24 h, by level, and its column integral",
)
i, j = 63, 33
colG = [G7[i, j, k, T] for k in 1:nz]
println("  G7 by level: ", join([@sprintf("%.2f", x) for x in colG], " "))
println(
    "  sfc by level: ",
    join([@sprintf("%.0f", C7["sfc"][i, j, k, T]) for k in 1:nz], " "),
)
println(
    "  rad by level: ",
    join([@sprintf("%.0f", C7["rad"][i, j, k, T]) for k in 1:nz], " "),
)
cw = [ρ[i, j, k, T] * dz[k] for k in 1:nz]
@printf(
    "  column: sum rho dz G = %.3e, sum rho dz |G| = %.3e, ratio %.3f\n",
    sum(cw .* colG),
    sum(cw .* abs.(colG)),
    abs(sum(cw .* colG)) / sum(cw .* abs.(colG))
)
# Over all columns: fraction of |G| that cancels within columns.
function colratio(G, t)
    num = 0.0;
    den = 0.0
    for jj in 1:ny, ii in 1:iend
        s = 0.0;
        sa = 0.0
        for k in 1:nz
            w = ρ[ii, jj, k, t] * dz[k] * cosd(lat[jj])
            s += w * G[ii, jj, k, t];
            sa += w * abs(G[ii, jj, k, t])
        end
        num += abs(s);
        den += sa
    end
    num / den
end
for (name, G) in (("C7", G7), ("C9", G9), ("C10", G10), ("C6 (no mp tag)", G6))
    @printf(
        "  %-15s sum over columns |col integral of G| / integral |G| at 24h: %.3f\n",
        name,
        colratio(G, T)
    )
end

println(
    "\n=== C. Global (approx. mass-weighted) integrals: does an integral form A separate a missing process from numerics?",
)
for (name, G, d) in
    (("C6 (no mp tag)", G6, C6), ("C7", G7, C7), ("C9", G9, C9), ("C10", G10, C10))
    for t in (7, 13, 25)
        IN = integ(newsum(d), t);
        IG = integ(G, t);
        IA = integ(abs.(G), t)
        @printf(
            "  %-15s t=%2dh: int G / int new = %+.3e | int|G| / int new = %.3e | max|G|/max new = %.3e\n",
            name, time[t] / 3600, IG / IN, IA / IN,
            maxabs(G[:, :, :, t]) / maximum(newsum(d)[:, :, :, t]))
    end
end
dfix =
    C10["fix_new_tropics"] .+ C10["fix_new_extratropics"] .- C10["fix_sfc"] .-
    C10["fix_rad"] .- C10["fix_mp"]
for t in (13, 25)
    IN = integ(newsum(C10), t)
    @printf(
        "  C10 t=%2dh: int(G10 - G9)/int new = %+.3e ; int(Δfix)/int new = %+.3e ; int fix_sfc/int new = %.3e\n",
        time[t] / 3600, integ(G10 .- G9, t) / IN, integ(dfix, t) / IN,
        integ(C10["fix_sfc"], t) / IN)
end
# the mp content the C6 layout misses, as a fraction of the new energy
for t in (7, 13, 25)
    @printf(
        "  int mp7 / int new (C7) t=%2dh: %.3e\n",
        time[t] / 3600,
        integ(C7["mp"], t) / integ(newsum(C7), t)
    )
end

println("\n=== D. The ratchet node (4,27,1) and its mirror (4,10,1)")
for (i, j) in ((4, 27), (4, 10))
    println(
        "  node ($i,$j,1) lon=$(round(lon[i]; digits=1)) lat=$(round(lat[j]; digits=1)):",
    )
    println(
        "    surface-flux record every 4 h: ",
        join([@sprintf("%.0f", C7["e_prc_surface_flux"][i, j, 1, t]) for t in 1:4:nt], " "),
    )
    println(
        "    radiation record every 4 h:    ",
        join([@sprintf("%.0f", C7["e_prc_radiation"][i, j, 1, t]) for t in 1:4:nt], " "),
    )
    for (name, d) in (("C7", C7), ("C9", C9), ("C10", C10))
        @printf(
            "    %-3s 24h: sfc %.1f rad %.1f mp %.2f new %.1f\n",
            name,
            d["sfc"][i, j, 1, T],
            d["rad"][i, j, 1, T],
            d["mp"][i, j, 1, T],
            newsum(d)[i, j, 1, T]
        )
    end
end
println(
    "  sfc at level 1 around (4,27) at 12 h; rows lat j=25..29, cols lon i=1..8 (i=1 is -180):",
)
for (name, d) in (("C7", C7), ("C9", C9))
    println("   $name")
    for jj in 29:-1:25
        println(
            "    lat ",
            @sprintf("%5.1f", lat[jj]),
            ": ",
            join([@sprintf("%7.0f", d["sfc"][ii, jj, 1, 13]) for ii in 1:8], " "),
        )
    end
end
println("  surface-flux record at level 1 around (4,27) at 12 h:")
for jj in 29:-1:25
    println(
        "    lat ",
        @sprintf("%5.1f", lat[jj]),
        ": ",
        join(
            [@sprintf("%7.0f", C7["e_prc_surface_flux"][ii, jj, 1, 13]) for ii in 1:8],
            " ",
        ),
    )
end
println("  lon[1:8] = ", join([@sprintf("%.1f", lon[ii]) for ii in 1:8], " "))
println("  C9 G at level 1 around (4,27) at 24 h:")
for jj in 29:-1:25
    println(
        "    lat ",
        @sprintf("%5.1f", lat[jj]),
        ": ",
        join([@sprintf("%7.1f", G9[ii, jj, 1, T]) for ii in 1:8], " "),
    )
end
println(
    "  C9 sfc vertical profile at (4,27) at 24 h: ",
    join([@sprintf("%.0f", C9["sfc"][4, 27, k, T]) for k in 1:nz], " "),
)
println(
    "  C7 sfc vertical profile at (4,27) at 24 h: ",
    join([@sprintf("%.0f", C7["sfc"][4, 27, k, T]) for k in 1:nz], " "),
)
