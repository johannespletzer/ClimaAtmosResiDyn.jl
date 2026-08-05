import ClimaAtmos as CA

config = CA.AtmosConfig(
    ["config/common_configs/numerics_sphere_he6ze31.yml",
     "config/model_configs/passive_stratospheric_tracers_ci.yml"];
    job_id = "passive_stratospheric_tracers_ci",
)

include(joinpath(pkgdir(CA), ".buildkite", "ci_driver.jl"))
