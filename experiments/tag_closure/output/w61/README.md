# W61: the tags' hyperdiffusion on a sphere, cross form against passive form

Measured after the fact for the WP4b fix PR (`claude/wp4b-fix`), not
pre-registered. Three runs of `scripts/transport1_sphere.jl` (the third with
`transport1_sphere_regime.jl`, which adds three volume and water fractions):
the moist baroclinic wave, `h_elem` 6, `nh_poly` 3, 10 levels to 30 km, 1M,
`dt` 400 s, ARS343, 3 days, region tags `tropics` and `extratropics`,
`water_tag_precipitation: true`.

- `cross/`: `main` `d3c5e42f` (the share of `q_tot_r` inside the operator).
  Job `14125084`.
- `passive/`: `main` plus the passive form only, the detached tree
  `81884d5b` (`scripts/passive_form_tree_81884d5b.diff`). Job `14125085`.
- `cross_regime/`: `cross` again, with the regime's fractions. Job
  `14126689`. Its ledgers equal `cross/`'s, byte for byte.

`forms.csv`: every 6 h, per tag, on the run's own state, both forms evaluated
by hand with the model's operators and DSS. `var_*` is `∫ χ T dV` (negative
lowers the tag's variance), `neg_*` the water one step of that tendency alone
would take below zero (kg), `l1_diff_rel` the L1 difference of the forms over
the passive form's L1, `model_vs_*` the model's own tendency against each
form (0 means equal). `ledgers.csv`: the run's own mechanism ledgers as
domain integrals (kg), the L1 residual of the non-precipitating parts and
`∫max(N, 0)`.
