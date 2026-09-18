#=
B1's pointwise residual against the pointwise energy scale.

`energy_tag_residual.csv` from `reduce_run.jl` gives `max |e_tag_res|` per time.
The docs state that in a 10-day dry baroclinic wave "the residual stayed below
one percent of the pointwise energy scale" (`docs/src/tagged_tracers.md`). To
set B1 beside that, this reads the three 6-hourly NetCDF fields and forms
`e_tot = e_tag_tropics + e_tag_extratropics + e_tag_res` pointwise, since the two
pure region tags and the residual add up to the parent by definition.

For each day it prints `max |e_tag_res|`, `max |e_tot|`, their ratio, and the
99th percentile of `|e_tag_res| / max |e_tot|` over the points.

    julia +1.11 --project=.buildkite \
        experiments/tag_closure/analysis/b1_residual_scale.jl <output_dir>

All fields are the NetCDF writer's bilinear remap to latitude and longitude, so
these are reductions over the remapped grid, not over the model's own nodes.
=#
import NCDatasets as NC

dir = ARGS[1]
read_field(name) = NC.NCDataset(joinpath(dir, "$(name)_6h_inst.nc")) do ds
    (Array(ds["time"]), Array(ds[name]))
end
t, res = read_field("e_tag_res")
_, tropics = read_field("e_tag_tropics")
_, extratropics = read_field("e_tag_extratropics")

println("day, max_abs_res, max_abs_e_tot, ratio, q99_ratio")
for k in eachindex(t)
    t[k] % 86400 == 0 || continue
    r = selectdim(res, 1, k)
    e_tot = selectdim(tropics, 1, k) .+ selectdim(extratropics, 1, k) .+ r
    scale = maximum(abs, e_tot)
    ratios = sort(vec(abs.(r))) ./ scale
    q99 = ratios[ceil(Int, 0.99 * length(ratios))]
    println(
        join(
            (t[k] / 86400, maximum(abs, r), scale, maximum(abs, r) / scale, q99),
            ", ",
        ),
    )
end
