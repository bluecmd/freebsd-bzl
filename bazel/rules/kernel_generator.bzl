"""The kernel's generated sources, as rules.

A kernel source tree generates a slice of its C from data-driven tables: the
bus method interfaces (.m through sys/tools/makeobjops.awk), vnode_if.src
(sys/tools/vnode_if.awk), the ACPI quirks table. The generator is the tree's
own awk program (//usr.bin/awk:awk, built by the layer) and the tree's own
awk script; a mode flag picks the output. Spelling that per interface is 60
copies of the same recipe; the rule is one.

    load("//bazel/rules:kernel_generator.bzl", "awk_generate", "makeobjops")

    makeobjops(name = "acpi_if", src = "//:sys/dev/acpica/acpi_if.m")
        # -> acpi_if.c and acpi_if.h

    awk_generate(
        name = "vnode_if",
        src = "//:sys/kern/vnode_if.src",
        script = "//:sys/tools/vnode_if.awk",
        outs = {"vnode_if.c": "-c", "vnode_if.h": "-h",
                "vnode_if_newproto.h": "-p", "vnode_if_typedef.h": "-t"},
    )

The output name is the one the generator writes (it derives it from the
source's basename), so `outs` maps the written name to its mode flag; each
entry is its own action, exactly the one invocation the tree's makefiles
run for that output.
"""

def _awk_generate_impl(ctx):
    awk = ctx.executable._awk
    src = ctx.file.src
    script = ctx.file.script
    for out in ctx.outputs.outs:
        # the generator's mode flag goes last, after the source
        mode = ctx.attr.modes.get(out.basename) or ""
        # the generator stamps the source path it was given into the output's
        # provenance comment; the tree's makefiles passed it absolute, and the
        # reference's records carry that spelling, so the source is named
        # $PWD/... (the action's execroot) -- the same spelling the genrule
        # this rule replaced used
        given = "$PWD/" + src.path
        command = '"%s" -f "%s" "%s" %s && mv %s "%s"' % (
            awk.path, script.path, given, mode, out.basename, out.path)
        ctx.actions.run_shell(
            mnemonic = "AwkGenerate",
            inputs = [src, script],
            tools = [awk],
            outputs = [out],
            command = command,
        )

awk_generate = rule(
    implementation = _awk_generate_impl,
    attrs = {
        "src": attr.label(mandatory = True, allow_single_file = True),
        "script": attr.label(mandatory = True, allow_single_file = True),
        # predeclared outputs: the generated files are addressed by their file
        # labels downstream (the kernel's filegroup lists each one)
        "outs": attr.output_list(mandatory = True),
        "modes": attr.string_dict(default = {}, doc = "generated file name -> the generator's mode flag"),
        "_awk": attr.label(default = "//usr.bin/awk:awk", executable = True, cfg = "exec"),
    },
)

def makeobjops(name, src, **kwargs):
    """sys/tools/makeobjops.awk over a bus interface (.m): its .c and .h."""
    base = src.rsplit("/", 1)[-1].rsplit(":", 1)[-1].rsplit(".", 1)[0]
    awk_generate(
        name = name,
        src = src,
        script = "//:sys/tools/makeobjops.awk",
        outs = [base + ".c", base + ".h"],
        modes = {
            base + ".c": "-c",
            base + ".h": "-h",
        },
        **kwargs
    )
