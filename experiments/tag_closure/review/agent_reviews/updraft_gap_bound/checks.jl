#=
Review checks for experiments/tag_closure/analysis/increment/updraft_gap_bound.jl.
Reads the day-1 and day-2 checkpoints of g2_v2_sphere and:
  A. verifies the level broadcast in ᶜf against a manual parent-array version;
  B. compares the script's CT3(WVector(M)) with the model's contravariant form;
  C. checks that the gap tendency integrates to zero in each column;
  D. prints f per level (with the level-1 and clamp contributions);
  E. builds f from the mse mixing line as a cross-check;
  F. compares the gap with an as-built estimate of the tags' SGS mass-flux
     transport, and with the exact factor e_updraft/(1-σ);
  G. compares redistribution (tag centroid height) instead of |change|;
  H. area-weights the turnover statistic and restricts it to the tropics.
=#
import ClimaAtmos as CA
import ClimaComms
import ClimaCore: InputOutput, Fields, Geometry, Spaces, Operators
import Statistics: median, mean, quantile
const TD = CA.TD

const ROOT = "/dss/dsstbyfs02/scratch/0D/di38kez/tag_closure/output"
const TAGS = (:tropics, :extratropics, :sfc, :rad, :mp, :new_tropics, :new_extratropics)

function read_state(run, day)
    dir = last(sort(filter(isdir, readdir(joinpath(ROOT, run); join = true))))
    path = joinpath(dir, "day$(day).0.hdf5")
    reader = InputOutput.HDF5Reader(path, ClimaComms.SingletonCommsContext())
    Y = InputOutput.read_field(reader, "Y")
    close(reader)
    return Y
end

# A verbatim copy of the script's gap_tendency.
function gap_tendency(Y, c, name)
    FT = eltype(Y)
    ρ = Y.c.ρ
    ρa = Y.c.sgsʲs.:(1).ρa
    ᶜE = @. Y.c.ρe_tot + c * ρ
    ᶜe = @. ᶜE / ρ
    ᶜtag = getproperty(Y.c, name)
    ᶜφ = @. ᶜtag / ᶜE
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
    ᶠw = Geometry.WVector.(Y.f.u₃)
    ᶠwʲ = Geometry.WVector.(Y.f.sgsʲs.:(1).u₃)
    ᶠM = @. CA.ᶠinterp(ρa) * (ᶠwʲ.components.data.:1 - ᶠw.components.data.:1)
    ᶠflux = @. CA.ᶠupwind1(CA.CT3(Geometry.WVector(ᶠM)), ᶜδφ * ᶜe)
    ᶜtendency = @. -CA.ᶜadvdivᵥ(ᶠflux)
    return (; ᶜtendency, ᶜf, ᶠM, ᶜE, ᶜφ, ᶜδφ, ᶜe, q_env, ᶠflux)
end

sig(x) = round(x, sigdigits = 3)
lv(A, k) = vec(A[k, :, :, :, :])

run = "g2_v2_sphere"
FT = Float32
c = FT(110495)
day = length(ARGS) >= 1 ? parse(Int, ARGS[1]) : 1
println("day $day -> $(day + 1)")
Y = read_state(run, day)
Y2 = read_state(run, day + 1)
println("same coordinates in both reads: ",
    parent(Fields.coordinate_field(Y.c).lat) == parent(Fields.coordinate_field(Y2.c).lat) &&
    parent(Fields.coordinate_field(Y.c).z) == parent(Fields.coordinate_field(Y2.c).z))
println("Y.c: ", propertynames(Y.c))
println("Y.c.sgsʲs.:(1): ", propertynames(Y.c.sgsʲs.:(1)))

ρ = Y.c.ρ
ρa = Y.c.sgsʲs.:(1).ρa
coord = Fields.coordinate_field(Y.c)
zc = parent(coord.z)
zf = parent(Fields.coordinate_field(Y.f).z)
lat = parent(coord.lat)
nv = size(zc, 1)
println("\n== grid: center z (mean, min, max) and face z (mean)")
for k in 1:nv
    println("  level $k: $(sig(mean(lv(zc,k)))) [$(sig(minimum(lv(zc,k)))), $(sig(maximum(lv(zc,k))))], face below $(sig(mean(lv(zf,k))))")
