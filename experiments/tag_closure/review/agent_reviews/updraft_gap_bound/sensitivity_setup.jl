#=
How much the gap estimate of updraft_gap_bound.jl moves with its choices, in
the tropics, for the surface-sourced tags:
  1. the script as it is (f from q_tot, clamped to [0, 1], upwind, e = E/ρ);
  2. points whose mixing-line ratio exceeds 1 dropped (f = 0) instead of clamped;
  3. f from the mse mixing line;
  4. the parent's own reconstruction (edmfx_sgsflux_upwinding: none, centred);
  5. the exact factor eʲ/(1 - σ) in place of e.
=#
import ClimaAtmos as CA
import ClimaComms
import ClimaCore: InputOutput, Fields, Geometry, Operators
const TD = CA.TD

const ROOT = "/dss/dsstbyfs02/scratch/0D/di38kez/tag_closure/output"
function read_state(run, day)
    dir = last(sort(filter(isdir, readdir(joinpath(ROOT, run); join = true))))
    reader = InputOutput.HDF5Reader(joinpath(dir, "day$(day).0.hdf5"), ClimaComms.SingletonCommsContext())
    Y = InputOutput.read_field(reader, "Y")
    close(reader)
    return Y
end
sig(x) = round(x, sigdigits = 3)

day = length(ARGS) >= 1 ? parse(Int, ARGS[1]) : 1
FT = Float32
c = FT(110495)
Y = read_state("g2_v2_sphere", day)
ρ = Y.c.ρ
sj = Y.c.sgsʲs.:(1)
ρa = sj.ρa
ᶜz = Fields.coordinate_field(Y.c).z
ᶜlat = Fields.coordinate_field(Y.c).lat
trop = @. ifelse(abs(ᶜlat) < 30, one(FT), zero(FT))
ᶜE = @. Y.c.ρe_tot + c * ρ
ᶜe = @. ᶜE / ρ
ᶜσ = @. ρa / ρ
on = @. ρa > FT(1e-3) * ρ

# f from q_tot, as the script does, and with out-of-line points dropped.
q_env = @. (Y.c.ρq_tot - ρa * sj.q_tot) / max(ρ - ρa, eps(FT) * ρ)
q1 = Fields.level(sj.q_tot, 1)
raw_q = @. (sj.q_tot - q_env) / (q1 - q_env)
ok_q = @. on & (abs(q1 - q_env) > FT(1e-6))
f_script = @. ifelse(ok_q, clamp(raw_q, FT(0), FT(1)), FT(0))
f_drop = @. ifelse(ok_q & (raw_q <= 1), max(raw_q, FT(0)), FT(0))

# f from mse.
tp = TD.Parameters.ThermodynamicsParameters(CA.CP.create_toml_dict(FT))
ᶜK = similar(ρ); ᶜK .= CA.compute_kinetic(Y.c.uₕ, Y.f.u₃)
ᶜKʲ = similar(ρ); ᶜKʲ .= CA.compute_kinetic(Y.c.uₕ, Y.f.sgsʲs.:(1).u₃)
ᶜq_liq = @. max(0, (Y.c.ρq_lcl + Y.c.ρq_rai) / ρ)
ᶜq_ice = @. max(0, (Y.c.ρq_icl + Y.c.ρq_sno) / ρ)
ᶜq_nn = @. max(ᶜq_liq + ᶜq_ice, Y.c.ρq_tot / ρ)
ᶜe_tot = @. Y.c.ρe_tot / ρ
ᶜT = @. TD.air_temperature(tp, ᶜe_tot - ᶜK - FT(9.81) * ᶜz, ᶜq_nn, ᶜq_liq, ᶜq_ice)
ᶜh = @. TD.total_enthalpy(tp, ᶜe_tot, ᶜT, ᶜq_nn, ᶜq_liq, ᶜq_ice)
mse_env = @. (ρ * (ᶜh - ᶜK) - ρa * sj.mse) / max(ρ - ρa, eps(FT) * ρ)
m1 = Fields.level(sj.mse, 1)
raw_m = @. (sj.mse - mse_env) / (m1 - mse_env)
f_mse = @. ifelse(on & (abs(m1 - mse_env) > 100), clamp(raw_m, FT(0), FT(1)), FT(0))
ᶜΔh = @. sj.mse + ᶜKʲ - ᶜh

