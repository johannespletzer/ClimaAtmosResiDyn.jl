### prof_energy_edmf: 1 finished points, not 2; no comparison.

### prof_water_1m_on: `wp9_water_1m_column`, 2 and 8 tags, commit `43b01ca1`

Hosts hpdar07c04s12 / hpdar07c04s12, load 1.13 / 1.00.

| measure | 2 tags | 8 tags |
|:--|--:|--:|
| step_ms | 8.775 | 39.811 |
| bytes_per_step | 1219169 | 8222975 |
| allocs_per_step | 2176 | 17546 |
| alloc_bytes_per_step_est | 1200971 | 8004178 |
| samples | 4638 | 6913 |
| alloc_recorded | 21799 | 175531 |
| tag_code_time_share | 0.222 | 0.136 |
| tag_code_alloc_share | 0.060 | 0.065 |

| phase | ms/step 2 | ms/step 8 | B/step 2 | B/step 8 |
|:--|--:|--:|--:|--:|
| explicit tendency | 2.113 | 14.317 | 1029876 | 3133140 |
| linear solve | 0.547 | 1.451 | 0 | 1855008 |
| implicit tendency | 1.107 | 15.509 | 58416 | 1632048 |
| jacobian | 1.069 | 4.549 | 104877 | 1311297 |
| cache_imp! | 0.479 | 0.898 | 0 | 52992 |
| cache! | 2.371 | 1.941 | 256 | 12032 |
| callbacks | 0.307 | 0.121 | 5274 | 5389 |
| other | 0.517 | 0.495 | 0 | 0 |
| constrain_state! | 0.070 | 0.104 | 480 | 480 |
| lim! | 0.197 | 0.426 | 1792 | 1792 |

Growth in allocation per step, 2 to 8 tags: 6803208 B over the top-80 frames; the rows below hold 5521792 B. A frame outside a point's top 80 is read as 0 (bound: 16 B).

| innermost frame in `src/` | 2 | 8 | growth | share of growth |
|:--|--:|--:|--:|--:|
| `prognostic_equations/implicit/manual_sparse_jacobian.jl:1088 solve_uncoupled_fields!` | 0 B | 1855008 B | 1855008 B | 27.3% |
| `utils/variable_manipulations.jl:242 #129` | 0 B | 1169280 B | 1169280 B | 17.2% |
| `utils/tracer_processes.jl:138 #142` | 0 B | 1088640 B | 1088640 B | 16.0% |
| `prognostic_equations/implicit/manual_sparse_jacobian.jl:1627 update_water_tag_sedimentatio…` | 0 B | 719136 B | 719136 B | 10.6% |
| `prognostic_equations/advection.jl:121 macro expansion` | 2816 B | 280128 B | 277312 B | 4.1% |
| `prognostic_equations/advection.jl:263 #888` | 121600 B | 340480 B | 218880 B | 3.2% |
| `utils/tracer_processes.jl:153 #144` | 0 B | 193536 B | 193536 B | 2.8% |

Growth in time per step, 2 to 8 tags: 29.861 ms over the top-80 frames; the rows below hold 23.911 ms. A frame outside a point's top 80 is read as 0 (bound: 0.035 ms).

| innermost frame in `src/` | 2 | 8 | growth | share of growth |
|:--|--:|--:|--:|--:|
| `utils/variable_manipulations.jl:242 #129` | 0.000 ms | 11.472 ms | 11.472 ms | 38.4% |
| `utils/tracer_processes.jl:138 #142` | 0.000 ms | 10.573 ms | 10.573 ms | 35.4% |
| `utils/tracer_processes.jl:153 #144` | 0.000 ms | 1.866 ms | 1.866 ms | 6.2% |

| P2/P3 function on the stack | time share 2 | time share 8 | B/step 2 | B/step 8 |
|:--|--:|--:|--:|--:|
| `_energy_source_share_norm!` | 0.0000 | 0.0000 | 0 | 0 |
| `is_energy_source_tag_name` | 0.0002 | 0.0000 | 351 | 1035 |

Type `String`: 3425 B/step at 2 tags, 0 B/step at 8 (0 if outside the top 40 types).

| type | 2 | 8 | growth | share of growth |
|:--|--:|--:|--:|--:|
| `Memory{Symbol}` | 0 B | 1811072 B | 1811072 B | 31.8% |
| `NTuple{52, Symbol}` | 0 B | 869856 B | 869856 B | 15.3% |
| `Base.Broadcast.Broadcasted{ClimaCore.Operators.ColumnStencilStyle, Nothing, typeof(+), Tup…` | 98560 B | 275968 B | 177408 B | 3.1% |
| `Base.Broadcast.Broadcasted{ClimaCore.Operators.ColumnStencilStyle, ClimaCore.Spaces.Finite…` | 91520 B | 256256 B | 164736 B | 2.9% |
| `ClimaCore.Fields.Field{ClimaCore.DataLayouts.VIJFH{Float64, 30, 1, 1, 1, ClimaCore.DataLay…` | 70464 B | 230208 B | 159744 B | 2.8% |

### prof_water_edmf: `wp9_water_trmm0m_edmf`, 2 and 32 tags, commit `43b01ca1`

