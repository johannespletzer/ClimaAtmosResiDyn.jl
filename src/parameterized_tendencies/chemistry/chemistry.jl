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

Fallback for a configured chemistry model whose backend is not loaded: source
terms are provided by the `ClimaAtmosMusica` extension, and without it chemistry
is a no-op.

Dispatch is on the abstract type rather than on `GasPhaseChem` so that the
extension *adds* the concrete `::GasPhaseChem` method instead of replacing this
one. A package extension may only add methods; defining the same signature the
parent already defines is a method overwrite, which Julia rejects while
precompiling the extension:

    ERROR: Method overwriting is not permitted during Module precompilation.

With `Musica` loaded, `::GasPhaseChem` is the more specific method and wins;
without it, this fallback applies, which is the behavior this file has always
had.
"""
chemistry_tendency!(Yₜ, Y, p, t, ::AbstractChemistryModel) = nothing
