"""
    AbstractTagRegion

Abstract type for the smooth spatial masks used by tagged prognostic energy
tracers. Concrete regions implement `region_mask(region, coord)` (defined in
`parameterized_tendencies/tagged_tracers/tagged_tracers.jl`).
"""
abstract type AbstractTagRegion end

"""
    EntireDomain()

Tag region whose mask is 1 everywhere.
"""
struct EntireDomain <: AbstractTagRegion end

"""
    TanhAltitudeRegion(z_center, width, above = true)

Tag region with a smooth `tanh` transition in altitude, with mask
`(1 + tanh((z - z_center) / width)) / 2` (0 well below `z_center`, 1 well
above). When `above` is `false`, the mask is the exact complement
`1 - M_above`, so a region and its complement sum to 1 everywhere (e.g. a
"troposphere" tag as the complement of a "stratosphere" tag). `z_center` and
`width` are in meters, and `width` must be positive.
"""
struct TanhAltitudeRegion{FT} <: AbstractTagRegion
    z_center::FT
    width::FT
    above::Bool
end
TanhAltitudeRegion(z_center, width) = TanhAltitudeRegion(z_center, width, true)

"""
    TanhLatitudeRegion(lat_bound, width, inside)

Tag region for a smooth latitude band `|lat| ≲ lat_bound` with `tanh`
transitions of the given `width` (both in degrees). When `inside` is `false`,
the mask is the exact complement `1 - M_band`, so a band and its complement
sum to 1 everywhere. Requires spherical geometry (coordinates with `lat`).

Both `lat_bound` and `width` must be positive: a zero bound gives an empty
band, and a negative one gives a negative mask.
"""
struct TanhLatitudeRegion{FT} <: AbstractTagRegion
    lat_bound::FT
    width::FT
    inside::Bool
end

"""
    TanhBoxRegion(lon_min, lon_max, lat_min, lat_max, width, inside)

Tag region for a smooth longitude–latitude box: the product of a smooth
latitude band and a smooth longitude band, each with `tanh` edges of the
given `width`. All arguments are in degrees. Longitudes are compared modulo
360°, so a box may cross the antimeridian (e.g. `lon_min = 170`,
`lon_max = -170`). When `inside` is `false`, the mask is the exact
complement. Requires spherical geometry.

`width` must be positive and `lat_min` must be below `lat_max`. Comparing
longitudes modulo 360° is what lets a box wrap, and it also means a box
spanning a whole turn (`lon_min = -180`, `lon_max = 180`) is indistinguishable
from one spanning nothing: its mask is zero everywhere. For a band over every
longitude, symmetric about the equator, use [`TanhLatitudeRegion`](@ref).
"""
struct TanhBoxRegion{FT} <: AbstractTagRegion
    lon_min::FT
    lon_max::FT
    lat_min::FT
    lat_max::FT
    width::FT
    inside::Bool
end

"""
    TanhPolygonRegion(vertices, width, inside)

Tag region for an arbitrary polygon on the sphere, smoothed with a `tanh`
transition of the given `width` (in degrees) across its boundary. This is the
region type to use for published reference regions such as the IPCC AR6 /
ATLAS domains: export their vertices and pass them here.

  - `vertices`: an `NTuple` of `(lon, lat)` pairs in degrees, in either
    winding order. The polygon is implicitly closed.
  - `width`: transition width in degrees of great-circle arc, and must be
    positive; the mask is `1/2` on the boundary, tending to 1 well inside and 0
    well outside.
  - `inside`: when `false`, the mask is the exact complement.

The polygon is evaluated in a longitude frame centered on its first vertex,
so it may cross the antimeridian as long as it spans less than 180° of
longitude. Requires spherical geometry.
"""
struct TanhPolygonRegion{N, FT} <: AbstractTagRegion
    vertices::NTuple{N, NTuple{2, FT}}
    width::FT
    inside::Bool
end

