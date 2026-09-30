using ForwardDiff
struct Jac end
const D = ForwardDiff.Dual{Jac}
# The fork's overrides (autodiff_utils.jl:199-226), specialised on the tag Jac.
for func in (:isequal, :isless, :<, :>, :(==), :!=, :<=, :>=)
    @eval Base.$func(a::ForwardDiff.Dual{Jac}, b::ForwardDiff.Dual{Jac}) =
        $func(ForwardDiff.value(a), ForwardDiff.value(b))
    for R in (AbstractFloat, Integer)
        @eval Base.$func(a::ForwardDiff.Dual{Jac}, b::$R) = $func(ForwardDiff.value(a), b)
        @eval Base.$func(a::$R, b::ForwardDiff.Dual{Jac}) = $func(a, ForwardDiff.value(b))
    end
end
target_gain(Δ, P) = ifelse(P < zero(P), zero(Δ), max(Δ, 0))
withheld(Δ, P) = ifelse(P < zero(P), max(Δ, zero(Δ)), zero(Δ))
for (v, pΔ) in ((2.0, 1.0), (0.0, 1.0), (-0.0, 1.0), (-1.0, 1.0)),
    P in (-1.0, -0.0, 0.0, 1.0)

    Δ = D(v, ForwardDiff.Partials((pΔ, 0.0)));
    Pd = D(P, ForwardDiff.Partials((0.0, 1.0)))
    g = target_gain(Δ, Pd);
    w = withheld(Δ, Pd)
    ok =
        isequal(ForwardDiff.value(g), target_gain(v, P)) &&
        isequal(ForwardDiff.value(w), withheld(v, P))
    println(
        "Δ=$(v) P=$(P): G=$(ForwardDiff.value(g)) ∂G=$(Tuple(ForwardDiff.partials(g))) w=$(ForwardDiff.value(w)) ∂w=$(Tuple(ForwardDiff.partials(w))) values isequal Float64: $ok",
    )
end
# Without the override (another tag): ForwardDiff 1.x compares partials when values tie.
Δ = ForwardDiff.Dual{Nothing}(-0.0, 1.0);
println(
    "untagged: max(-0.0+ε,0) = ",
    max(Δ, 0),
    "  (-0.0 - ε) < 0: ",
    ForwardDiff.Dual{Nothing}(-0.0, -1.0) < 0,
)
@show Base.return_types(target_gain, (D{Float64, 2}, D{Float64, 2}))
@show Base.return_types(withheld, (D{Float64, 2}, D{Float64, 2}))