end

g = gap_tendency(Y, c, :ρe_src_sfc)

# A. The level broadcast.
Pρ = parent(ρ); Pρa = parent(ρa)
qj = parent(Y.c.sgsʲs.:(1).q_tot)
qenv = (parent(Y.c.ρq_tot) .- Pρa .* qj) ./ max.(Pρ .- Pρa, eps(FT) .* Pρ)
qj1 = qj[1:1, :, :, :, :]
raw = (qj .- qenv) ./ (qj1 .- qenv)
cond = (Pρa .> 1e-3 .* Pρ) .& (abs.(qj1 .- qenv) .> 1e-6)
fman = ifelse.(cond, clamp.(raw, 0, 1), 0)
println("\n== A. level broadcast: max |f_script - f_manual| = ", maximum(abs.(parent(g.ᶜf) .- fman)))
φ = parent(g.ᶜφ)
δφman = fman .* (φ[1:1, :, :, :, :] .- φ)
println("   max |δφ_script - δφ_manual| = ", maximum(abs.(parent(g.ᶜδφ) .- δφman)),
    " (max |δφ| ", maximum(abs.(δφman)), ")")

# B. The mass flux against the model's contravariant form.
ᶠct_script = @. CA.CT3(Geometry.WVector(g.ᶠM))
ᶠct_model = @. CA.ᶠinterp(ρa) * (CA.CT3(Y.f.sgsʲs.:(1).u₃) - CA.CT3(Y.f.u₃))
a1 = parent(ᶠct_script); a2 = parent(ᶠct_model)
println("\n== B. CT3(WVector(M)) vs ᶠinterp(ρa)(CT3(u₃ʲ) - CT3(u₃)): max rel diff ",
    maximum(abs.(a1 .- a2)) / maximum(abs.(a2)))
# Physical w against u₃ / (∂z/∂ξ³) computed from the face z spacing is not needed:
# WVector(Covariant3) = (∂ξ³/∂z) u₃ exactly when ∂ξ¹/∂z = ∂ξ²/∂z = 0.
M = parent(g.ᶠM)
println("   M range ", extrema(M), "; faces with M>0: ", count(>(0), M), " of ", length(M))

# C. Column conservation of the gap tendency.
colint = zeros(axes(Fields.level(Y.f, CA.half)))
colabs = zeros(axes(Fields.level(Y.f, CA.half)))
Operators.column_integral_definite!(colint, g.ᶜtendency)
Operators.column_integral_definite!(colabs, @. abs(g.ᶜtendency))
println("\n== C. column integral of gap tendency / column integral of |tendency|: max ",
    maximum(abs.(parent(colint))) / maximum(parent(colabs)),
    ", global ", sum(abs.(parent(colint))) / sum(parent(colabs)))

# The partition: tropics + extratropics shares and gaps.
gt = gap_tendency(Y, c, :ρe_src_tropics)
ge = gap_tendency(Y, c, :ρe_src_extratropics)
φsum = parent(gt.ᶜφ) .+ parent(ge.ᶜφ)
println("   partition share sum: extrema ", extrema(φsum))
println("   |gap_tr + gap_ex| / |gap_tr|, global: ",
    sum(abs.(parent(gt.ᶜtendency) .+ parent(ge.ᶜtendency))) / sum(abs.(parent(gt.ᶜtendency))))

# D. f per level.
trop = abs.(lat) .< 30
println("\n== D. f per level (all nodes | tropics): n(updraft), median f>0, frac f==1, frac raw>1, frac raw<0")
for k in 1:nv
    for (label, m) in (("all", trues(size(lat))), ("trop", trop))
        sel = cond[k, :, :, :, :] .& m[k, :, :, :, :]
        fk = fman[k, :, :, :, :][sel]
        rk = raw[k, :, :, :, :][sel]
        fpos = filter(>(0), fk)
        isempty(fk) && continue
        println("  level $k $label: n=$(length(fk)) median f>0=$(isempty(fpos) ? NaN : sig(median(fpos))) ",
            "f==1: $(sig(count(==(1), fk)/length(fk))) raw>1: $(sig(count(>(1), rk)/length(rk))) raw<0: $(sig(count(<(0), rk)/length(rk)))")
    end