Hosts hpdar07c04s09 / hpdar07c04s09, load 1.00 / 1.01.

| measure | 2 tags | 32 tags |
|:--|--:|--:|
| step_ms | 10.503 | 35.162 |
| bytes_per_step | 289934 | 5261784 |
| allocs_per_step | 703 | 28937 |
| alloc_bytes_per_step_est | 260902 | 5026340 |
| samples | 2990 | 5923 |
| alloc_recorded | 6501 | 198641 |
| tag_code_time_share | 0.081 | 0.281 |
| tag_code_alloc_share | 0.000 | 0.173 |

| phase | ms/step 2 | ms/step 32 | B/step 2 | B/step 32 |
|:--|--:|--:|--:|--:|
| implicit tendency | 1.532 | 19.187 | 51856 | 2243177 |
| explicit tendency | 2.188 | 9.629 | 188512 | 1487895 |
| linear solve | 0.667 | 1.122 | 0 | 677374 |
| other | 0.699 | 1.532 | 0 | 356428 |
| jacobian | 0.766 | 1.348 | 0 | 192586 |
| cache! | 1.454 | 0.724 | 6352 | 53358 |
| constrain_state! | 0.014 | 0.047 | 48 | 1344 |
| cache_imp! | 2.740 | 1.276 | 8960 | 9140 |
| initialize_imp! | 0.200 | 0.166 | 0 | 0 |
| callbacks | 0.242 | 0.131 | 5174 | 5039 |

Growth in allocation per step, 2 to 32 tags: 4764997 B over the top-80 frames; the rows below hold 3602715 B. A frame outside a point's top 80 is read as 0 (bound: 128 B).

| innermost frame in `src/` | 2 | 32 | growth | share of growth |
|:--|--:|--:|--:|--:|
| `utils/tracer_processes.jl:138 #142` | 0 B | 741614 B | 741614 B | 15.6% |
| `utils/variable_manipulations.jl:242 #129` | 0 B | 741388 B | 741388 B | 15.6% |
| `prognostic_equations/implicit/manual_sparse_jacobian.jl:1088 solve_uncoupled_fields!` | 0 B | 677374 B | 677374 B | 14.2% |
| `parameterized_tendencies/tagged_tracers/tagged_water_edmf.jl:572 WaterPlumeStep` | 0 B | 451255 B | 451255 B | 9.5% |
| `(outside src)` | 0 B | 356428 B | 356428 B | 7.5% |
| `parameterized_tendencies/tagged_tracers/tagged_water_edmf.jl:469 water_tag_plume!` | 0 B | 146464 B | 146464 B | 3.1% |
| `prognostic_equations/edmfx_sgs_flux.jl:394 #867` | 13824 B | 154298 B | 140474 B | 2.9% |
| `prognostic_equations/surface_flux.jl:134 #874` | 12384 B | 135642 B | 123258 B | 2.6% |
| `prognostic_equations/edmfx_sgs_flux.jl:395 #867` | 11616 B | 129938 B | 118322 B | 2.5% |
| `prognostic_equations/advection.jl:121 macro expansion` | 192 B | 106331 B | 106139 B | 2.2% |

Growth in time per step, 2 to 32 tags: 24.400 ms over the top-80 frames; the rows below hold 19.898 ms. A frame outside a point's top 80 is read as 0 (bound: 0.030 ms).

| innermost frame in `src/` | 2 | 32 | growth | share of growth |
|:--|--:|--:|--:|--:|
| `utils/tracer_processes.jl:138 #142` | 0.000 ms | 7.314 ms | 7.314 ms | 30.0% |
| `utils/variable_manipulations.jl:242 #129` | 0.000 ms | 6.845 ms | 6.845 ms | 28.1% |
| `parameterized_tendencies/tagged_tracers/tagged_water_edmf.jl:521 _exchange_water_tags!` | 0.162 ms | 5.070 ms | 4.908 ms | 20.1% |
| `prognostic_equations/surface_flux.jl:143 #874` | 0.000 ms | 0.831 ms | 0.831 ms | 3.4% |

| P2/P3 function on the stack | time share 2 | time share 32 | B/step 2 | B/step 32 |
|:--|--:|--:|--:|--:|
| `_energy_source_share_norm!` | 0.0000 | 0.0000 | 0 | 0 |
| `is_energy_source_tag_name` | 0.0000 | 0.0000 | 0 | 0 |

Type `String`: 1650 B/step at 2 tags, 0 B/step at 32 (0 if outside the top 40 types).

| type | 2 | 32 | growth | share of growth |
|:--|--:|--:|--:|--:|
| `Memory{Symbol}` | 0 B | 1123214 B | 1123214 B | 26.3% |
| `NTuple{45, Symbol}` | 0 B | 504464 B | 504464 B | 11.8% |
| `Float64` | 0 B | 213842 B | 213842 B | 5.0% |
| `ClimaCore.Utilities.AutoBroadcaster{NTuple{32, Float64}}` | 0 B | 178828 B | 178828 B | 4.2% |
| `ClimaTimeSteppers.var'#96#99'{ClimaCore.Fields.FieldVector{Float64, @NamedTuple{c::ClimaCo…` | 0 B | 156504 B | 156504 B | 3.7% |