"""
    AbstractTracerTag{name}

Supertype of the tag definitions, parameterized by the tag `name` so that state
field names can be generated at compile time. The concrete subtypes differ in
which parent quantity they partition: [`TracerTag`](@ref) tags total energy
`ρe_tot`, [`WaterTag`](@ref) tags total water `ρq_tot`.
"""
abstract type AbstractTracerTag{name} end

"""
    TracerTag{name}(region, source = :none)

Definition of one tagged prognostic energy tracer, stored in the state as
`Y.c.ρe_tag_<name>`. The tag `name` is a type parameter so that state field
names can be generated at compile time (GPU-compatible).

  - `region`: an [`AbstractTagRegion`](@ref) or `nothing`. A region tag
    (`region` given, no sources) is initialized to `ρe_tot * mask` and
    receives every attributed process, masked. Any tag with sources is
    initialized to zero — including region-restricted ones, which accumulate
    only their own processes, masked by their region.
  - `sources`: a `Tuple` of `Symbol`s labeling the physical processes whose
    `ρe_tot` tendencies are attributed to this tag (e.g. `(:radiation,)`);
    empty for passive region tags. A single `Symbol` is also accepted
    (`:none` meaning "no sources").

A tag with sources is a *signed process tag*. It starts at zero, accumulates
the signed change its processes have made, and goes negative under net cooling.
It is not a share of the energy present. The `source` key is shared
with [`WaterTag`](@ref), which applies a different rule to it.

Do not call it a process-change record. That name belongs to the `prc_*`
family in `process_record.jl`, which is a different object: one field per
process rather than per tag, and not transported.
"""
struct TracerTag{name, R <: Union{Nothing, AbstractTagRegion}, S <: Tuple} <:
       AbstractTracerTag{name}
    region::R
    sources::S
end
TracerTag{name}(region::R, sources::S = ()) where {name, R, S <: Tuple} =
    TracerTag{name, R, S}(region, sources)
TracerTag{name}(region, source::Symbol) where {name} =
    TracerTag{name}(region, source === :none ? () : (source,))

"""
    WaterTag{name}(region, source = :none)

Definition of one tagged prognostic water tracer, stored in the state as
`Y.c.ρq_tag_<name>`. Same shape as [`TracerTag`](@ref), but it partitions total
water `ρq_tot` rather than total energy, and it is attributed with a different
rule (see `parameterized_tendencies/tagged_tracers/tagged_water.jl`):

  - `region`: an [`AbstractTagRegion`](@ref) or `nothing`. A region tag
    (`region` given, no sources) is initialized to `ρq_tot * mask` and receives
    every attributed *production* term, masked. Any source tag is initialized to
    zero and receives only the production of the processes it lists.
  - `sources`: a `Tuple` of `Symbol`s labeling the processes whose `ρq_tot`
    production is attributed to this tag (e.g. `(:surface_flux,)`); empty for a
    region tag. A single `Symbol` is also accepted (`:none` meaning "no
    sources").

Unlike an energy tag, *every* water tag is depleted by *every* attributed loss
term, in proportion to its own share of the local water. That is what makes
`ρq_tag_<name>` an actual water mass rather than a running source integral.
Where the parent's water is below zero, no tag gains.
"""
struct WaterTag{name, R <: Union{Nothing, AbstractTagRegion}, S <: Tuple} <:
       AbstractTracerTag{name}
    region::R
    sources::S
end
WaterTag{name}(region::R, sources::S = ()) where {name, R, S <: Tuple} =
    WaterTag{name, R, S}(region, sources)
WaterTag{name}(region, source::Symbol) where {name} =
    WaterTag{name}(region, source === :none ? () : (source,))

"""
    tag_sources(tag::AbstractTracerTag)

The `Tuple` of process labels attributed to a tag. Empty for a region tag.
"""
tag_sources(tag::AbstractTracerTag) = tag.sources

"""
    tag_name(tag::AbstractTracerTag)

The `Symbol` name of a tag (compile-time constant).
"""
tag_name(::AbstractTracerTag{name}) where {name} = name

