# Print the Downgrade workflow's test matrix, `groups=[...]`, for
# `$GITHUB_OUTPUT`: the groups of `test/runtests.jl`'s `KNOWN_TEST_GROUPS`,
# less "all". It parses that file and evaluates only the one assignment, so no
# test runs. It fails, rather than printing a partial list, if the assignment
# is missing or is not a literal tuple of plain names, or if a name repeats.
text = read(joinpath(@__DIR__, "..", "test", "runtests.jl"), String)
is_groups(e) =
    e isa Expr && e.head == :const && e.args[1] isa Expr &&
    e.args[1].head == :(=) && e.args[1].args[1] == :KNOWN_TEST_GROUPS
definitions = filter(is_groups, Meta.parseall(text).args)
length(definitions) == 1 || error(
    "expected one `const KNOWN_TEST_GROUPS = (...)` in test/runtests.jl, found $(length(definitions))",
)
value = definitions[1].args[1].args[2]
(value isa Expr && value.head == :tuple && all(x -> x isa String, value.args)) || error(
    "KNOWN_TEST_GROUPS is not a literal tuple of strings; update .github/read_test_groups.jl with it",
)
names = String.(value.args)
allunique(names) || error("KNOWN_TEST_GROUPS repeats a name")
all(n -> occursin(r"^[a-z0-9_]+$", n), names) ||
    error("KNOWN_TEST_GROUPS has a malformed name")
"all" in names || error("KNOWN_TEST_GROUPS lacks \"all\"")
groups = filter(!=("all"), names)
isempty(groups) && error("KNOWN_TEST_GROUPS lists no group besides \"all\"")
println("groups=[", join(map(n -> "\"$n\"", groups), ","), "]")
