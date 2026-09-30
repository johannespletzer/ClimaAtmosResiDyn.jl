# #130's Julia 1.10 allocation fix: the verification logs

#130's second CI run failed one job: `tagging_water_rainout_jacobian` on
Julia 1.10. There `update_jacobian!` allocated 496 B with the switch on and
448 B off. The cause was not in the switch. On 1.10,
`passive_gs_tracer_names(Y)` does not infer, so the passive-tracer loop in
`update_diffusion_jacobian!` was a dynamic call that boxed the Jacobian, about
16 B per block. The fix is `f4a5108d`: `jacobian_cache` passes the names, and
the loop is a recursion. It was merged in #130.

These logs are the checks before the push, with CI's versions (ClimaCore
1.0.1, ClimaComms 0.6.12, ClimaParams 1.1.15):

| Job      | What                                                   | Result                                                          |
|:-------- |:------------------------------------------------------ |:--------------------------------------------------------------- |
| 14010424 | Julia 1.10: unit and integration files                 | 134/134 and 75/75; `update_jacobian!` 0 B on and off            |
| 14010425 | Julia 1.11: unit and integration files; mutant 1       | 134/134 and 75/75, all 0 B; the mutant fails its file as needed |
| 14010426 | parity: main 4060c782 against the fix without the key; 79ba1435 against the fix with the switch on | all bit for bit |

The `.out` files are the jobs' driver logs, and the `.log` files the test
files' output.
