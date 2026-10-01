# The P2/P3 profile (design/WP9_COST.md section 8)

Model `43b01ca1` (old physics, before #139), record `d44593c61`. Three
exclusive jobs on `hpda2_compute`, all COMPLETED on 2026-10-01:
`prof_water_edmf` 14055213 (`hpdar07c04s09`, 00:53:49), `prof_energy_edmf`
14055214 (`hpdar07c04s11`, 02:06:29), `prof_water_1m_on` 14055215
(`hpdar07c04s12`, 01:01:10). Load average at each point 1.00 to 1.13.

Energy at 32 tags hit the 90 min point limit (exit 124) during the allocation
profile, after a 1583 s build. Its time profile ran (10079 samples, tag code
on 14.6% of them, in its log) but wrote no CSV. So the energy arm has no
comparison, and P2 is read at 2 tags only.

`table.md` is `analysis/wp9_profile_table.py
$SCRATCH/tag_closure/output/wp9_profile`. The script got one fix after the
run: `csv.field_size_limit`, since ClimaCore's type names pass csv's default
limit, and a shortened display of long names. Four `*_alloc_type.csv` files
are over 2 MB and stay on scratch:

```
db9c0b7df044e39ec84799a89cea2c241d837630c2654c6248a2576a9567b7fd  prof_energy_edmf/energy_wp9_energy_d4_edmf_default_noprecip_none_n2_alloc_type.csv
638df24ed0ee9ff31d0fd423af72df05a6e8e112b459b72056cf9d86d4e39320  prof_water_1m_on/water_wp9_water_1m_column_default_precip_none_n2_alloc_type.csv
4ffbda8733a21fefc103c65f4d4c6bbefe73affa8651eb3ea7a5cc6408352d78  prof_water_1m_on/water_wp9_water_1m_column_default_precip_none_n8_alloc_type.csv
35265de114d323cd4ea3a975c4d3351fef4fbe63e7890b3dc8fbeed62f983c17  prof_water_edmf/water_wp9_water_trmm0m_edmf_default_noprecip_none_n32_alloc_type.csv
```

## Reading

These are bounded results. A profile says in which frames the cost is
recorded. It does not say why the cost grows. Each point is one run.

  - **Water under EDMF, 2 to 32 tags.** Allocation grows from 0.26 to
    5.0 MB per step (profile estimate; the timed block reads 0.29 and
    5.26 MB). Three frames hold 45% of that growth, and none of them
    allocates at 2 tags. They are the closures that walk the tuple of
    tracer names: `utils/tracer_processes.jl:138` and
    `utils/variable_manipulations.jl:242` (`foreach_gs_tracer`), and
    `solve_uncoupled_fields!` in `manual_sparse_jacobian.jl:1088`. The
    largest types in the growth are `Memory{Symbol}` (26%) and
    `NTuple{45, Symbol}` (12%), that is, tuples of names. The tag code in
    `tagged_tracers/` holds 17% of the bytes at 32 tags and 0% at 2.
    By phase, the implicit tendency grows most: from 0.05 to 2.2 MB and from
    1.5 to 19 ms per step. The two name-walking closures also hold 58% of the
    growth in time. The tags' own exchange (`_exchange_water_tags!`) holds 20%.
  - **1M column with rain and snow, 2 to 8 tags.** The same frames lead.
    `solve_uncoupled_fields!` holds 27% of the growth in allocation, the two
    closures 33%, and the water-tag sedimentation Jacobian block 11%. The types
    are `Memory{Symbol}` (32%) and `NTuple{52, Symbol}` (15%). The two
    closures hold 74% of the growth in time.
  - **P2** (`_energy_source_share_norm!`) is on the stack in 0.19% of the
    energy time samples at 2 tags. That is under the 5% of section 8. It is
    not read at 32 tags. So P2 does not show at 2 tags. The profile does not
    say whether it shows at 32.
  - **P3** (`is_energy_source_tag_name`) holds at most 1035 bytes per step at
    any profiled point, under 0.1% of the bytes. `String` bytes are 1650 to
    3425 per step at 2 tags, and below the top 40 types at the high points.
    So P3 does not show at these points, with the closure audit off.
  - The step times here come from one block taken right after the warm-up. It
    is the block that carried the excess in the cost runs. Use them for
    shares, not as step times.
