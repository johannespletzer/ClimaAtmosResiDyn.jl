###
### Chemistry Module
###

# Gas-phase chemistry for ClimaAtmos.
# The MUSICA backend is provided by the ClimaAtmosMusica extension;
# this file defines only the fallback for when no chemistry is loaded.

"""
    chemistry_tendency!(Yₜ, Y, p, t, ::Nothing)

No chemistry model is active.
"""
chemistry_tendency!(Yₜ, Y, p, t, ::Nothing) = nothing

"""
    chemistry_tendency!(Yₜ, Y, p, t, ::AbstractChemistryModel)

No-op fallback for a chemistry model that contributes no tendency of its own.

`GasPhaseChem` lands here when `Musica` is not loaded, and the
`ClimaAtmosMusica` extension's `::GasPhaseChem` method — being strictly more
specific — takes over when it is. The fallback must *not* be written on
`::GasPhaseChem` itself: an extension may add methods to a function but may not
overwrite one, and doing so makes `ClimaAtmosMusica` fail to precompile with
"Method overwriting is not permitted during Module precompilation".

A chemistry model with real source terms defines its own method (see
`stratospheric_passive_tracers.jl`), which likewise wins over this one.
"""
chemistry_tendency!(Yₜ, Y, p, t, ::AbstractChemistryModel) = nothing