"""
    TaggingModel(tags::Tuple)

Model component holding a `Tuple` of [`TracerTag`](@ref)s. Constructed from
the `energy_tracers` config entry; see `AtmosTagging(::AtmosConfig)` in
`config/tracer_config.jl`.
"""
struct TaggingModel{T <: Tuple}
    tags::T
end

"""
    AbstractWaterTagTransport

How the water tags follow the parent's implicit transport, from the
`water_tag_transport` config key: [`TracerWaterTagTransport`](@ref), the
default, or [`IncrementWaterTagTransport`](@ref).
"""
abstract type AbstractWaterTagTransport end

"""
    TracerWaterTagTransport()

The default. The tags are moved as tracers, explicitly, while the parent
`ρq_tot` is advected implicitly. Their implicit terms, such as the sub-grid
mass flux under EDMF, have no Jacobian block. So with one Newton iteration they
take those terms at the stage's first guess while the parent takes the solved
one, and `q_tag_res` grows by the difference.
"""
struct TracerWaterTagTransport <: AbstractWaterTagTransport end

"""
    IncrementWaterTagTransport()

Increment transport. The tags take the parent's own implicit increment. Their
explicit vertical advection is skipped. After each Newton solve, the difference
between the parent's increment of `ρq_tot` and the partition's is moved as a
vertical flux, and each tag takes its share of it in the cell the flux leaves.
See `correct_water_tag_increment!`. It needs region tags without sources that
partition the domain.
"""
struct IncrementWaterTagTransport <: AbstractWaterTagTransport end

"""
    WaterTaggingModel(tags::Tuple; updraft_copies = false,
                      transport = TracerWaterTagTransport(),
                      ledger_per_tag = false, precipitation = false,
                      leak_correction = false, rainout_jacobian = false,
                      precipitation_audit = true)

Model component holding a `Tuple` of [`WaterTag`](@ref)s. Constructed from the
`water_tracers` config entry; see `AtmosTagging(::AtmosConfig)` in
`config/tracer_config.jl`.

`updraft_copies`, from `water_tag_updraft_copy`, gives each tag a copy in every
updraft under `turbconv: prognostic_edmfx`, which the model's own updraft
machinery moves: the comparison mode. Without it the tags stay grid-scale. They
take their share of the updraft's water flux, and an exchange gives each tag the
updraft's composition. That is the default. It is a type parameter, so the state
is built from it at compile time.

`transport`, from `water_tag_transport`, is how the tags follow the parent's
implicit terms: as tracers by default, or by the parent's own increment after
each Newton solve (increment transport). Increment transport needs region tags
without sources, and is refused without them. See
[`IncrementWaterTagTransport`](@ref).

`ledger_per_tag`, from `water_tag_ledger_per_tag`, gives each tag its own state
ledgers of what the corrections changed it by: `q_tag_led_fix_<name>` for the
limiters' rescale and the partition repair, and, under increment transport,
`q_tag_led_inc_<name>` for the correction after each solve. Off by default,
since each adds a state field per tag. A type parameter, like `updraft_copies`.

`precipitation`, from `water_tag_precipitation`, splits each tag into three
parts: `ρq_tag_<name>` holds the water that is neither rain nor snow,
`ρq_rtag_<name>` the rain and `ρq_stag_<name>` the snow. It is a type
parameter too. It needs 1-moment microphysics, which the configuration checks,
and it is refused here with updraft copies. See
[`has_water_tag_precipitation`](@ref).

`precipitation_audit`, from `water_tag_precipitation_audit`, keeps the
microphysics audit of the rain and snow parts, `q_rtag_aud_<name>` and
`q_stag_aud_<name>`, as state fields. On by default. It matters only with
`precipitation`. Off, the audit's fields are not in the state and its kernels do
not run. The parts and every other field are the same either way. A type
parameter too. See [`has_water_tag_precipitation_audit`](@ref).

`leak_correction`, from `water_tag_leak_correction`, charges each tag the EDMF
vertical diffusion of its share of the rain and snow, which the parent does not
diffuse, on the grid mean and on the copies. Off by default. A type
parameter too. See [`correct_water_tag_diffusion_leak!`](@ref).

`rainout_jacobian`, from `water_tag_rainout_jacobian`, gives the tags' rows of
the manual Jacobian the derivatives of their implicit 0M rain-out, in the tag
and in `ρq_tot`. Off by default. A type parameter too. See
`has_water_tag_rainout_jacobian`.
"""
struct WaterTaggingModel{
    T <: Tuple,
    UpdraftCopies,
    TR <: AbstractWaterTagTransport,
    LedgerPerTag,
    Precipitation,
    LeakCorrection,
    RainoutJacobian,
    PrecipitationAudit,
}
    tags::T
    transport::TR
