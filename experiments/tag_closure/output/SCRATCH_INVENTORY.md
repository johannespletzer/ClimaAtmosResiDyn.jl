# What is still on scratch

Generated on 2026-09-20. The repository keeps each run's small text
outputs: the closure and audit tables, the configuration, the provenance and
the log. The NetCDF and the checkpoints live on
`$SCRATCH/tag_closure/output/<run>/`, which is not durable. This lists what
was still there, so a later session knows what can be reanalysed and what
only its tables remain of.

| run | NetCDF files | checkpoints |
|:--|--:|--:|
| `b1_base` | 6 | 0 |
| `c0_sphere_audit` | 8 | 0 |
| `c10_sphere_enthalpy_repair` | 38 | 0 |
| `c1_sphere_shift` | 8 | 0 |
| `c1c_base_d4_enthalpy` | 48 | 0 |
| `c1c_opt1_d4_enthalpy` | 48 | 0 |
| `c1c_opt1_newton_d4_enthalpy` | 48 | 0 |
| `c1c_opt2_d4_enthalpy` | 48 | 0 |
| `c1c_opt3_d4_enthalpy` | 48 | 0 |
| `c4_sphere_tag_offset` | 10 | 0 |
| `c4_sphere_tag_offset_2x` | 10 | 0 |
| `c5_column_offset` | 20 | 0 |
| `c5_sphere_gray` | 18 | 0 |
| `c6_column_no_repair` | 50 | 0 |
| `c6_column_repair` | 50 | 0 |
| `c6_sphere_first_order` | 41 | 0 |
| `c6_sphere_no_repair` | 41 | 0 |
| `c6_sphere_repair` | 41 | 0 |
| `c6_sphere_wide_mask` | 34 | 0 |
| `c7_sphere_mp` | 24 | 0 |
| `c8_column_1m` | 48 | 0 |
| `c9_column_enthalpy` | 42 | 0 |
| `c9_sphere_enthalpy` | 24 | 0 |
| `d1_column_1m_ice` | 36 | 0 |
| `d1_column_1m_ice_no_vdiff` | 36 | 0 |
| `d4_column_edmf` | 48 | 0 |
| `d4_column_edmf_enthalpy` | 48 | 0 |
| `d4_column_edmf_vd` | 48 | 0 |
| `d4_column_edmf_vd_float32` | 48 | 0 |
| `d5_column_edmf_ice` | 42 | 0 |
| `g1_base_d4_float32` | 48 | 0 |
| `g1_inc_d4` | 52 | 0 |
| `g1_inc_d4_2c` | 52 | 0 |
| `g1_inc_d4_float32` | 52 | 0 |
| `g1_inc_newton10_d4` | 52 | 0 |
| `g1_inc_newton_d4` | 52 | 0 |
| `g1_ref_newton10_d4` | 48 | 0 |
| `g1_ref_newton_d4` | 48 | 0 |
| `g2_v2_diag_newton2` | 32 | 0 |
| `g2_v2_diag_nosponge` | 32 | 0 |
| `g2_v2_diag_notopo` | 32 | 0 |
| `g2_v2_f64_2h` | 32 | 0 |
| `g2_v2_nosponge_2h` | 32 | 0 |
| `g2_v2_sphere` | 32 | 20 |
| `g2_v2_sphere_n2` | 32 | 20 |
| `g2_v2_sphere_newton10` | 32 | 0 |
| `g2_v2_sphere_test` | 32 | 0 |
| `inc_d4_enthalpy_increment` | 48 | 0 |
| `mp1_sphere_4ranks` | 24 | 0 |
| `p1_sphere_tags` | 24 | 0 |
| `v3_d4_passive_tracer` | 60 | 0 |
| `v3_sphere_float32` | 24 | 0 |
| `v3_upd_copies` | 60 | 0 |
| `v3_upd_default` | 90 | 0 |
| `v3_upd_default_prefix_e010f780_superseded` | 60 | 0 |
| `v5_c5_continuous` | 20 | 4 |
| `v5_c5_continuous_notags` | 0 | 4 |
| `v5_c5_restarted` | 20 | 2 |
| `v5_c5_restarted_notags` | 0 | 2 |

The other 47 run directories in `output/` have their tables only.