ᶠw = Geometry.WVector.(Y.f.u₃)
ᶠwʲ = Geometry.WVector.(Y.f.sgsʲs.:(1).u₃)
ᶠM = @. CA.ᶠinterp(ρa) * (ᶠwʲ.components.data.:1 - ᶠw.components.data.:1)
ᶠMv = @. CA.CT3(Geometry.WVector(ᶠM))

function measure(ᶜtend, ᶜtag)
    out = ""
    for (label, mask) in (("tropics", trop), ("elsewhere", @. one(FT) - trop))
        amount = sum(@. abs(ᶜtag) * mask)
        moved = sum(@. abs(ᶜtend) * mask) * 86400 / amount
        lift = sum(@. ᶜz * ᶜtend * mask) * 86400 / sum(@. ᶜtag * mask)
        out *= "$label: moved $(sig(moved)) (net $(sig(moved / 2))), lift $(sig(lift)) m/day | "
    end
    return out
end


name = :ρe_src_sfc
ᶜtag = getproperty(Y.c, name)
ᶜφ = @. ᶜtag / ᶜE
φ1 = Fields.level(ᶜφ, 1)
ᶜχ = @. f_script * (φ1 - ᶜφ) * ᶜe
ᶠup = @. CA.ᶠupwind1(ᶠMv, ᶜχ)
ᶠce = @. ᶠMv * CA.ᶠinterp(ᶜχ)
ᶜΔX = @. (ᶜΔh + c * (sj.q_tot - Y.c.ρq_tot / ρ)) / (1 - ᶜσ)
ᶠF = @. ᶠMv * CA.ᶠinterp(ᶜΔX)
# Physical face fluxes: divide the CT3 component by the face's ∂ξ³/∂z, which is
# the ratio CT3(WVector(1))'s component.
ᶠone = @. CA.CT3(Geometry.WVector(0 * ᶠM + 1))
Pup = parent(ᶠup) ./ parent(ᶠone); Pce = parent(ᶠce) ./ parent(ᶠone); PF = parent(ᶠF) ./ parent(ᶠone)
PM = parent(ᶠM); lat = parent(ᶜlat)
Pf = parent(f_script); Pφ = parent(ᶜφ); Pe = parent(ᶜe); Pa = parent(ᶜσ); Pz = parent(ᶜz); Ptag = parent(ᶜtag)
Pzf = parent(Fields.coordinate_field(Y.f).z)
for (label, sel) in (("tropics", abs.(lat[1, :, :, 1, :]) .< 30), ("extratropics", abs.(lat[1, :, :, 1, :]) .> 35))
    Mf2 = PM[2, :, :, 1, :] .* sel
    I = argmax(Mf2)
    i, j, h = Tuple(I)
    println("== $label column (i=$i, j=$j, h=$h), lat $(sig(lat[1, i, j, 1, h]))")
    println("  level: z, a, f, φ_sfc, δφ, e [kJ/kg], tag [J/m³]")
    for k in 1:6
        println("   $k: $(sig(Pz[k,i,j,1,h])) $(sig(Pa[k,i,j,1,h])) $(sig(Pf[k,i,j,1,h])) $(sig(Pφ[k,i,j,1,h])) $(sig(Pf[k,i,j,1,h]*(Pφ[1,i,j,1,h]-Pφ[k,i,j,1,h]))) $(sig(Pe[k,i,j,1,h]/1000)) $(sig(Ptag[k,i,j,1,h]))")
    end
    println("  face: z, M [kg/m²/s], gap flux upwind, centred, as-built tag flux φ_donor·F [W/m²]")
    for k in 1:6
        Fk = PF[k,i,j,1,h]
        φd = Fk > 0 ? (k > 1 ? Pφ[k-1,i,j,1,h] : 0) : Pφ[k,i,j,1,h]
        println("   $k: $(sig(Pzf[k,i,j,1,h])) $(sig(PM[k,i,j,1,h])) $(sig(Pup[k,i,j,1,h])) $(sig(Pce[k,i,j,1,h])) $(sig(φd*Fk))")
    end
end
