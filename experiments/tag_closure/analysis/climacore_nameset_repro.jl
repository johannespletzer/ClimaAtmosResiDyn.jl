#=
A ClimaCore-only reproducer for `CLIMACORE_ISSUE_DRAFT.md`: how long the first
`FieldMatrixWithSolver` takes to build, against the number of scalar fields
that have only a diagonal block. Run it in a fresh process for each count, so
that each time includes the compile:

    julia +1.11 --project=.buildkite \
        experiments/tag_closure/analysis/climacore_nameset_repro.jl <n>

The state is a column with `ρ`, `ρe` and `n` more center scalars, and a face
`w` coupled to `ρ` and `ρe`. The extra scalars stand for the tags. The solver
is an arrowhead solve over `ρ` and `ρe`, as ClimaAtmos uses, so the extra
scalars fall into the other group with `w`, as the tags do. Nothing is solved:
the build is what is timed.
=#
import ClimaComms
ClimaComms.@import_required_backends
import ClimaCore: CommonSpaces, Fields, MatrixFields
import ClimaCore.MatrixFields: @name, DiagonalMatrixRow, BidiagonalMatrixRow
import ClimaCore.MatrixFields: TridiagonalMatrixRow

n_tracers = parse(Int, only(ARGS))
FT = Float64
center_space = CommonSpaces.ColumnSpace(
    FT;
    z_min = 0,
    z_max = 10,
    z_elem = 10,
    staggering = CommonSpaces.CellCenter(),
)
face_space = CommonSpaces.ColumnSpace(
    FT;
    z_min = 0,
    z_max = 10,
    z_elem = 10,
    staggering = CommonSpaces.CellFace(),
)

tracer_names = Tuple(Symbol("χ$i") for i in 1:n_tracers)
center_names = (:ρ, :ρe, tracer_names...)
ᶜfields = similar(
    Fields.coordinate_field(center_space),
    NamedTuple{center_names, NTuple{length(center_names), FT}},
)
ᶠfields = similar(Fields.coordinate_field(face_space), NamedTuple{(:w,), Tuple{FT}})
parent(ᶜfields) .= 0
parent(ᶠfields) .= 0
Y = Fields.FieldVector(; c = ᶜfields, f = ᶠfields)

# The blocks. Their values do not matter, since nothing is solved.
function build_matrix(tracer_names)
    ᶜdiagonal = fill(DiagonalMatrixRow(FT(-1)), center_space)
    ᶠtridiagonal = fill(TridiagonalMatrixRow(FT(0), FT(-1), FT(0)), face_space)
    ᶜᶠbidiagonal = fill(BidiagonalMatrixRow(FT(0), FT(0)), center_space)
    ᶠᶜbidiagonal = fill(BidiagonalMatrixRow(FT(0), FT(0)), face_space)
    tracer_blocks = map(tracer_names) do name
        field_name = MatrixFields.FieldName(:c, name)
        (field_name, field_name) => copy(ᶜdiagonal)
    end
    return MatrixFields.FieldMatrix(
        (@name(c.ρ), @name(c.ρ)) => copy(ᶜdiagonal),
        (@name(c.ρe), @name(c.ρe)) => copy(ᶜdiagonal),
        (@name(c.ρ), @name(f.w)) => copy(ᶜᶠbidiagonal),
        (@name(c.ρe), @name(f.w)) => copy(ᶜᶠbidiagonal),
        (@name(f.w), @name(c.ρ)) => copy(ᶠᶜbidiagonal),
        (@name(f.w), @name(c.ρe)) => copy(ᶠᶜbidiagonal),
        (@name(f.w), @name(f.w)) => ᶠtridiagonal,
        tracer_blocks...,
    )
end

t_matrix = @elapsed A = build_matrix(tracer_names)
alg = MatrixFields.ApproximateBlockArrowheadIterativeSolve(
    @name(c.ρ),
    @name(c.ρe);
    P_alg₁ = MatrixFields.MainDiagonalPreconditioner(),
    n_iters = 1,
)
t_solver = @elapsed MatrixFields.FieldMatrixWithSolver(A, Y, alg)
t_again = @elapsed MatrixFields.FieldMatrixWithSolver(A, Y, alg)
println(
    "tracers ",
    n_tracers,
    "  blocks ",
    length(keys(A).values),
    "  FieldMatrix ",
    round(t_matrix; digits = 1),
    " s  FieldMatrixWithSolver ",
    round(t_solver; digits = 1),
    " s  again ",
    round(t_again; digits = 3),
    " s",
)
