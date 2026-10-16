#=
Tests of the fork's `propertynames` method for data layouts whose element type
is a `NamedTuple` (src/utils/datalayout_property_names.jl).

ClimaCore builds the names with `filter`, which builds a tuple of 32 or more
names at run time. Every name lookup on a large `Y.c` then allocates. The
fork's method gives the same names as a compile-time constant.
=#

using Test
import ClimaAtmos as CA
import ClimaCore
import ClimaCore: Fields, DataLayouts, Geometry, MatrixFields
import ClimaCore.MatrixFields: @name

include("test_helpers.jl")

# A type of size zero, like the singleton bases that ClimaCore hides.
struct ZeroSizeEntry end

# ClimaCore's rule, written out.
climacore_rule(::Type{T}) where {T} =
    filter(name -> sizeof(fieldtype(T, name)) > 0, fieldnames(T))

# ClimaCore's own method, called past the fork's.
climacore_names(data) =
    Base.invoke(propertynames, Tuple{DataLayouts.DataLayout}, data)

# A state like `Y.c` with `n` top-level fields: the 1M water species, a passive
# tracer, tags, a process record without the `ρ` prefix, a zero-size entry and
# one updraft.
function property_names_state(n; FT = Float32)
    (; cent_space) = get_cartesian_spaces(; FT)
    sgs_names = (:ρa, :mse, :q_tot, :q_lcl, :q_icl, :q_rai, :q_sno, :q_gas_A)
    sgs_type = NamedTuple{sgs_names, NTuple{length(sgs_names), FT}}
    base = (:ρ, :ρe_tot, :ρq_tot, :ρq_lcl, :ρq_icl, :ρq_rai, :ρq_sno)
    tail = (:ρq_gas_A, :prc_e_test, :zero_size, :sgsʲs)
    ntags = n - length(base) - length(tail)
    tags = ntuple(i -> Symbol(:ρq_tag_, i), ntags)
    names = (base..., tags..., tail...)
    types = (ntuple(_ -> FT, n - 2)..., ZeroSizeEntry, Tuple{sgs_type})
    coords = Fields.coordinate_field(cent_space)
    c = similar(coords, NamedTuple{names, Tuple{types...}})
    return Fields.FieldVector(; c)
end

# Allocation of one call, after a call that compiles it.
call_allocations(f::F, x) where {F} = (f(x); @allocated f(x))

lookups(Y) = (
    MatrixFields.has_field(Y, @name(c.ρq_tot)),
    MatrixFields.has_field(Y, @name(c.ρtke)),
    MatrixFields.has_field(Y, @name(c.sgsʲs)),
    MatrixFields.has_field(Y.c, @name(ρq_tag_1)),
    MatrixFields.top_level_names(Y.c),
    hasproperty(Y.c, :ρq_tot),
    hasproperty(Y.c, :ρtke),
    propertynames(Y.c),
)
updraft_lookups(updraft) = (
    MatrixFields.has_field(updraft, @name(q_rai)),
    MatrixFields.has_field(updraft, @name(n_rai)),
    MatrixFields.top_level_names(updraft),
)

# The name walks the per-step code calls.
const name_walks = (
    CA.gs_tracer_names,
    CA.specific_gs_tracer_names,
    CA.sgs_tracer_names,
    CA.sedimenting_tracer_names,
    CA.sedimenting_mass_names,
    CA.sedimenting_sgs_tracer_names,
    CA.sedimenting_sgs_mass_names,
    CA.microphysics_tracer_names,
    CA.diffused_gs_scalar_names,
    CA.advected_gs_scalar_names,
    CA.passive_gs_tracer_names,
    CA.passive_sgs_tracer_names,
    CA.advected_sgs_scalar_names,
)

# 32 is the first count at which Julia's `filter` builds its tuple at run time.
const field_counts = (31, 32, 38, 54)

# On Julia 1.10 these walks do not infer a concrete return type at any field
# count, 31 included, with or without the fork's method. Their answers and
# allocation still hold. `@test_broken` reports it if 1.10 starts inferring them.
const walks_not_inferred_on_1_10 =
    (CA.gs_tracer_names, CA.specific_gs_tracer_names, CA.passive_gs_tracer_names)
const float_types = (Float32, Float64)

@testset "answers equal ClimaCore's rule" begin
    for FT in float_types, n in field_counts
        Y = property_names_state(n; FT)
        data = Fields.field_values(Y.c)
        T = eltype(data)
        @test propertynames(data) == climacore_names(data)
        @test propertynames(data) == climacore_rule(T)
        @test propertynames(Y.c) == climacore_names(data)
        updraft = Fields.field_values(Y.c.sgsʲs.:(1))
        @test propertynames(updraft) == climacore_names(updraft)
    end
    # Element types that are not a `NamedTuple` keep ClimaCore's method.
    (; cent_space) = get_cartesian_spaces(; FT = Float32)
    coords = Fields.coordinate_field(cent_space)
    for field in (
        similar(coords, Geometry.Covariant3Vector{Float32}),
        similar(coords, Tuple{Float32, Float32}),
        similar(coords, Float32),
    )
        data = Fields.field_values(field)
        @test propertynames(data) == climacore_names(data)
        @test which(propertynames, (typeof(data),)).module === DataLayouts
    end
end

@testset "zero-size entries are hidden" begin
    for n in field_counts
        Y = property_names_state(n)
        @test !(:zero_size in propertynames(Fields.field_values(Y.c)))
        @test :zero_size in fieldnames(eltype(Fields.field_values(Y.c)))
    end
end

@testset "no allocation and inferred at 31, 32, 38 and 54 fields" begin
    for FT in float_types, n in field_counts
        Y = property_names_state(n; FT)
        @test length(propertynames(Y.c)) == n - 1
        updraft = Y.c.sgsʲs.:(1)
        @test (@inferred updraft_lookups(updraft)) isa Tuple
        @test call_allocations(updraft_lookups, updraft) == 0
        # The state as a `FieldVector` and as a `NamedTuple`.
        for state in (Y, (; c = Y.c))
            @test (@inferred lookups(state)) isa Tuple
            @test call_allocations(lookups, state) == 0
            for walk in name_walks
                @testset "$walk, $n fields, $FT, $(nameof(typeof(state)))" begin
                    if VERSION < v"1.11" && walk in walks_not_inferred_on_1_10
                        @test_broken (@inferred walk(state)) isa Tuple
                    else
                        @test (@inferred walk(state)) isa Tuple
                    end
                    @test call_allocations(walk, state) == 0
                end
            end
        end
    end
end

@testset "the method is the fork's" begin
    for n in field_counts
        data = Fields.field_values(property_names_state(n).c)
        @test which(propertynames, (typeof(data),)).module === CA
    end
end

# If this fails, ClimaCore's `propertynames` for data layouts has changed.
# Then the fork's method must be checked against ClimaCore's new code before
# the test is changed.
@testset "guard: ClimaCore's method is unchanged" begin
    data = Fields.field_values(property_names_state(31).c)
    @test climacore_names(data) == climacore_rule(eltype(data))
    method = which(propertynames, Tuple{DataLayouts.DataLayout})
    @test method.module === DataLayouts
    @test endswith(string(method.file), "DataLayouts.jl")
end
