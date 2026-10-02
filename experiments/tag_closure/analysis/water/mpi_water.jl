#=
W59 (design/MPI_PARITY.md), reported only, added after the pre-registration
at the coordinator's request: how much water the run holds, as the strength of
the two-rank check. The atmosphere starts dry, so this water came in through
the surface flux.

    julia +1.11 --project=<run tree>/.buildkite mpi_water.jl DIR

For each checkpoint in DIR it prints the global integrals of `ρq_tot`, of the
1M species and of each water tag in `Y.c`, in kg, and `ρq_tot`'s integral as a
global mean column in kg m⁻². Each integral is ClimaCore's `sum` over the
cell-centre field, on one process.
=#

import ClimaComms
import ClimaCore: InputOutput, Fields

const EARTH_RADIUS = 6.371e6

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

dir = only(ARGS)
for file in checkpoints(dir)
    Y = read_state(joinpath(dir, file))
    names = filter(propertynames(Y.c)) do name
        s = string(name)
        startswith(s, "ρq_") || startswith(s, "ρq_tag_")
    end
    total = sum(Y.c.ρq_tot)
    parts = join(["$(name) $(sum(getproperty(Y.c, name)))" for name in names], ", ")
    println(
        "$file: global mean column water $(total / (4π * EARTH_RADIUS^2)) kg m⁻²; ",
        parts,
    )
end
