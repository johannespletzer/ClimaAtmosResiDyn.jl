#=
A prototype of P4's fix, loaded into ClimaAtmos from outside so that the model's
own code stays untouched while it is tested. Include it after `import ClimaAtmos
as CA`, before building a simulation.

E44c and the inference profiles found that the build grows with the tags inside
`FieldMatrixWithSolver`, when ClimaCore builds the Jacobian's solver. No solver
group names the tags, so they fall into the remaining group, which the
approximate arrowhead solve iterates over, together with the velocities. Every
matrix product in that solve then carries the tag fields' names, and the work
to compile those products grows faster than the number of names.

The tags couple to nothing. Their only Jacobian block is their own diagonal,
and no other block refers to them. So they can be solved on their own, before
the rest, without changing the rest. This replaces `jacobian_cache` with a
version that does that:

  - it finds every field whose only block is its own diagonal and which no other
    block names, as a row or a column or a part of one;
  - it wraps the model's solver in a `BlockLowerTriangularSolve` that solves
    those fields first.

The fields are solved as the model's solver solves them now, so that the result
stays the same to the bit. Under the approximate arrowhead solve, the remaining
group's preconditioner inverts each such block exactly, and the iteration
repeats that `n_iters` times from zero. A `StationaryIterativeSolve` with a
`BlockDiagonalPreconditioner` and the same `n_iters` does the same. Under the
exact arrowhead solve, the block is inverted once, which `BlockDiagonalSolve`
does.
=#

import ClimaCore.MatrixFields as MatrixFields

@eval CA begin
    # Whether one field name, as a string, is the other or a part of it.
    _names_overlap(a::String, b::String) =
        a == b || startswith(a, b * ".") || startswith(b, a * ".")

    # The fields whose only block is their own diagonal, and which no other
    # block names. This runs once, when the Jacobian is built. It compares the
    # names as strings, so that nothing here compiles once per pair of name
    # types, which would grow the build again.
    function uncoupled_jacobian_names(block_pairs)
        keys = Any[pair.first for pair in block_pairs]
        rows = String[string(key[1]) for key in keys]
        columns = String[string(key[2]) for key in keys]
        uncoupled = Any[]
        for (i, key) in enumerate(keys)
            rows[i] == columns[i] || continue
            mentions = count(
                j ->
                    _names_overlap(rows[i], rows[j]) ||
                    _names_overlap(rows[i], columns[j]),
                eachindex(keys),
            )
            mentions == 1 && push!(uncoupled, key[1])
        end
        return Tuple(uncoupled)
    end

    function split_uncoupled_solver(alg, uncoupled_names, approximate_solve_iters)
        isempty(uncoupled_names) && return alg
        alg₁ =
            alg isa MatrixFields.SchurComplementReductionSolve ?
            MatrixFields.StationaryIterativeSolve(;
                P_alg = MatrixFields.BlockDiagonalPreconditioner(),
                n_iters = approximate_solve_iters,
            ) : MatrixFields.BlockDiagonalSolve()
        return MatrixFields.BlockLowerTriangularSolve(
            uncoupled_names...;
            alg₁,
            alg₂ = alg,
        )
    end

    function jacobian_cache(alg::ManualSparseJacobian, Y, atmos)
        derivative_flags = _derivative_flags(atmos, Y)
        (; topography_flag, diffusion_flag) = derivative_flags
        FT = Spaces.undertype(axes(Y.c))

        process_block_pairs = merge_jacobian_blocks((
            sgs_advection_jacobian_blocks(Y, atmos)...,
            advection_jacobian_blocks(Y, atmos, topography_flag)...,
            diffusion_jacobian_blocks(Y, atmos, diffusion_flag)...,
            sedimentation_jacobian_blocks(Y, atmos)...,
            sgs_massflux_jacobian_blocks(Y, atmos)...,
        ))
        block_pairs = (
            process_block_pairs...,
            fallback_identity_blocks(process_block_pairs, Y, FT)...,
        )
        matrix = MatrixFields.FieldMatrix(block_pairs...)

        full_alg = split_uncoupled_solver(
            jacobian_solver_algorithm(
                Y,
                atmos,
                diffusion_flag,
                alg.approximate_solve_iters,
            ),
            uncoupled_jacobian_names(block_pairs),
            alg.approximate_solve_iters,
        )

        return (;
            matrix = MatrixFields.FieldMatrixWithSolver(matrix, Y, full_alg),
            derivative_flags,
        )
    end
end
