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

# Field as (lon, lat, z, time).
function rd(run, name)
    dir = joinpath(BASE, run, "output_active")
    files = filter(n -> startswith(n, name * "_") && endswith(n, "_inst.nc"), readdir(dir))
    length(files) == 1 || error("$run $name: $files")
    NCDatasets.NCDataset(joinpath(dir, only(files))) do ds
        v = ds[name]
        dn = collect(NCDatasets.dimnames(v))
        A = Array(v.var)
        order = [findfirst(==(d), dn) for d in ("lon", "lat", "z", "time")]
        permutedims(A, order)
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
const R_d = 287.05

load(run, names) = Dict(n => rd(run, (n == "ta" ? "ta" : "e_src_" * n)) for n in names)
tagnames = [
    "tropics",
    "extratropics",
    "res",
    "sfc",
    "rad",
    "mp",
    "new_tropics",
    "new_extratropics",
    "ta",
]
fixnames = [
    "fix_" * n for n in
    ["tropics", "extratropics", "sfc", "rad", "mp", "new_tropics", "new_extratropics"]
]

println("loading ...")
C7 = load("c7_sphere_mp", tagnames)
C9 = load("c9_sphere_enthalpy", tagnames)
C10 = load("c10_sphere_enthalpy_repair", [tagnames; fixnames])
c6names = ["sfc", "rad", "new_tropics", "new_extratropics"]
C6 = load("c6_sphere_no_repair", c6names)
C6fo = load("c6_sphere_first_order", c6names)
C6r = load(
    "c6_sphere_repair",
    [c6names; ["fix_sfc", "fix_rad", "fix_new_tropics", "fix_new_extratropics"]],
)
println("loaded")

newsum(d) = d["new_tropics"] .+ d["new_extratropics"]
gap(d, procs) = newsum(d) .- sum(d[p] for p in procs)
P3 = ["sfc", "rad", "mp"];
P2 = ["sfc", "rad"]
G7 = gap(C7, P3);
G9 = gap(C9, P3);
G10 = gap(C10, P3)
G6 = gap(C6, P2);
G6fo = gap(C6fo, P2);
G6r = gap(C6r, P2)

maxabs(a) = maximum(abs, a)
loc(I) = @sprintf(
    "(i=%d,j=%d,k=%d) lon=%.1f lat=%.1f z=%.0f",
    I[1],
    I[2],
    I[3],
    lon[I[1]],
    lat[I[2]],
    z[I[3]]
)
T = nt  # last sample, 24 h

println(
    "\n=== 0. grid: lon ",
    lon[1],
    "..",
    lon[end],
    " lat ",
    lat[1],
    "..",
    lat[end],
    " z ",
    round.(z; digits = 0),
)

println(
    "\n=== 1. Under tracer transport each tag evolves on its own: C6 no-repair against C7",
)
for n in c6names
    @printf("  %-18s max|C6 - C7| = %.3e\n", n, maxabs(C6[n] .- C7[n]))
end
@printf("  max|G6 - G7 - mp7| = %.3e\n", maxabs(G6 .- G7 .- C7["mp"]))

println("\n=== 2. Worst form-A point at 24 h and what sits there")
for (name, G, d, procs) in (("C7", G7, C7, P3), ("C9", G9, C9, P3), ("C10", G10, C10, P3))
    g = G[:, :, :, T]
    I = argmax(abs.(g))
    E = d["res"][I, T] + d["tropics"][I, T] + d["extratropics"][I, T]
    A = 1 + R_d * d["ta"][I, T] / E
    @printf(
        "  %s: G=%.2f at %s; E/rho=%.0f J/kg, T=%.1f K, (E+p)/E~%.2f\n",
        name,
        g[I],
        loc(I),
        E,
        d["ta"][I, T],
        A
    )
    for n in ["sfc", "rad", "mp", "new_tropics", "new_extratropics"]
        @printf("      %-18s %.2f\n", n, d[n][I, T])
    end
end

println(
    "\n=== 3. E30: tracer transport, van Leer (C7) against first order (C6fo), at points far from any mp energy",
)
# mp-free: |mp_C7| below thr at the point and within +-2 lon, +-2 lat, all levels.
function mpfree(mp, t, thr, r)
    colmax = dropdims(maximum(abs.(mp[:, :, :, t]); dims = 3); dims = 3)
    m = falses(nx, ny, nz)
    for j in 1:ny, i in 1:nx
        ok = true
        for dj in (-r):r, di in (-r):r
            jj = j + dj
            1 <= jj <= ny || continue
            colmax[mod1(i + di, nx), jj] >= thr && (ok = false)
        end
        ok && (m[i, j, :] .= true)
    end
    m
end
for t in (7, 13, 19, 25)
    for thr in (1e-2, 1e-1)
        m = mpfree(C7["mp"], t, thr, 2)
        g7 = G7[:, :, :, t][m];
        gfo = G6fo[:, :, :, t][m];
        gvl = G6[:, :, :, t][m]
        @printf(
            "  t=%2dh thr=%.0e: frac pts %.3f | max|G7| %.3f  max|G6vl| %.3f  max|G6fo| %.3f | sum|G7| %.3e sum|G6fo| %.3e\n",
            time[t] / 3600, thr, count(m) / length(m), maxabs(g7), maxabs(gvl), maxabs(gfo),
            sum(abs, g7), sum(abs, gfo))
    end
