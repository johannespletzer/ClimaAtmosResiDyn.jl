#=
Two checks behind E90, added by its review (2026-10-02). Post hoc. They run
on a login node in the run tree's environment, without a model build:

    cd <run tree>   # ../ClimaAtmosResiDyn-wp9-run-d3c5
    JULIA_NUM_THREADS=1 CLIMACOMMS_DEVICE=CPU CLIMACOMMS_CONTEXT=SINGLETON \
        julia +1.11 --project=.buildkite \
        <record tree>/experiments/tag_closure/analysis/wp9_profile_threads.jl

1. Threads. After `import ClimaAtmos`, `Threads.maxthreadid()` is printed and
   a plain loop is profiled at 1 ms. The samples are counted by thread id.
2. The 32-field limit. `ClimaCore`'s `propertynames(::DataLayout)` filters
   `fieldnames(T)` with `Base.filter`, which collects a tuple of 32 or more
   entries into a `Vector` (Julia 1.11 `base/tuple.jl`). The check times
   `sedimenting_tracer_names`' pattern, an `unrolled_filter` by
   `MatrixFields.has_field`, on a center field with 31, 32 and 38 entries.
=#

import Profile
import ClimaAtmos as CA
import ClimaComms
import ClimaCore: Domains, Fields, Geometry, Meshes, Spaces, MatrixFields
using ClimaCore.MatrixFields: @name, has_field

println("maxthreadid after import ClimaAtmos: ", Threads.maxthreadid(),
    ", nthreads: ", Threads.nthreads())

function work(n)
    s = 0.0
    for i in 1:n
        s += sin(i) * cos(i)
    end
    return s
end
work(10)
Profile.init(n = 10_000_000, delay = 0.001)
Profile.clear()
Profile.@profile for _ in 1:200
    work(10^6)
end
function samples_by_thread(d)
    # A sample block ends in two zeros. The thread id is 5 before the last.
    counts = Dict{Int, Int}()
    i = length(d)
    while i > 6
        if d[i] == 0 && d[i - 1] == 0
            t = Int(d[i - 5])
            counts[t] = get(counts, t, 0) + 1
            i -= 6
            while i > 1 && !(d[i] == 0 && d[i - 1] == 0)
                i -= 1
            end
        else
            i -= 1
        end
    end
    return counts
end
println(
    "profile samples by thread id: ",
    samples_by_thread(Profile.fetch(include_meta = true)),
)

const CANDIDATES = (@name(ρq_lcl), @name(ρq_icl), @name(ρq_rai), @name(ρq_sno))
sedimenting(c) = CA.unrolled_filter(name -> has_field(c, name), CANDIDATES)
domain = Domains.IntervalDomain(Geometry.ZPoint(0.0), Geometry.ZPoint(1.0);
    boundary_names = (:bottom, :top))
space = Spaces.CenterFiniteDifferenceSpace(ClimaComms.CPUSingleThreaded(),
    Meshes.IntervalMesh(domain; nelems = 10))
for n in (31, 32, 38)
    names = Tuple(
        i <= 4 ? MatrixFields.extract_first(CANDIDATES[i]) : Symbol("ρx$i")
        for i in 1:n
    )
    c = Fields.Field(NamedTuple{names, NTuple{n, Float64}}, space)
    sedimenting(c)
    bytes = @allocated sedimenting(c)
    t = @elapsed for _ in 1:10_000
        sedimenting(c)
    end
    println("$n fields: $(bytes) B and $(round(1e6 * t / 10_000; digits = 3)) μs per call")
end
