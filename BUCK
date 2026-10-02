load("@nomimono//rules/lua:defs.bzl", "lua_library", "lua_test")

lua_library(
    name = "shroomi",
    srcs = ["init.lua", "components.lua", "css.lua", "utilities.lua", "markdown.lua", "policy.lua", "icons.lua", "page.lua", "lui.lua", "lui_scan.lua"],
    prefix = "shroomi",
    visibility = ["PUBLIC"],
)

[
    lua_test(
        name = name,
        src = name + ".lua",
        deps = [":shroomi"],
    )
    for name in ["shroomi_test", "css_test", "markdown_test", "lui_test"]
]