end
fall = filter(>(0), vec(fman))
fabove = filter(>(0), vec(fman[2:end, :, :, :, :]))
println("  median f>0 all levels (the script's number): ", sig(median(fall)),
    "; share of those points at level 1: ", sig(count(>(0), fman[1, :, :, :, :]) / length(fall)),
    "; median f>0 above level 1: ", sig(median(fabove)))
# Mass-flux weighted f on centers (M interpolated as the mean of the two faces).
Mc = 0.5 .* (max.(M[1:end-1, :, :, :, :], 0) .+ max.(M[2:end, :, :, :, :], 0))
for k in 2:5
    w = Mc[k, :, :, :, :] .* trop[k, :, :, :, :]
    println("  level $k tropics M-weighted mean f: ", sig(sum(w .* fman[k, :, :, :, :]) / max(sum(w), eps())))
end

# Precipitation in the updraft's q_tot.
sj = Y.c.sgsʲs.:(1)
if hasproperty(sj, :q_rai)
    qp = parent(sj.q_rai) .+ (hasproperty(sj, :q_sno) ? parent(sj.q_sno) : 0)
    println("\n   updraft (q_rai+q_sno)/q_tot, tropics with updraft, median per level:")
    for k in 1:nv
        sel = cond[k, :, :, :, :] .& trop[k, :, :, :, :]
        v = (qp[k, :, :, :, :] ./ max.(qj[k, :, :, :, :], 1f-12))[sel]
        isempty(v) || println("     level $k: median $(sig(median(v))), 90th pct $(sig(quantile(v, 0.9)))")
    end
end

# E. Thermodynamics for mse and h.
tp = TD.Parameters.ThermodynamicsParameters(CA.CP.create_toml_dict(FT))
grav = FT(9.81)
ᶜK = similar(ρ); ᶜK .= CA.compute_kinetic(Y.c.uₕ, Y.f.u₃)
ᶜKʲ = similar(ρ); ᶜKʲ .= CA.compute_kinetic(Y.c.uₕ, Y.f.sgsʲs.:(1).u₃)
ᶜz = Fields.coordinate_field(Y.c).z
ᶜq_liq = @. max(0, (Y.c.ρq_lcl + Y.c.ρq_rai) / ρ)
ᶜq_ice = @. max(0, (Y.c.ρq_icl + Y.c.ρq_sno) / ρ)
ᶜq_nn = @. max(ᶜq_liq + ᶜq_ice, Y.c.ρq_tot / ρ)
ᶜe_tot = @. Y.c.ρe_tot / ρ
ᶜT = @. TD.air_temperature(tp, ᶜe_tot - ᶜK - grav * ᶜz, ᶜq_nn, ᶜq_liq, ᶜq_ice)
ᶜh = @. TD.total_enthalpy(tp, ᶜe_tot, ᶜT, ᶜq_nn, ᶜq_liq, ᶜq_ice)
println("\n== E. T range ", extrema(parent(ᶜT)), ", e = E/ρ range ", extrema(parent(g.ᶜe)))
ᶜmse = @. ᶜh - ᶜK
ᶜmse_env = @. (ρ * ᶜmse - ρa * sj.mse) / max(ρ - ρa, eps(FT) * ρ)
msej = parent(sj.mse); msee = parent(ᶜmse_env)
rawm = (msej .- msee) ./ (msej[1:1, :, :, :, :] .- msee)
condm = (Pρa .> 1e-3 .* Pρ) .& (abs.(msej[1:1, :, :, :, :] .- msee) .> 100)
fmse = ifelse.(condm, clamp.(rawm, 0, 1), 0)
println("   f from q_tot vs f from mse, tropics with updraft, per level: median f_q, median f_mse, median |f_q - f_mse|, frac raw_mse outside [0,1]")
for k in 2:nv
    sel = cond[k, :, :, :, :] .& condm[k, :, :, :, :] .& trop[k, :, :, :, :]
    count(sel) < 10 && continue
    fq = fman[k, :, :, :, :][sel]; fm = fmse[k, :, :, :, :][sel]; rm = rawm[k, :, :, :, :][sel]
    println("     level $k: n=$(count(sel)) f_q $(sig(median(fq))) f_mse $(sig(median(fm))) |diff| $(sig(median(abs.(fq .- fm)))) outside $(sig(count(x -> x < 0 || x > 1, rm)/length(rm)))")
