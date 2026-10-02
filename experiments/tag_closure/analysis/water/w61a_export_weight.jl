#=
W61 addendum, review check (not pre-registered). The driver `w61a_inventory.jl`
sums each tag's surface precipitation with `sum(sfc)`, where `sfc` lives on the
bottom face level of the 3D space, `axes(Fields.level(ᶠJ, half))`. That level
keeps the 3D quadrature weight, so `sum` returns the area integral times a
height. This script measures that height on W61's grid and checks that it is
the same at every point, so the scorer can divide the export by it.

    julia --project=<env> w61a_export_weight.jl
=#
import ClimaComms
ClimaComms.@import_required_backends
import ClimaAtmos as CA
import ClimaCore: Spaces, Fields

for deep_atmosphere in (false, true)
    grid = CA.SphereGrid(
        Float64;
        z_elem = 10,
        z_max = 30000.0,
        dz_bottom = 500.0,
        h_elem = 6,
        nh_poly = 3,
        deep_atmosphere,
    )
    (; center_space, face_space) = CA.get_spaces(grid)
    horizontal = Spaces.horizontal_space(center_space)
    sfc_J = Fields.level(Fields.local_geometry_field(face_space).J, Fields.half)
    J_h = Fields.local_geometry_field(horizontal).J
    J_ratio = Fields.Field(Fields.field_values(sfc_J), horizontal) ./ J_h
    # A field that varies with latitude, integrated both ways.
    lat = Fields.coordinate_field(horizontal).lat
    f_h = @. 1 + cosd(lat)^3
    f_sfc = Fields.Field(Fields.field_values(f_h), axes(sfc_J))
    z_1 = Fields.level(Fields.coordinate_field(center_space).z, 1)
    println(
        "deep_atmosphere = $deep_atmosphere: J(face) / J(horizontal) in ",
        extrema(J_ratio),
        "; sum on the face level / sum on the horizontal space = ",
        sum(f_sfc) / sum(f_h),
        "; z of the first centre in ",
        extrema(z_1),
        "; horizontal area ",
        sum(ones(horizontal)),
    )
end
