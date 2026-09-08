"""
    ClimaAtmos.Internals.ParentBudget

The parent-budget ledger: the accounting that decides whether an accepted
timestep's change in atmospheric mass, total water, and total energy is
explained by what the model recorded.

**Unstable internal machinery.** Nothing here is exported, public, or covered by
any compatibility promise. A simulation constructs a ledger only when
`parent_budget_mode` is not `off`, and the ledger never writes the state, so a
run with it off is the run without it. See
`docs/src/parent_budget/` for the contract these types implement and
`docs/src/parent_budget/plan.md` for the order the rest is built in.

The files are included in dependency order.

  - `integrals.jl` defines the accounting precision, the three parent
    quantities, and the local integrals. Nothing in it communicates.
  - `schema.jl` declares what a configuration is expected to produce, before
    anything is collected.
  - `coverage_registry.jl` holds every path that writes a parent field as a
    row, and builds the schema a configuration selects from those rows.
  - `reduction.jl` packs local values into a fixed layout and reduces the whole
    packet with one collective.
  - `journal.jl` records what happened, with evidence per component.
  - `transaction.jl` compares the two and produces the three residuals.
  - `adapter.jl` is the one place that knows the timestepper: it captures the
    accepted envelopes after each step and drives the transactions.
"""
module ParentBudget

import ClimaComms
import ClimaCore.Fields as Fields
import ClimaCore.Spaces as Spaces
import ClimaTimeSteppers as CTS

# The adapter boundary. These are the only ClimaAtmos types the ledger
# dispatches on, and naming them here keeps the dependency visible in one place
# rather than scattered through the files below.
import ...AbstractMicrophysicsModel
import ...DryModel
import ...SurfaceConditions
# The coverage registry's guards read the model configuration and nothing else.
import ...EquilibriumMicrophysics0M
import ...NonEquilibriumMicrophysics1M
import ...NonEquilibriumMicrophysics2M
import ...NonEquilibriumMicrophysics2MP3
import ...HeldSuarezForcing
import ...RRTMGPI
import ...RadiationDYCOMS
import ...RadiationISDAC
import ...RadiationTRMM_LBA
import ...Explicit
import ...Implicit
import ...AbstractEDMF
import ...GasPhaseChem
import ...TracerNonnegativityVaporTendency
import ...TracerNonnegativityVaporConstraint
import ...TracerNonnegativityElementConstraint
import ...TracerNonnegativityVerticalWaterBorrowing
# The adapter asks the space whether it performs DSS.
import ...do_dss

include("integrals.jl")
include("schema.jl")
include("coverage_registry.jl")
include("reduction.jl")
include("journal.jl")
include("transaction.jl")
include("adapter.jl")

end