end

# The mass flux per face in the tropics, and how much of it the f threshold drops.
ftrop = abs.(parent(Fields.coordinate_field(Y.f).lat)) .< 30
aj = Pρa ./ Pρ
println("\n   tropics, per face: sum M+ [kg/m²/s over nodes], median M over M>0, share of M+ whose donor below has f=0 by the threshold; median a below")
for k in 2:nv
    Mk = max.(M[k, :, :, :, :], 0) .* ftrop[k, :, :, :, :]
    donor_off = .!cond[k-1, :, :, :, :]
    pos = filter(>(0), vec(Mk))
    println("     face $k (z≈$(sig(mean(lv(zf,k))))): ΣM+ $(sig(sum(Mk))), median $(isempty(pos) ? NaN : sig(median(pos))), dropped $(sig(sum(Mk .* donor_off)/max(sum(Mk), eps()))), a(k-1) median $(sig(median(vec(aj[k-1, :, :, :, :][trop[k-1, :, :, :, :]]))))")
end

# F. The as-built SGS transport of a tag, and the gap with the exact factor.
# Parent flux of E per updraft, summed with the environment's under mass-flux
# balance: M (hʲ - h + c (qʲ - q)) / (1 - σ), centred as with
# edmfx_sgsflux_upwinding: none. Each tag takes it times the donor's share,
# the donor chosen by the sign of the flux, as in _sgs_energy_source_tag_fluxes!.
ᶜσ = @. ρa / ρ
ᶜΔh = @. sj.mse + ᶜKʲ - ᶜh
ᶜΔX = @. (ᶜΔh + c * (sj.q_tot - Y.c.ρq_tot / ρ)) / (1 - ᶜσ)
ᶠMvec = @. CA.CT3(Geometry.WVector(g.ᶠM))
ᶠF = @. ᶠMvec * CA.ᶠinterp(ᶜΔX)
println("   (hʲ - h) in tropics with updraft, per level median [J/kg]:")
Δh = parent(ᶜΔh)
for k in 1:nv
    sel = cond[k, :, :, :, :] .& trop[k, :, :, :, :]
    count(sel) < 10 && continue
    println("     level $k: $(sig(median(Δh[k, :, :, :, :][sel]))), e = E/ρ median $(sig(median(parent(g.ᶜe)[k, :, :, :, :][sel])))")
end