end
g7 = G7[:, :, :, T];
I7 = argmax(abs.(g7))
@printf("  at C7's worst point %s: G7=%.3f mp7=%.4f G6vl=%.3f G6fo=%.3f G6fo-mp7=%.3f\n",
    loc(I7), g7[I7], C7["mp"][I7, T], G6[I7, T], G6fo[I7, T], G6fo[I7, T] - C7["mp"][I7, T])
println("  C7's worst |G| by hour and where (to see if it stays put):")
for t in (4, 7, 13, 19, 25)
    g = G7[:, :, :, t];
    I = argmax(abs.(g))
    @printf(
        "    t=%2dh G=%.3f at %s, mp there %.4f, G6fo-mp7 there %.3f\n",
        time[t] / 3600,
        g[I],
        loc(I),
        C7["mp"][I, t],
        G6fo[I, t] - C7["mp"][I, t]
    )
end
# Level profile of max|G| at 24 h in mp-free columns.
m = mpfree(C7["mp"], T, 1e-2, 2)
println("  per level at 24 h, mp-free columns: max|G7|, max|G6fo|")
for k in 1:nz
    mk = m[:, :, k]
    any(mk) || continue
    @printf(
        "    z=%6.0f  %.3f  %.3f\n",
        z[k],
        maxabs(G7[:, :, k, T][mk]),
        maxabs(G6fo[:, :, k, T][mk])
    )
end

println("\n=== 4. Audit: are negative overlay values frozen in place (the ratchet)?")
for (name, d) in (("C7", C7), ("C9", C9))
    println("  $name, sfc minimum by hour:")
    for t in (4, 7, 10, 13, 16, 19, 22, 25)
        s = d["sfc"][:, :, :, t];
        I = argmin(s)
        @printf("    t=%2dh min=%.2f at %s\n", time[t] / 3600, s[I], loc(I))
    end
end
s9 = C9["sfc"][:, :, :, T];
I9 = argmin(s9)
s7 = C7["sfc"][:, :, :, T];
I7s = argmin(s7)
println("  sfc at C9's 24 h minimum point, every 2 h, C9 then C7:")
println("    C9: ", join([@sprintf("%.1f", C9["sfc"][I9, t]) for t in 1:2:nt], " "))
println("    C7: ", join([@sprintf("%.1f", C7["sfc"][I9, t]) for t in 1:2:nt], " "))
println("  sfc at C7's 24 h minimum point ", loc(I7s), ", every 2 h, C7 then C9:")
println("    C7: ", join([@sprintf("%.1f", C7["sfc"][I7s, t]) for t in 1:2:nt], " "))
println("    C9: ", join([@sprintf("%.1f", C9["sfc"][I7s, t]) for t in 1:2:nt], " "))
f10 = C10["fix_sfc"][:, :, :, T];
If = argmax(f10)
@printf(
    "  C10 fix_sfc max %.2f at %s ; C9 sfc min %.2f at %s\n",
    f10[If],
    loc(If),
    s9[I9],
    loc(I9)
)
for n in ["sfc", "rad", "mp", "new_tropics", "new_extratropics"]
    neg9 = -min.(C9[n][:, :, :, T], 0)
    fx = C10["fix_" * n][:, :, :, T]
    num = sum(neg9 .* fx);
    den = sqrt(sum(neg9 .^ 2) * sum(fx .^ 2))
    @printf(
        "  %-17s C9 sum(neg)=%.4e  C10 sum(fix)=%.4e  corr=%.3f  max|fix10 - neg9|=%.2f (max fix %.2f)\n",
        n, sum(neg9), sum(fx), den > 0 ? num / den : NaN, maxabs(fx .- neg9), maximum(fx))
end
for n in ["tropics", "extratropics"]
    @printf(
        "  %-17s C10 fix range %.1f .. %.1f\n",
        n,
        minimum(C10["fix_" * n][:, :, :, T]),
        maximum(C10["fix_" * n][:, :, :, T])
    )
end

println(
    "\n=== 5. Is 'form A with ledgers out' the no-repair gap? C10 against C9 (same atmosphere), C6r against C6",
)
for (name, Gr, Gn, d, procs, news) in (
    ("C10 vs C9", G10, G9, C10, P3, ["new_tropics", "new_extratropics"]),
    ("C6r vs C6", G6r, G6, C6r, P2, ["new_tropics", "new_extratropics"]),
)
    dfix = sum(d["fix_" * n] for n in news) .- sum(d["fix_" * p] for p in procs)
    for t in (13, 25)
        ΔG = Gr[:, :, :, t] .- Gn[:, :, :, t]
        df = dfix[:, :, :, t]
        lo = Gr[:, :, :, t] .- df
        @printf(
            "  %s t=%2dh: max|G_rep|=%.1f max|G_norep|=%.1f max|ledgers-out|=%.1f | max|ΔG|=%.1f max|Δfix|=%.1f max|ΔG-Δfix|=%.1f | max|ledgers-out - G_norep|=%.1f\n",
            name, time[t] / 3600, maxabs(Gr[:, :, :, t]), maxabs(Gn[:, :, :, t]),
            maxabs(lo), maxabs(ΔG), maxabs(df), maxabs(ΔG .- df),
            maxabs(lo .- Gn[:, :, :, t]))
    end
