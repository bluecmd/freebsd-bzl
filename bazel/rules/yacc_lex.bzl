"""The tree's parser generators, as rules.

yacc(1) and lex(1) drive several of the layer's parsers: the kernel's
rpcsec_tls .x files go through rpcgen (kernel_steps.bzl), m4's parser and
awk's grammar go through the tree's own yacc (usr.bin/yacc:byacc), config's
parser through the same and its scanner through the tree's flex with the
m4boot the scanner's M4PATH lookup expects. The generator runs once per
grammar and writes its files into the working directory under the names
yacc/lex choose (y.tab.c beside a -d, the -o name and its .h); the rule
declares the names the tree's build calls them by and moves them there.

    load("//bazel/rules:yacc_lex.bzl", "yacc_generate", "lex_generate")

    yacc_generate(
        name = "m4_parser",
        src = "parser.y",
        args = "-d -o parser.c",
        produced = ["parser.c", "parser.h"],
        outs = ["parser.c", "parser.h"],
    )

`produced` is what the one yacc/lex run writes, `outs` what the build's
consumers include -- usually the same names, config's parser excepted
(y.tab.c -> config.c, y.tab.h kept).
"""

def _yacc_impl(ctx):
    # one yacc run over the grammar; -d is what turns on the header
    command = """
        YACC="$(pwd)/{yacc}"
        SRC="$(pwd)/{src}"
        OUT="$(pwd)/{out_dir}"
        mkdir g && cd g
        "$YACC" {args} "$SRC"
        {mvs}
        cd .. && rm -rf g
    """.format(
        yacc = ctx.executable._yacc.path,
        src = ctx.file.src.path,
        args = ctx.attr.args,
        out_dir = ctx.outputs.outs[0].dirname,
        mvs = " && ".join(["mv %s \"$OUT/%s\"" % (p, o.basename)
                          for p, o in zip(ctx.attr.produced, ctx.outputs.outs)]),
    )
    ctx.actions.run_shell(
        mnemonic = "YaccGenerate",
        inputs = [ctx.file.src],
        tools = [ctx.executable._yacc],
        outputs = list(ctx.outputs.outs),
        command = command,
    )

yacc_generate = rule(
    implementation = _yacc_impl,
    attrs = {
        "src": attr.label(mandatory = True, allow_single_file = True),
        # the flags the build's makefile passes (the -o name steers where
        # the parser and, with -d, its header land)
        "args": attr.string(default = "-d"),
        # the file names yacc writes into the working directory
        "produced": attr.string_list(mandatory = True),
        "outs": attr.output_list(mandatory = True),
        "_yacc": attr.label(default = "//usr.bin/yacc:yacc", executable = True, cfg = "exec"),
    },
)

def _lex_impl(ctx):
    # flex finds its m4 through PATH; the tree's makefiles point PATH at a
    # directory holding an `m4` link to the bootstrapped m4boot
    command = """
        LEX="$(pwd)/{lex}"
        M4="$(pwd)/{m4}"
        SRC="$(pwd)/{src}"
        OUT="$(pwd)/{out_dir}"
        mkdir s && cd s
        ln -sf "$M4" m4
        PATH="$(pwd):$PATH" "$LEX" {args} "$SRC"
        {mvs}
        cd .. && rm -rf s
    """.format(
        lex = ctx.executable._lex.path,
        m4 = ctx.executable._m4.path,
        src = ctx.file.src.path,
        args = ctx.attr.args,
        out_dir = ctx.outputs.outs[0].dirname,
        mvs = " && ".join(["mv %s \"$OUT/%s\"" % (p, o.basename)
                          for p, o in zip(ctx.attr.produced, ctx.outputs.outs)]),
    )
    ctx.actions.run_shell(
        mnemonic = "LexGenerate",
        inputs = [ctx.file.src],
        tools = [ctx.executable._lex, ctx.executable._m4],
        outputs = list(ctx.outputs.outs),
        command = command,
    )

lex_generate = rule(
    implementation = _lex_impl,
    attrs = {
        "src": attr.label(mandatory = True, allow_single_file = True),
        "args": attr.string(default = ""),
        "produced": attr.string_list(mandatory = True),
        "outs": attr.output_list(mandatory = True),
        "_lex": attr.label(default = "//usr.bin/lex:lex", executable = True, cfg = "exec"),
        # the bootstrapped m4 the scanner's macros run through
        "_m4": attr.label(default = "//usr.bin/m4:m4boot", executable = True, cfg = "exec"),
    },
)