tropics_mask = @. ifelse(abs(coord.lat) < 30, one(FT), zero(FT))
elsewhere_mask = @. one(FT) - tropics_mask
println("\n== F/G. per tag, tropics: ∫|.|·86400/∫|tag| for: gap (script), gap×(eʲ/e)/(1-σ), as-built SGS; half of gap = net amount moved;")
println("         centroid-height change in a day [m]: gap, as-built SGS, actual (day 1 -> 2); net and gross change")
for tag in TAGS
    name = Symbol(:ρe_src_, tag)
    hasproperty(Y.c, name) || continue
    gg = gap_tendency(Y, c, name)
    ᶜtag = getproperty(Y.c, name)
    ᶠG_exact = @. CA.ᶠupwind1(ᶠMvec, gg.ᶜδφ * (gg.ᶜe + ᶜΔh) / (1 - ᶜσ))
    ᶜgap_exact = @. -CA.ᶜadvdivᵥ(ᶠG_exact)
    ᶜshare = @. ifelse(gg.ᶜE > 0, clamp(ᶜtag / gg.ᶜE, FT(0), FT(1)), FT(0))
    ᶜbuilt = @. -CA.ᶜadvdivᵥ(ᶠF * ifelse(
        CA._is_upward(ᶠF),
        CA.ᶠbottom_bias_zero(ᶜshare),
        CA.ᶠtop_bias_zero(ᶜshare),
    ))
    ᶜnext = similar(ᶜtag)
    parent(ᶜnext) .= parent(getproperty(Y2.c, name))
    for (label, mask) in (("tropics", tropics_mask), ("elsewhere", elsewhere_mask))
        amount = sum(@. abs(ᶜtag) * mask)
        amount > 0 || continue
        gap = sum(@. abs(gg.ᶜtendency) * mask) * 86400 / amount
        gapx = sum(@. abs(ᶜgap_exact) * mask) * 86400 / amount
        built = sum(@. abs(ᶜbuilt) * mask) * 86400 / amount
        tot = sum(@. ᶜtag * mask)
        tot2 = sum(@. ᶜnext * mask)
        Z1 = sum(@. ᶜz * ᶜtag * mask) / tot
        Z2 = sum(@. ᶜz * ᶜnext * mask) / tot2
        dZgap = sum(@. ᶜz * gg.ᶜtendency * mask) * 86400 / tot
        dZbuilt = sum(@. ᶜz * ᶜbuilt * mask) * 86400 / tot
        println("  $(rpad(tag, 17)) $label: gap $(sig(gap)) exact $(sig(gapx)) built $(sig(built)) net-moved $(sig(gap/2)) | ",
            "Z $(sig(Z1)) m, dZ gap $(sig(dZgap)) built $(sig(dZbuilt)) actual $(sig(Z2 - Z1)) | net change $(sig((tot2 - tot)/tot))")
    end
end

# σ where the gap acts, and the gap's vertical profile for sfc in the tropics.
σp = Pρa ./ Pρ
for (label, m) in (("tropics", trop), ("elsewhere", .!trop))
    v = σp[cond .& m]
    isempty(v) || println("\n   σ = ρa/ρ where f is defined, $label: median $(sig(median(v))), 90th $(sig(quantile(v, 0.9))), max $(sig(maximum(v)))")
end
tend = parent(g.ᶜtendency); tag = parent(Y.c.ρe_src_sfc)
println("   sfc, tropics, per level: node-sum of gap tendency·86400 / node-sum of tag at that level, and median φ")
for k in 1:6
    m = trop[k, :, :, :, :]
    println("     level $k: $(sig(sum(tend[k, :, :, :, :][m]) * 86400 / sum(tag[k, :, :, :, :][m]))), φ median $(sig(median(φ[k, :, :, :, :][m])))")
end

# H. Turnover, area-weighted and in the tropics.
column_mass = zeros(axes(Fields.level(Y.f, CA.half)))
below = @. ifelse(ᶜz < 10000, one(FT), zero(FT))
Operators.column_integral_definite!(column_mass, @. ρ * below)
Mmax = dropdims(maximum(max.(M, 0); dims = 1); dims = 1)
τ = vec(parent(column_mass)) ./ max.(vec(Mmax), 1e-12) ./ 86400
area = similar(column_mass)
parent(area) .= 1
ᶠlat = vec(parent(Fields.coordinate_field(Fields.level(Y.f, CA.half)).lat))
under = similar(column_mass)
parent(under) .= reshape(FT.(τ .< 1), size(parent(under)))
tropc = similar(column_mass)
parent(tropc) .= reshape(FT.(abs.(ᶠlat) .< 30), size(parent(tropc)))
println("\n== H. turnover < 1 day: node share $(sig(count(<(1), τ)/length(τ))), area share $(sig(sum(under)/sum(area))), ",
    "tropics area share $(sig(sum(@. under * tropc)/sum(tropc)))")
println("   column mass below 10 km (median) ", sig(median(vec(parent(column_mass)))), " kg/m²")
# Where along the column the largest M sits.
kmax = [argmax(max.(M[:, i, j, 1, h], 0)) for i in 1:size(M, 2), j in 1:size(M, 3), h in 1:size(M, 5)]
sel = vec(τ .< 1)
println("   face index of M_max for columns under 1 day: ", [k => count(==(k), vec(kmax)[sel]) for k in 1:size(M, 1)])
