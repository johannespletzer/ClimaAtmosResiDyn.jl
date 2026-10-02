## prof88_a: timed excess 6.277 ms

  - untagged: 2.68 samples per timed ms
  - water: 2.24 samples per timed ms
  - energy: 2.88 samples per timed ms
  - both: 2.52 samples per timed ms

time_phase:
  - implicit tendency: 2.60 ms, 41.4%
  - explicit tendency: 2.08 ms, 33.2%
  - jacobian: 1.79 ms, 28.6%
  - constrain_state!: 0.04 ms, 0.6%
  - callbacks: 0.03 ms, 0.5%
  - dss!: -0.00 ms, -0.0%

tag_entry:
  - (not tag code): 5.84 ms, 93.0%
  - water_tag_sedimenting_mass_names (tagged_water_precipitation.jl): 0.47 ms, 7.5%
  - sedimenting_energy_source_tag_names (energy_source_tags.jl): 0.16 ms, 2.6%
  - sedimenting_water_tag_names (tagged_water.jl): 0.08 ms, 1.3%
  - energy_source_tag_moves_as_enthalpy (energy_source_tags.jl): 0.06 ms, 0.9%
  - snapshot_energy_source_increment! (energy_source_tags.jl): 0.00 ms, 0.0%

six walk frames: 6.43 ms, 102% of the timed excess

## prof88_b: timed excess 8.111 ms

  - untagged: 1.04 samples per timed ms
  - water: 0.88 samples per timed ms
  - energy: 0.78 samples per timed ms
  - both: 0.95 samples per timed ms

time_phase:
  - implicit tendency: 3.84 ms, 47.3%
  - explicit tendency: 2.51 ms, 30.9%
  - jacobian: 2.45 ms, 30.2%
  - constrain_state!: 0.05 ms, 0.6%
  - callbacks: 0.02 ms, 0.3%
  - lim!: 0.00 ms, 0.0%

tag_entry:
  - (not tag code): 7.71 ms, 95.0%
  - water_tag_sedimenting_mass_names (tagged_water_precipitation.jl): 1.02 ms, 12.6%
  - sedimenting_water_tag_names (tagged_water.jl): 0.11 ms, 1.4%
  - sedimenting_energy_source_tag_names (energy_source_tags.jl): 0.10 ms, 1.2%
  - WaterTagIncrementCorrection (tagged_water_increment.jl): 0.08 ms, 1.0%
  - repair_water_tag_partition! (tagged_water.jl): 0.01 ms, 0.1%

six walk frames: 10.25 ms, 126% of the timed excess

