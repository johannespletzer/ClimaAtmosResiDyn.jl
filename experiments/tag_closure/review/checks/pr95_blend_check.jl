@inline function _partition_total(ε, partition)
    total = zero(ε[1])
    for i in 1:length(partition)
        total += partition[i] ? ε[i] : zero(total)
    end
    return total
end
@inline _subdomain_share(ε, total, i) = min(ε[i] / total, one(total))
struct ShareDifferences{partition, environment} end
@inline function _blend_factor(ε̄, εʲ, total, totalʲ, room, i)
    mean_share = _subdomain_share(ε̄, total, i)
    difference = _subdomain_share(εʲ, totalʲ, i) - mean_share
    limit = mean_share * room
    FT = typeof(limit)
    return difference > limit ? min(one(FT), max(limit, zero(FT)) / difference) : one(FT)
end
@inline function (::ShareDifferences{partition, environment})(εʲ, ε̄, ρ, ρaʲ, ρa⁰, Aʲ, A⁰, Ā) where {partition, environment}
    FT = typeof(ρ); N = length(partition)
    total = _partition_total(ε̄, partition); totalʲ = _partition_total(εʲ, partition)
    no_exchange = (ρaʲ <= zero(FT)) | (ρa⁰ <= zero(FT)) | (Aʲ <= zero(FT)) | (A⁰ <= zero(FT)) | (Ā <= zero(FT)) | (total <= zero(FT)) | (totalʲ <= zero(FT))
    no_exchange && return ntuple(_ -> zero(FT), Val(N))
    room = min(ρ * Ā - ρaʲ * Aʲ, ρa⁰ * A⁰) / (ρaʲ * Aʲ)
    θ = one(FT)
    for i in 1:N
        θ = partition[i] ? min(θ, _blend_factor(ε̄, εʲ, total, totalʲ, room, i)) : θ
    end
    return ntuple(Val(N)) do i
        θᵢ = partition[i] ? θ : _blend_factor(ε̄, εʲ, total, totalʲ, room, i)
        scale = environment ? -θᵢ * (ρaʲ * Aʲ) / (ρa⁰ * A⁰) : θᵢ
        scale * (_subdomain_share(εʲ, totalʲ, i) - _subdomain_share(ε̄, total, i))
    end
end
share(ε, part, i) = ε[i] / sum(ε[k] for k in eachindex(ε) if part[k])
for FT in (Float32, Float64)
    println("== ", FT)
    run(p, ej, eb; A0 = FT(1)) = (ShareDifferences{p, false}()(ej, eb, FT(1), FT(0.1), FT(0.9), FT(1), A0, FT(1)),
                                   ShareDifferences{p, true}()(ej, eb, FT(1), FT(0.1), FT(0.9), FT(1), A0, FT(1)))
    # 1: scarce overlay leaves the partition alone
    u2, e2 = run((true, true), FT.((0.3, 0.7)), FT.((0.2, 0.8)))
    u3, e3 = run((true, true, false), FT.((0.3, 0.7, 1e-4)), FT.((0.2, 0.8, 1e-6)))
    m_ov = FT(1e-6) / FT(1.0); φj_ov = m_ov + u3[3]
    println("1 partition equal with/without overlay: ", u2 == u3[1:2] && e2 == e3[1:2], "  updraft shares ", (FT(0.2)+u3[1], FT(0.8)+u3[2]),
            "  overlay θ ≈ ", u3[3] / (FT(1e-4)/FT(1.0) - m_ov), "  overlay bound ok: ", FT(0.1)*φj_ov <= m_ov * (1 + 4eps(FT)))
    # 2: review counterexample, 3: energies don't add up
    for (name, A0) in (("2 counterexample", FT(1)), ("3 A⁰ 1% low    ", FT(0.99)))
        eb = FT.((0.01, 0.99)); ej = FT.((0.93842, 0.06158))
        u, e = run((true, true), ej, eb; A0)
        φj = eb .+ u; φ0 = eb .+ e
        inv = FT(0.1) .* φj .+ FT(0.9) * A0 .* φ0
        println(name, ": updraft shares ", φj, "  min env share ", minimum(φ0), "  inventory ", inv, "  Σu Σe ", sum(u), " ", sum(e))
    end
    # 5: unchanged where nothing binds
    u, e = run((true, true), FT.((0.3, 0.7)), FT.((0.2, 0.8)))
    d = (FT(0.3) - FT(0.2), FT(0.7) - FT(0.8)); s = -(FT(0.1) * FT(1)) / (FT(0.9) * FT(1))
    println("5 unchanged where nothing binds: ", u == (one(FT) .* d) && e == (s .* d))
    f = ShareDifferences{(true, true, false), true}(); a = FT.((0.3, 0.7, 1e-4)); b = FT.((0.2, 0.8, 1e-6))
    f(a, b, FT(1), FT(0.1), FT(0.9), FT(1), FT(1), FT(1))
    println("6 allocations: ", @allocated f(a, b, FT(1), FT(0.1), FT(0.9), FT(1), FT(1), FT(1)))
end
