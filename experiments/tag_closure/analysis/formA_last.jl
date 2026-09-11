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
    f = only(
        filter(n -> startswith(n, name * "_") && endswith(n, "_inst.nc"), readdir(dir)),
    )
    NCDatasets.NCDataset(joinpath(dir, f)) do ds
        v = ds[name];
        dn = collect(NCDatasets.dimnames(v))
        permutedims(
            Array(v.var),
            [findfirst(==(d), dn) for d in ("lon", "lat", "z", "time")],
        )
    end
end
lat = NCDatasets.NCDataset(
    ds -> Array(ds["lat"].var),
    joinpath(BASE, "c7_sphere_mp/output_active/e_src_sfc_1h_inst.nc"),
)
C7 = Dict(
    n => rd("c7_sphere_mp", n) for n in (
        "e_src_sfc",
        "e_src_rad",
        "e_src_mp",
        "e_src_new_tropics",
        "e_src_new_extratropics",
        "e_prc_surface_flux",
    )
)
C9 = Dict(
    n => rd("c9_sphere_enthalpy", n) for
    n in ("e_src_sfc", "e_src_rad", "e_src_new_extratropics")
)
fo = rd("c6_sphere_first_order", "e_src_sfc")
I = (42, 26, 1)
println("C7 at (42,26,1), every 4 h:")
for (n, a) in (
    ("sfc C7", C7["e_src_sfc"]),
    ("sfc C6fo", fo),
    ("rad", C7["e_src_rad"]),
    ("new_extratropics", C7["e_src_new_extratropics"]),
    ("new_tropics", C7["e_src_new_tropics"]),
    ("sfc-flux record", C7["e_prc_surface_flux"]),
)
    println("  ", rpad(n, 18), join([@sprintf("%.1f", a[I..., t]) for t in 1:4:25], " "))
end
# Grid-scale roughness along longitude at level 1, |lat| < 80: sum|2nd difference| / sum|centred difference|.
function rough(a, t)
    nx = size(a, 1) - 1  # last lon duplicates the first
    num = 0.0;
    den = 0.0
    for j in axes(a, 2)
        abs(lat[j]) < 80 || continue
        for i in 1:nx
            ip = mod1(i + 1, nx);
            im = mod1(i - 1, nx)
            num += abs(a[ip, j, 1, t] - 2a[i, j, 1, t] + a[im, j, 1, t])
            den += abs(a[ip, j, 1, t] - a[im, j, 1, t])
        end
    end
    num / den
end
println("roughness at level 1 (2nd difference over centred difference), C7 then C9:")
for (n7, n9) in (
    ("e_src_sfc", "e_src_sfc"),
    ("e_src_rad", "e_src_rad"),
    ("e_src_new_extratropics", "e_src_new_extratropics"),
)
    for t in (7, 13, 25)
        @printf(
            "  %-24s t=%2dh  C7 %.3f  C9 %.3f\n",
            n7,
            (t - 1),
            rough(C7[n7], t),
            rough(C9[n9], t)
        )
    end
end
