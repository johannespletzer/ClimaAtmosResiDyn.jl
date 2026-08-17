###
### Chemistry Module
###

# Gas-phase chemistry for ClimaAtmos.
# The MUSICA backend is provided by the ClimaAtmosMusica extension.

"""
    chemistry_tendency!(Yₜ, Y, p, t, ::Nothing)

No chemistry model is active.
"""
chemistry_tendency!(Yₜ, Y, p, t, ::Nothing) = nothing
