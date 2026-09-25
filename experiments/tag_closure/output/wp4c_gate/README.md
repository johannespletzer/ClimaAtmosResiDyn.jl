# WP4c gate: the login-node checks

2026-09-25, before any job (`design/WP4C_GATE.md`, section 6).

- Every trial configuration of both cases builds its model (12 of 12).
- The probe ran two steps of case A (`T_END=240secs`) and wrote the per-step
  CSV here (`smoke_two_steps_…`, 107 columns). The first attempt failed at the
  first copy into a tracer-transport trial, whose state lacks the follower's
  ledgers; fixed in `df4fa7ad`. The second failed after the loop, in the
  profile writer's array types; fixed after it and checked on a small column,
  not by a third two-step run (76 minutes each on the login node).
- The two steps are startup: `vdiff`'s source is zero at the first step and
  8e-20 kg/m² at the second, since the column has no rain yet. They check the
  plumbing, not the gate.
