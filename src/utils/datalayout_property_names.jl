import ClimaCore: DataLayouts

# ClimaCore gives the names of a data layout with `filter`, which hides the
# fields of size zero. From 32 names on, `filter` builds its tuple at run time,
# so every name lookup on a large `Y.c` allocates. Tags add fields to `Y.c`.
# This method applies the same rule to a `NamedTuple` element type, but at
# compile time. It is more specific than ClimaCore's method, so it adds a
# method and replaces none.
@generated function Base.propertynames(
    ::DataLayouts.DataLayout{T},
) where {T <: NamedTuple}
    names = filter(name -> sizeof(fieldtype(T, name)) > 0, fieldnames(T))
    return :($names)
end
