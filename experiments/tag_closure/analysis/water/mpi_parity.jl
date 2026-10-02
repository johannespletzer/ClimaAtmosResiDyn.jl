#=
W59, criterion 3 on two MPI ranks (design/MPI_PARITY.md): compare the
checkpoints of two runs, field by field.

    julia +1.11 --project=<run tree>/.buildkite mpi_parity.jl \
        parity UNTAGGED_DIR TAGGED_DIR
    julia +1.11 --project=<run tree>/.buildkite mpi_parity.jl \
        report ONE_RANK_DIR TWO_RANK_DIR

Each directory holds the run's `day*.hdf5` checkpoints. Each checkpoint is read
on one process (`SingletonCommsContext`), so a file that two ranks wrote is
read whole.

`parity` is the judged comparison. The checkpoints of the first directory set
the times. The second directory must have a checkpoint at each of them, and no
time may be missing on either side. At each time, every scalar field of the
first state (every property chain of `Y`, down to a scalar or a vector field)
must exist in the second state and be equal bit for bit: the raw bits of each
value, so a signed zero or a NaN payload counts. The second state may have more
fields, the tags. The exit status is 0 only when every field at every time is
equal and at least one time was compared.

`report` compares the fields the two states share, at the times both have, and
judges nothing. For each field it prints the number of points that differ,
the largest absolute difference, and that difference relative to the field's
largest absolute value. It is for one rank against two, where the order of the
sums at the ranks' boundary may differ.
=#

import ClimaComms
import ClimaCore: InputOutput, Fields

checkpoints(dir) =
    sort(filter(f -> startswith(f, "day") && endswith(f, ".hdf5"), readdir(dir)))

function read_state(path)
    reader = InputOutput.HDF5Reader(path, ClimaComms.SingletonCommsContext())
    try
        return InputOutput.read_field(reader, "Y")
    finally
        close(reader)
    end
end

# Every property chain of `Y` down to a field without property names. A vector
# field, such as `uₕ`, is one leaf. Its parent array holds every component.
leaves(Y) = Dict(Tuple(pc) => pc for pc in Fields.property_chains(Y))

leaf_values(Y, pc) = vec(Array(parent(Fields.single_field(Y, pc, identity))))

bits(x::AbstractVector{Float64}) = reinterpret(UInt64, x)
bits(x::AbstractVector{Float32}) = reinterpret(UInt32, x)

label(pc) = "Y." * join(string.(pc), ".")

function parity(dir_a, dir_b)
    files = checkpoints(dir_a)
    isempty(files) && (println("FAIL no checkpoints in $dir_a"); return false)
    missing_b = setdiff(files, checkpoints(dir_b))
    extra_b = setdiff(checkpoints(dir_b), files)
    ok = isempty(missing_b) && isempty(extra_b)
    isempty(missing_b) || println("FAIL checkpoints missing in the second run: ", missing_b)
    isempty(extra_b) || println("FAIL checkpoints only in the second run: ", extra_b)
    n_fields = 0
    n_values = 0
    for file in files
        file in missing_b && continue
        Y_a = read_state(joinpath(dir_a, file))
        Y_b = read_state(joinpath(dir_b, file))
        chains_a = leaves(Y_a)
        chains_b = leaves(Y_b)
        equal_here = 0
        for (key, pc) in sort(collect(chains_a); by = first)
            if !haskey(chains_b, key)
                println("FAIL $file $(label(pc)) is missing in the second run")
                ok = false
                continue
            end
            a = leaf_values(Y_a, pc)
            b = leaf_values(Y_b, chains_b[key])
            same = length(a) == length(b) && eltype(a) == eltype(b) && bits(a) == bits(b)
            n_fields += 1
            n_values += length(a)
            if same
                equal_here += 1
            else
                ok = false
                n_diff = length(a) == length(b) ? count(bits(a) .!= bits(b)) : -1
                largest = length(a) == length(b) ? maximum(abs, a .- b) : NaN
                println(
                    "FAIL $file $(label(pc)): $n_diff of $(length(a)) values differ, \
                    largest difference $largest",
                )
            end
        end
        extra = sort([label(pc) for (key, pc) in chains_b if !haskey(chains_a, key)])
        println(
            "$file: $equal_here of $(length(chains_a)) fields bit for bit; \
            only in the second run: $(length(extra))",
        )
        file == first(files) && println("   only in the second run: ", join(extra, ", "))
    end
    n_fields > 0 || (ok = false)
    println(
        ok ? "PASS" : "FAIL",
        " parity: $(length(files)) checkpoints, $n_fields field comparisons, \
        $n_values values",
    )
    return ok
end

function report(dir_a, dir_b)
    files = intersect(checkpoints(dir_a), checkpoints(dir_b))
    println("checkpoints in both: ", length(files))
    worst = Dict{String, Tuple{Float64, String}}()
    for file in files
        Y_a = read_state(joinpath(dir_a, file))
        Y_b = read_state(joinpath(dir_b, file))
        chains_a = leaves(Y_a)
        chains_b = leaves(Y_b)
        for (key, pc) in sort(collect(chains_a); by = first)
            haskey(chains_b, key) || continue
            a = leaf_values(Y_a, pc)
            b = leaf_values(Y_b, chains_b[key])
            n_diff = count(bits(a) .!= bits(b))
            largest = maximum(abs, a .- b)
            scale = maximum(abs, a)
            relative = scale > 0 ? largest / scale : largest
            println(
                "$file $(rpad(label(pc), 40)) differ $(lpad(n_diff, 7)) of $(length(a)), \
                largest $largest, relative $relative",
            )
            name = label(pc)
            if relative > get(worst, name, (-1.0, ""))[1]
                worst[name] = (relative, file)
            end
        end
    end
    println("largest relative difference over all checkpoints, by field:")
    for name in sort(collect(keys(worst)))
        relative, file = worst[name]
        println("   $(rpad(name, 40)) $relative ($file)")
    end
    return true
end

mode, dir_a, dir_b = ARGS
if mode == "parity"
    exit(parity(dir_a, dir_b) ? 0 : 1)
elseif mode == "report"
    report(dir_a, dir_b)
else
    error("The first argument must be `parity` or `report`, got $(repr(mode)).")
end
