"""
    ClimaAtmos.Internals.ParentBudget

The parent-budget ledger: the accounting that decides whether an accepted
timestep's change in atmospheric mass, total water, and total energy is
explained by what the model recorded.

**Unstable internal machinery.** Nothing here is exported, public, or covered by
any compatibility promise. A simulation constructs a ledger only when
`parent_budget_mode` is not `off`, and the ledger never writes the state, so a
run with it off is the run without it. See
`docs/src/parent_budget/` for the contract these types implement.

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
  - `adapter.jl` is the place that knows the timestepper's stages and hooks.
    It captures the accepted envelopes after each step, meters the
    applied-update events the tendency code brackets, and drives the
    transactions.
"""
module ParentBudget

import ClimaComms
import ClimaCore.Fields as Fields
import ClimaCore.Spaces as Spaces
import ClimaTimeSteppers as CTS

# The ClimaAtmos types the applicability functions and the slab integrals
# dispatch on. Naming every ClimaAtmos import here keeps the dependency visible
# in one place.
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
# The ledger half of the applied-update event. The functions are declared in
# the main module, next to the tag half, so the tendency code calls one API
# whether the ledger is on or off; the adapter adds its methods here.
import ...open_ledger_event!
import ...close_ledger_event!

include("integrals.jl")
include("schema.jl")
include("coverage_registry.jl")
include("reduction.jl")
include("journal.jl")
include("transaction.jl")
include("adapter.jl")

end