end
function WaterTaggingModel(
    tags::Tuple;
    updraft_copies::Bool = false,
    transport::AbstractWaterTagTransport = TracerWaterTagTransport(),
    ledger_per_tag::Bool = false,
    precipitation::Bool = false,
    leak_correction::Bool = false,
    rainout_jacobian::Bool = false,
    precipitation_audit::Bool = true,
)
    # The updraft copies of the rain and snow parts are not built.
    precipitation &&
        updraft_copies &&
        error(
            "`water_tag_precipitation: true` is refused with \
            `water_tag_updraft_copy: true`. The updraft copies of the rain and \
            snow parts are not built yet. Under `turbconv: prognostic_edmfx` \
            the parts follow the updraft without copies, so drop \
            `water_tag_updraft_copy`.",
        )
    # The correction gives the partition the parent's increment, less what the
    # partition's own tendencies moved. Without a partition the tags that carry
    # a source would take the parent's whole implicit transport on top of
    # their own.
    transport isa IncrementWaterTagTransport &&
        !any(_is_partition_tag, tags) &&
        error(
            "`water_tag_transport: increment` needs region tags without \
            sources that partition the domain. The correction gives them the \
            parent's increment of `ρq_tot`, less what their own tendencies \
            moved. Without them the tags that carry a source would take the \
            parent's whole implicit transport on top of their own. Add a \
            region and its complement, for example with `above: false` or \
            `inside: false`.",
        )
    return WaterTaggingModel{
        typeof(tags),
        updraft_copies,
        typeof(transport),
        ledger_per_tag,
        precipitation,
        leak_correction,
        rainout_jacobian,
        precipitation_audit,
    }(
        tags,
        transport,
    )
end

"""
    follows_water_increment(model)

Whether the water tags of `model` take the parent's own increment in each
implicit stage (`water_tag_transport: increment`). A property of the model's
type, so it folds away at compile time. `false` without water tags.
"""
follows_water_increment(::Nothing) = false
follows_water_increment(model::WaterTaggingModel) =
    model.transport isa IncrementWaterTagTransport

"""
    has_water_tag_updraft_copies(model)

Whether the water tags have a copy in each updraft, from the
`water_tag_updraft_copy` config key. `false` without water tags.
"""
has_water_tag_updraft_copies(::Nothing) = false
has_water_tag_updraft_copies(
    ::WaterTaggingModel{T, UpdraftCopies},
) where {T, UpdraftCopies} = UpdraftCopies

"""
    has_water_tag_ledger_per_tag(model)

Whether each water tag keeps its own state ledgers of the corrections, from the
`water_tag_ledger_per_tag` config key. `false` without water tags.
"""
has_water_tag_ledger_per_tag(::Nothing) = false
has_water_tag_ledger_per_tag(
    ::WaterTaggingModel{T, U, TR, LedgerPerTag},
) where {T, U, TR, LedgerPerTag} = LedgerPerTag

