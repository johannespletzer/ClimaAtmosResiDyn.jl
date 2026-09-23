@inline function _partition_total(ε, partition)
    total = zero(ε[1])
    for i in 1:length(partition)
        total += partition[i] ? ε[i] : zero(total)
    end
    return total
end
@inline _subdomain_share(ε, total, i) = min(ε[i] / total, one(total))
@inline function _blend_factor(ε̄, εʲ, total, totalʲ, room, i)
    mean_share = _subdomain_share(ε̄, total, i)
    difference = _subdomain_share(εʲ, totalʲ, i) - mean_share
    limit = mean_share * room
    FT = typeof(limit)
    return difference > limit ? min(one(FT), max(limit, zero(FT)) / difference) : one(FT)
end
@inline function _partition_blend_factor(ε̄, εʲ, total, totalʲ, room, partition)
    θ = one(room)
    for i in 1:length(partition)
        θ = partition[i] ? min(θ, _blend_factor(ε̄, εʲ, total, totalʲ, room, i)) : θ
    end
    return θ
end
struct New{partition, environment} end
@inline function (::New{partition, environment})(εʲ, ε̄, ρ, ρaʲ, ρa⁰, Aʲ, A⁰, Ā) where {partition, environment}
    FT = typeof(ρ); N = length(partition)
    total = _partition_total(ε̄, partition); totalʲ = _partition_total(εʲ, partition)
    no_exchange = (ρaʲ <= zero(FT)) | (ρa⁰ <= zero(FT)) | (Aʲ <= zero(FT)) | (A⁰ <= zero(FT)) | (Ā <= zero(FT)) | (total <= zero(FT)) | (totalʲ <= zero(FT))
    no_exchange && return ntuple(_ -> zero(FT), Val(N))
    room = min(ρ * Ā - ρaʲ * Aʲ, ρa⁰ * A⁰) / (ρaʲ * Aʲ)
    θ = _partition_blend_factor(ε̄, εʲ, total, totalʲ, room, partition)
    return ntuple(Val(N)) do i
        θᵢ = partition[i] ? θ : _blend_factor(ε̄, εʲ, total, totalʲ, room, i)
        scale = environment ? -θᵢ * (ρaʲ * Aʲ) / (ρa⁰ * A⁰) : θᵢ
        scale * (_subdomain_share(εʲ, totalʲ, i) - _subdomain_share(ε̄, total, i))
    end
end
struct Old{partition, environment} end   # dbe7435c, verbatim
@inline function (::Old{partition, environment})(εʲ, ε̄, ρ, ρaʲ, ρa⁰, Aʲ, A⁰, Ā) where {partition, environment}
    FT = typeof(ρ); N = length(partition)
    total = _partition_total(ε̄, partition); totalʲ = _partition_total(εʲ, partition)
    no_exchange = (ρaʲ <= zero(FT)) | (ρa⁰ <= zero(FT)) | (Aʲ <= zero(FT)) | (A⁰ <= zero(FT)) | (Ā <= zero(FT)) | (total <= zero(FT)) | (totalʲ <= zero(FT))
    no_exchange && return ntuple(_ -> zero(FT), Val(N))
    headroom = ρ * Ā / (ρaʲ * Aʲ)
    θ = one(FT)
    for i in 1:N
        mean_share = _subdomain_share(ε̄, total, i)
        difference = _subdomain_share(εʲ, totalʲ, i) - mean_share
        limit = mean_share * (headroom - one(FT))
        difference > limit && (θ = min(θ, max(limit, zero(FT)) / difference))
    end
    scale = environment ? -θ * (ρaʲ * Aʲ) / (ρa⁰ * A⁰) : θ
    return ntuple(Val(N)) do i
        scale * (_subdomain_share(εʲ, totalʲ, i) - _subdomain_share(ε̄, total, i))
    end
end
function measure(F, ::Type{FT}) where {FT}
    f = F{(true, true, false), true}()
    a = FT.((0.3, 0.7, 1e-4)); b = FT.((0.2, 0.8, 1e-6))
    g() = f(a, b, FT(1), FT(0.1), FT(0.9), FT(1), FT(0.99), FT(1))
    g(); return @allocated g()
end
for FT in (Float32, Float64)
    println(FT, "  old: ", measure(Old, FT), " B   new: ", measure(New, FT), " B")
    # Unconstrained cell: new == old exactly; room differs only by the min, so choose A⁰ = 1 (energies add up)
    a = FT.((0.3, 0.7)); b = FT.((0.2, 0.8)); args = (FT(1), FT(0.1), FT(0.9), FT(1), FT(1), FT(1))
    println("   unconstrained: updraft equal ", New{(true,true),false}()(a, b, args...) == Old{(true,true),false}()(a, b, args...),
            ", environment equal ", New{(true,true),true}()(a, b, args...) == Old{(true,true),true}()(a, b, args...))
end
