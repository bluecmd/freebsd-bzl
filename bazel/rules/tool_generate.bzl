"""A host tool's one-invocation codegen step, as a rule.

Several of the layer's tools generate a source of their own build: config(8)
runs file2c over kernconf.tmpl for its kernconfstr table, awk's build runs
its maketab tool over the generated grammar header for proctab.c. Each is
the tree's own program run once over declared inputs, writing stdout to a
named file; the rule states the tool, its inputs and its outputs instead of
hand-driving it from a genrule.

    load("//bazel/rules:tool_generate.bzl", "tool_generate")

    tool_generate(
        name = "kernconf",
        srcs = ["kernconf.tmpl"],
        tool = "//usr.bin/file2c:file2c",
        outs = ["kernconf.c"],
        cmd = "$(location //usr.bin/file2c:file2c) ... > $(RULEDIR)/kernconf.c",
    )

`cmd` is the one invocation the tree's makefile runs -- $(location) labels
expand as in a genrule, and $(RULEDIR) is this rule's output directory. The
stdout-into-file redirection stays a shell fact because that is the tools'
interface; everything else (inputs, outputs, the tool) is declared.
"""

def _tool_generate_impl(ctx):
    cmd = ctx.expand_location(ctx.attr.cmd, ctx.attr.srcs + [ctx.attr.tool])
    # the genrule spelling of the output directory; the rule's outputs live
    # in the same place
    cmd = cmd.replace("$(RULEDIR)", ctx.outputs.outs[0].dirname)
    ctx.actions.run_shell(
        mnemonic = "ToolGenerate",
        inputs = ctx.files.srcs,
        tools = [ctx.executable.tool],
        outputs = list(ctx.outputs.outs),
        command = cmd,
    )

tool_generate = rule(
    implementation = _tool_generate_impl,
    attrs = {
        "srcs": attr.label_list(allow_files = True),
        # the tree's own generator program (a host tool of this workspace)
        "tool": attr.label(mandatory = True, executable = True, cfg = "exec"),
        # the generated files, addressed by their file labels downstream
        "outs": attr.output_list(mandatory = True),
        "cmd": attr.string(mandatory = True, doc = "the tree's one invocation"),
    },
)