"""
    has_water_tag_precipitation(model)

Whether each water tag of `model` has a rain part and a snow part, from the
`water_tag_precipitation` config key. Then `ρq_tag_<name>` holds only the water
that is neither rain nor snow. A property of the model's type, so it folds away
at compile time. `false` without water tags.
"""
has_water_tag_precipitation(::Nothing) = false
has_water_tag_precipitation(
    ::WaterTaggingModel{T, U, TR, L, Precipitation},
) where {T, U, TR, L, Precipitation} = Precipitation

"""
    has_water_tag_leak_correction(model)

Whether the water tags of `model` are charged the EDMF vertical diffusion of
their share of the rain and snow, from the `water_tag_leak_correction` config
key. `false` without water tags.
"""
has_water_tag_leak_correction(::Nothing) = false
has_water_tag_leak_correction(
    ::WaterTaggingModel{T, U, TR, L, P, LeakCorrection},
) where {T, U, TR, L, P, LeakCorrection} = LeakCorrection

"""
    has_water_tag_rainout_jacobian(model)

Whether the tags' rows of the manual Jacobian carry the derivatives of their
implicit 0M rain-out, from the `water_tag_rainout_jacobian` config key. The
entries go in only where the tags lose water by the grid rule on
the implicit path, and only with the split solver
(`water_tag_rainout_jacobian_names`). `false` without water tags.
"""
has_water_tag_rainout_jacobian(::Nothing) = false
has_water_tag_rainout_jacobian(
    ::WaterTaggingModel{T, U, TR, L, P, LC, RainoutJacobian},
) where {T, U, TR, L, P, LC, RainoutJacobian} = RainoutJacobian

"""
    has_water_tag_precipitation_audit(model)

Whether the water tags of `model` keep the microphysics audit of their rain and
snow parts, `q_rtag_aud_<name>` and `q_stag_aud_<name>`, from the
`water_tag_precipitation_audit` config key. It needs the parts, so it is
`false` without [`has_water_tag_precipitation`](@ref), and `false` without
water tags.
"""
has_water_tag_precipitation_audit(::Nothing) = false
has_water_tag_precipitation_audit(
    model::WaterTaggingModel{T, U, TR, L, P, LC, RJ, PrecipitationAudit},
) where {T, U, TR, L, P, LC, RJ, PrecipitationAudit} =
    has_water_tag_precipitation(model) && PrecipitationAudit

"""
    EnergySourceTag{name}(region, source = :none)

Definition of one energy **source tag**, stored in the state as
`Y.c.ρe_src_<name>`. The tag `name` is a type parameter so that state field
names can be generated at compile time (GPU-compatible).

Fields mean what they do for [`TracerTag`](@ref), but the attribution rule
differs and that is the whole point of the separate type. A source tag holds an
amount of moist energy that is present now and is traced back to where it came
from: production is shared out by region mask and loss is taken from each tag in
proportion to what it already holds. That reading is **conditional**: it holds
only where the total the tags partition is positive, so the share is defined,
and only while the tag itself is non-negative. That total is `ρe_tot`, or
`ρe_tot + c·ρ` when `energy_source_tag_offset` is set. The results are an
attribution defined by the configured rules and the offset, not a unique
physical history. A `TracerTag` configured with `source` instead accumulates the
whole signed change of its processes and is a signed process tag.

`ρe_src_*` is **not guaranteed non-negative**. Three separate things can take
it below zero, and none of them is a defect in the rule.

The loss term is in proportion to what the tag holds, so the *rate* at which a
tag is depleted is `φ_k` times the parent's gross loss rate. That bounds the rate, not the
amount. What the attribution step produces is a tendency, and the timestepper
integrates it over a finite step, so the energy taken from a tag across one
step is about `dt * φ_k * Δ⁻`. Nothing ties that to the tag's holding. Parent
tendencies that cancel, say `+200` against `-200`, leave `ρe_tot` unchanged
while a tag receiving only the loss half crosses zero inside the step.
Clamping `φ_k` to `[0, 1]` cannot prevent this: the clamp acts on the share,
and the step length is what sets the amount.

Where that total is not positive the share is undefined and
[`energy_source_fraction`](@ref) returns zero, so no loss is applied there at
all. Moist total energy has no physical zero, so how much of a domain this
affects is a property of the chosen energy reference rather than a rare edge
case. An `energy_source_tag_offset` large enough to lift the total positive
everywhere is what removes the region, without moving the reference the model
itself uses.

The tags are also exempt from both tracer limiters through
[`is_tagged_tracer_name`](@ref) and ride the unlimited explicit transport path.

These are known limits of the current discrete implementation rather than
properties of the continuous rule. A negative value invalidates the
amount-of-energy and origin reading of that tag while it lasts. So by
default `repair_energy_source_tags!` puts negative tags back after each state
update, where the total is positive, and logs what it moved. With
`energy_source_tag_repair: false` nothing does.

`e_src_res` will not reveal it: that residual covers the region tags only,
so a source-labelled tag never enters it and region-tag errors of opposite sign
can cancel. Inspect each `e_src_<name>` for its minimum or sign instead, and
use the initialization warning and the closure check's `nonpositive_fraction`
for the parent.

This is the energy counterpart of [`WaterTag`](@ref), which already works this
way. Moist total energy has no physical zero, so unlike water the resulting
shares depend on the chosen `energy_source_tag_offset`. See
`docs/src/energy_source_tags.md`.
"""
struct EnergySourceTag{name, R <: Union{Nothing, AbstractTagRegion}, S <: Tuple} <:
       AbstractTracerTag{name}
    region::R
    sources::S
