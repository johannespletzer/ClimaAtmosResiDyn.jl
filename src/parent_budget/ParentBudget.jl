"""
    ClimaAtmos.Internals.ParentBudget

The parent-budget ledger: the accounting that decides whether an accepted
timestep's change in atmospheric mass, total water, and total energy is
explained by what the model recorded.

**Unstable internal machinery.** Nothing here is exported, public, or covered by
any compatibility promise, and it is not wired into any simulation: no runtime
path constructs a ledger, so enabling nothing changes any trajectory. See
`docs/src/parent_budget/` for the contract these types implement and
`docs/src/parent_budget/plan.md` for the order the rest is built in.

The files are included in dependency order.

  - `integrals.jl` defines the accounting precision, the three parent
    quantities, and the local integrals. Nothing in it communicates.
  - `schema.jl` declares what a configuration is expected to produce, before
    anything is collected.
  - `reduction.jl` packs local values into a fixed layout and reduces the whole
    packet with one collective.
  - `journal.jl` records what happened, with evidence per component.
  - `transaction.jl` compares the two and produces the three residuals.
"""
module ParentBudget

import ClimaComms
import ClimaCore.Fields as Fields
import ClimaCore.Spaces as Spaces

# The adapter boundary. These are the only ClimaAtmos types the ledger
# dispatches on, and naming them here keeps the dependency visible in one place
# rather than scattered through the files below.
import ...AbstractMicrophysicsModel
import ...DryModel
import ...SurfaceConditions

include("integrals.jl")
include("schema.jl")
include("reduction.jl")
include("journal.jl")
include("transaction.jl")

end