end
g10 = G10[:, :, :, T];
I10 = argmax(abs.(g10))
@printf(
    "  C10 worst point %s: G10=%.1f G9=%.1f; sfc10=%.1f sfc9=%.1f fix_sfc=%.1f rad10=%.1f rad9=%.1f\n",
    loc(I10), g10[I10], G9[I10, T], C10["sfc"][I10, T], C9["sfc"][I10, T],
    C10["fix_sfc"][I10, T], C10["rad"][I10, T], C9["rad"][I10, T])

println("\n=== 6. Where the audit's gap sits, with history (C9)")
function dilate(mask, r, rz)
    out = falses(size(mask))
    for k in 1:nz, j in 1:ny, i in 1:nx
        mask[i, j, k] || continue
        for dk in (-rz):rz, dj in (-r):r, di in (-r):r
            kk = k + dk;
            jj = j + dj
            (1 <= kk <= nz && 1 <= jj <= ny) || continue
            out[mod1(i + di, nx), jj, kk] = true
        end
    end
    out
end
srcs = ["sfc", "rad", "mp", "new_tropics", "new_extratropics"]
for (name, d, G) in (("C9", C9, G9), ("C7", C7, G7))
    for thr in (-1.0, -1e-2)
        ever = falses(nx, ny, nz)
        for t in 1:nt
            neg = sum(min.(d[n][:, :, :, t], 0) for n in srcs) .< thr
            ever .|= neg
            if t in (2, 4, 7, 13, 25)
                g = abs.(G[:, :, :, t]);
                tot = sum(g)
                d1 = dilate(neg, 1, 1);
                de = dilate(ever, 1, 1)
                @printf(
                    "  %s thr=%.0e t=%2dh: max|G|=%.3f | now: %.2f of |G| at %.3f of pts | now+-1: %.2f at %.3f | ever+-1: %.2f at %.3f\n",
                    name, thr, time[t] / 3600, maximum(g), sum(g[neg]) / tot,
                    count(neg) / length(neg),
                    sum(g[d1]) / tot, count(d1) / length(d1), sum(g[de]) / tot,
                    count(de) / length(de))
            end
        end
    end
end

println(
    "\n=== 7. Dipole test: per-level |sum w G| / sum w |G| at 24 h (w = cos lat; no rho)",
)
w = reshape(cosd.(lat), 1, ny)
for (name, G) in (("C7", G7), ("C9", G9), ("C10", G10))
    r = [abs(sum(w .* G[:, :, k, T])) / sum(w .* abs.(G[:, :, k, T])) for k in 1:nz]
    println("  $name: ", join([@sprintf("%.2f", x) for x in r], " "))
end

println(
    "\n=== 8. Enthalpy speed-up (E+p)/E = 1 + R_d T/(E/rho) (the audit moves shares at u*(E+p)/E)",
)
for (name, d) in (("C9", C9),)
    E = d["res"][:, :, :, T] .+ d["tropics"][:, :, :, T] .+ d["extratropics"][:, :, :, T]
    A = 1 .+ R_d .* d["ta"][:, :, :, T] ./ E
    @printf(
        "  E/rho min %.0f max %.0f; A min %.2f max %.2f; A at level 1: min %.2f max %.2f\n",
        minimum(E),
        maximum(E),
        minimum(A),
        maximum(A),
        minimum(A[:, :, 1]),
        maximum(A[:, :, 1])
    )
    neg = d["sfc"][:, :, :, T] .< -1
    @printf(
        "  mean A where C9 sfc < -1: %.2f (n=%d); mean A over all: %.2f; level-1 share of those points %.2f\n",
        sum(A[neg]) / count(neg), count(neg), sum(A) / length(A),
        count(neg[:, :, 1]) / max(count(neg), 1))
    neg7 = C7["sfc"][:, :, :, T] .< -1
    @printf(
        "  mean A where C7 sfc < -1: %.2f (n=%d); level-1 share %.2f\n",
        sum(A[neg7]) / count(neg7),
        count(neg7),
        count(neg7[:, :, 1]) / max(count(neg7), 1)
    )
    # How negative, integrated, the overlays are in each run (grid-point sum, cos-lat weighted).
end
for (name, d) in (("C7", C7), ("C9", C9))
    for n in srcs
        @printf(
            "  %s %-17s sum_w min(tag,0) at 24h = %.4e, points < -1: %d\n",
            name,
            n,
            sum(w .* min.(d[n][:, :, :, T], 0)),
            count(d[n][:, :, :, T] .< -1)
        )
    end
end