end
EnergySourceTag{name}(region::R, sources::S = ()) where {name, R, S <: Tuple} =
    EnergySourceTag{name, R, S}(region, sources)
EnergySourceTag{name}(region, source::Symbol) where {name} =
    EnergySourceTag{name}(region, source === :none ? () : (source,))

"""
    AbstractEnergySourceTransport

How the energy source tags are transported, from the
`energy_source_tag_transport` config key: [`TracerEnergySourceTransport`](@ref),
the default, [`EnthalpyEnergySourceTransport`](@ref), a comparison mode, or
[`EnthalpyIncrementEnergySourceTransport`](@ref), a prototype.
"""
abstract type AbstractEnergySourceTransport end

"""
    TracerEnergySourceTransport()

The default. Each energy source tag is moved as a passive tracer, by the same
advection, hyperdiffusion and closures as any other tracer. The parent moves
enthalpy, so the tags' sum drifts from the total they partition by pressure
work, and the closure residual `e_src_res` reports that.
"""
struct TracerEnergySourceTransport <: AbstractEnergySourceTransport end

"""
    EnthalpyEnergySourceTransport()

A comparison mode. In vertical and horizontal advection and in hyperdiffusion, each
energy source tag takes its share of the parent's own flux of `ρe_tot + c·ρ`.
So transport adds nothing to `e_src_res`, up to the timing of the step. It needs
an `energy_source_tag_offset`. Everything else the tags see is as under
[`TracerEnergySourceTransport`](@ref). See `docs/src/energy_source_tags.md`.
"""
struct EnthalpyEnergySourceTransport <: AbstractEnergySourceTransport end

"""
    EnthalpyIncrementEnergySourceTransport()

A prototype of the enthalpy comparison mode whose implicit part takes the
parent's own increment (increment transport). The tags take their shares of the parent's explicit fluxes, as under
[`EnthalpyEnergySourceTransport`](@ref). In each implicit stage they then take
the parent's increment of `ρe_tot + c·ρ`: after the Newton solve, the difference
between the parent's increment and theirs is moved as a vertical flux and
shared out by the cell it leaves. See `correct_energy_source_increment!`. It
needs an `energy_source_tag_offset`.
"""
struct EnthalpyIncrementEnergySourceTransport <: AbstractEnergySourceTransport end

