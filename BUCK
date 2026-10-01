load("@monomono//rules/lua:defs.bzl", "lua_library", "lua_test")

lua_library(
    name = "shroomi",
    srcs = ["init.lua", "components.lua", "css.lua", "utilities.lua", "template.lua", "markdown.lua", "policy.lua"],
    prefix = "shroomi",
    visibility = ["PUBLIC"],
)

[
    lua_test(
        name = name,
        src = name + ".lua",
        deps = [":shroomi"],
    )
    for name in ["shroomi_test", "css_test", "markdown_test"]
]
