###
### Chemistry Module
###

# Gas-phase chemistry for ClimaAtmos.
# The MUSICA backend is provided by the ClimaAtmosMusica extension.

"""
    chemistry_tendency!(Yₜ, Y, p, t, chemistry_model)

Add gas-phase chemistry source terms to `Yₜ` in place; return `nothing`.

Dispatches on the chemistry model in `p.atmos`:

  - `::Nothing`: no chemistry is active; the tendency is a no-op.
  - `::AbstractChemistryModel`: a no-op fallback, so a model whose tendency lives
    outside the package is still callable when that code is not loaded.
  - `::GasPhaseChem`: the MUSICA-backed method comes from the `ClimaAtmosMusica`
    extension, loaded automatically when `Musica` is imported alongside `ClimaAtmos`.
    Without it the fallback above applies. It cannot also be defined here: an
    extension may add a method but not overwrite one, so a `::GasPhaseChem` method in
    this file makes the extension fail to precompile.
  - `::StratosphericPassiveTracers`: defined in `stratospheric_passive_tracers.jl`.
"""
chemistry_tendency!(Yₜ, Y, p, t, ::Nothing) = nothing
chemistry_tendency!(Yₜ, Y, p, t, ::AbstractChemistryModel) = nothing