"""
    EnergySourceTaggingModel(tags::Tuple, offset = nothing; repair = true,
                             transport = TracerEnergySourceTransport(),
                             updraft_copies = false, ledger_per_tag = false)

Model component holding a `Tuple` of [`EnergySourceTag`](@ref)s. Constructed
from the `energy_source_tags` config entry; see `AtmosTagging(::AtmosConfig)` in
`config/tracer_config.jl`.

`offset` is an energy per unit mass of air in J/kg, from the
`energy_source_tag_offset` config key, or `nothing`. With an offset `c` the tags
partition `ρe_tot + c·ρ` rather than `ρe_tot`. The model never uses that total,
so the simulated atmosphere is the same either way. See `energy_source_parent`.

`repair`, from the `energy_source_tag_repair` config key, keeps the tags
non-negative where their total is positive, without changing the sum of the
partition. It is on by default. Switched off, the tags go negative as the rule
and their transport make them, which is how to measure what the repair changes.
See `repair_energy_source_tags!`.

`transport`, from the `energy_source_tag_transport` config key, is how the tags
move: as passive tracers by default, by their shares of the parent's own flux
as a comparison mode, or by the parent's implicit increment as well. The last
two need
an offset, because a share is zero wherever the total is not positive, and
there the tags would not move. So they are refused without one. Increment
transport also needs region tags without sources that partition the domain, and
is refused without them. See [`EnthalpyEnergySourceTransport`](@ref) and
[`EnthalpyIncrementEnergySourceTransport`](@ref).

`updraft_copies`, from the `energy_source_tag_updraft_copy` config key, gives
each tag a copy in the updraft under `PrognosticEDMFX`. It is off by default.
Off, the sub-grid mass flux moves each tag by its share in the cell the flux
leaves, and the tags exchange composition at the updraft's mass flux, from a
steady entraining plume (`sgs_mass_flux_of_energy_source_tags!`). The exchange
gives each tag the updraft's composition instead of the grid mean's. On, it is a
comparison mode: the copies are passive updraft tracers, and the model moves
them as it moves any other. It is refused with the `enthalpy` transport. See
[`has_energy_source_updraft_copies`](@ref).

`ledger_per_tag`, from `energy_source_tag_ledger_per_tag`, gives each tag its
own state ledgers of what the corrections changed it by:
`e_src_led_fix_<name>` for the repair, and, under `enthalpy_increment`,
`e_src_led_inc_<name>` for the correction after each solve. Off by default,
since each adds a state field per tag. A type parameter, like
`updraft_copies`.
"""
struct EnergySourceTaggingModel{
    T <: Tuple,
    O <: Union{Nothing, AbstractFloat},
    TR <: AbstractEnergySourceTransport,
    UpdraftCopies,
    LedgerPerTag,
}
    tags::T
    offset::O
    repair::Bool
    transport::TR
end
function EnergySourceTaggingModel(
    tags::Tuple,
    offset = nothing;
    repair::Bool = true,
    transport::AbstractEnergySourceTransport = TracerEnergySourceTransport(),
    updraft_copies::Bool = false,
    ledger_per_tag::Bool = false,
)
    !(transport isa TracerEnergySourceTransport) && isnothing(offset) &&
        error(
            "`energy_source_tag_transport: \
            $(energy_source_transport_text(transport))` needs \
            `energy_source_tag_offset`. Each tag moves by its share of the total \
            the tags partition, and a share is zero wherever that total is not \
            positive, which under the default energy reference is much of the \
            domain. There the tags would not move at all. Set an offset large \
            enough to make the total positive everywhere.",
        )
    # The increment correction gives the partition the parent's increment,
    # less what the partition's own tendencies moved. Without a partition the
    # tags that carry a source would take the parent's whole implicit
    # transport on top of their own.
    transport isa EnthalpyIncrementEnergySourceTransport &&
        !any(_is_energy_partition_tag, tags) &&
        error(
            "`energy_source_tag_transport: enthalpy_increment` needs region \
            tags without sources that partition the domain. The correction \
            gives them the parent's increment of the total, less what their \
            own tendencies moved. Without them the tags that carry a source \
            would take the parent's whole implicit transport on top of their \
            own. Add a region and its complement, for example with \
            `above: false` or `inside: false`.",
        )
    # The copies move each tag by the model's tracer flux. Its sum over the
    # tags is not the parent's flux of the total, and under `enthalpy` nothing
    # would correct it. Under `enthalpy_increment` the correction after each
    # solve does.
    updraft_copies &&
        transport isa EnthalpyEnergySourceTransport &&
        error(
            "`energy_source_tag_updraft_copy: true` does not work with \
            `energy_source_tag_transport: enthalpy`. The copies move each tag \
            by the model's tracer flux of its updraft value, and the sum of \
            those fluxes is not the parent's flux of the total. Under \
            `enthalpy` nothing corrects that, so the difference would go to \
            `e_src_res`. Use `enthalpy_increment`, whose correction after \
            each solve takes it, or `tracer`.",
        )
    return EnergySourceTaggingModel{
        typeof(tags),
        typeof(offset),
        typeof(transport),
        updraft_copies,
        ledger_per_tag,
    }(
        tags,
        offset,
        repair,
        transport,
    )
end

"""
    has_energy_source_updraft_copies(model)

Whether the energy source tags have a copy in each updraft, from the
`energy_source_tag_updraft_copy` config key. It is a type parameter of
[`EnergySourceTaggingModel`](@ref), so the state can be built from it at compile
time. `false` without energy source tags.
"""
has_energy_source_updraft_copies(::Nothing) = false
has_energy_source_updraft_copies(
    ::EnergySourceTaggingModel{T, O, TR, UpdraftCopies},
) where {T, O, TR, UpdraftCopies} = UpdraftCopies

"""
    has_energy_source_ledger_per_tag(model)

Whether each energy source tag keeps its own state ledgers of the corrections,
from the `energy_source_tag_ledger_per_tag` config key. `false` without energy
source tags.
"""
has_energy_source_ledger_per_tag(::Nothing) = false
has_energy_source_ledger_per_tag(
    ::EnergySourceTaggingModel{T, O, TR, U, LedgerPerTag},
) where {T, O, TR, U, LedgerPerTag} = LedgerPerTag

"""
    RecordedProcess{name}()

One process whose applied change is accumulated by a
[`ProcessRecordModel`](@ref). The process `name` is a type parameter so that the
state field `prc_e_<name>` or `prc_q_<name>` can be looked up at compile time,
exactly as [`TracerTag`](@ref) does for its own state field.
"""
struct RecordedProcess{name} end

"""
    process_name(::RecordedProcess)

The `Symbol` naming the recorded process, e.g. `:radiation`.
"""
process_name(::RecordedProcess{name}) where {name} = name

"""
    ProcessRecordModel(processes::Tuple)

Model component holding a `Tuple` of [`RecordedProcess`](@ref)es. Constructed
from the `energy_process_record` or `water_process_record` config entry; see
`AtmosTagging(::AtmosConfig)` in `config/tracer_config.jl`.

A process record answers "what did this process do here", not "where did the
energy present come from". It accumulates the signed change each attributed
process applies, so gains are positive and losses negative.

Records are prognostic, because the applied-update event yields a rate and only
the timestepper can integrate it correctly across the stages. They are still never
transported: their state names carry no `ρ` prefix, so `gs_tracer_names` does
not see them.
"""
struct ProcessRecordModel{P <: Tuple}
    processes::P
end

"""
    AtmosTagging

Groups tagged-tracer models and types.
"""
@kwdef struct AtmosTagging{TM, WM, ESM, EPR, WPR}
    tagging_model::TM = nothing
    water_tagging_model::WM = nothing
    energy_source_tagging_model::ESM = nothing
    energy_process_record::EPR = nothing
    water_process_record::WPR = nothing
end
