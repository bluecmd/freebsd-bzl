"""cc_per_source_library: a cc_library whose sources each get flags of their own.

Some builds give every object a flag or two that no other object gets:
CMake's `set_source_files_properties(... COMPILE_DEFINITIONS)`, Kbuild's
per-object `-DKBUILD_BASENAME="x" -DKBUILD_MODNAME="y"` on every file. A
plain cc_library cannot say that, and one cc_library per source is no
library. This rule compiles each source with `cc_common.compile` under the
selected cc toolchain (so every object is an ordinary CppCompile), adding
`per_source_copts[src]` to the target's `copts`, archives them like a
cc_library and provides CcInfo, so it drops into `deps` anywhere.

    load("//bazel/rules:cc_per_source_library.bzl", "cc_per_source_library")

    cc_per_source_library(
        name = "init",
        srcs = ["main.c", "version.c"],
        hdrs = ["init.h"],
        copts = ["-fno-function-sections"],
        per_source_copts = {
            "main.c": ['-DKBUILD_BASENAME=\\"main\\"'],
            "version.c": ['-DKBUILD_BASENAME=\\"version\\"'],
        },
        deps = ["//:kernel_headers"],
    )

A project with a rule for the pattern (a kernel's `kernel_library` macro
deriving the defines from the file names) wraps this; the emitter writes
the explicit map.
"""

load("@rules_cc//cc:find_cc_toolchain.bzl", "find_cpp_toolchain", "use_cc_toolchain")
load("@rules_cc//cc/common:cc_common.bzl", "cc_common")
load("@rules_cc//cc/common:cc_info.bzl", "CcInfo")

_SOURCE_EXTS = (".c", ".cc", ".cpp", ".cxx", ".S", ".s", ".m", ".mm")

def _stem(f):
    b = f.basename
    return b[:b.rfind(".")] if "." in b else b

def _per_source_key(f, package):
    sp = f.short_path
    if package and sp.startswith(package + "/"):
        return sp[len(package) + 1:]
    return sp

def _expand(ctx, flag):
    """A copt as cc_library treats one: Bazel's predefined make variables
    expanded (`-I$(GENDIR)/include`) and Bourne-shell tokenized, so a
    quoted define (`-DKBUILD_MODNAME=\"ext4\"`) reaches the compiler as
    `-DKBUILD_MODNAME="ext4"`, one token."""
    return ctx.tokenize(ctx.expand_make_variables("copts", flag, {}))


def _impl(ctx):
    tc = find_cpp_toolchain(ctx)
    fc = cc_common.configure_features(
        ctx = ctx,
        cc_toolchain = tc,
        requested_features = ctx.features,
        unsupported_features = ctx.disabled_features,
    )
    dep_ccinfos = [d[CcInfo] for d in ctx.attr.deps if CcInfo in d]
    dep_cctxs = [c.compilation_context for c in dep_ccinfos]
    pkg = ctx.label.package
    includes = []
    for inc in ctx.attr.includes:
        rel = pkg if inc in ("", ".") else (pkg + "/" + inc if pkg else inc)
        includes.append(rel)
        includes.append(ctx.bin_dir.path + "/" + rel)
    srcs = [f for f in ctx.files.srcs if f.basename.endswith(_SOURCE_EXTS)]
    private_hdrs = [f for f in ctx.files.srcs if not f.basename.endswith(_SOURCE_EXTS)]
    per = ctx.attr.per_source_copts
    cctxs = []
    outs = []
    for src in srcs:
        key = _per_source_key(src, pkg)
        extra = per.get(key, per.get(src.basename, []))
        cctx, co = cc_common.compile(
            actions = ctx.actions,
            feature_configuration = fc,
            cc_toolchain = tc,
            name = ctx.label.name + "/" + _stem(src),
            srcs = [src],
            public_hdrs = ctx.files.hdrs,
            private_hdrs = private_hdrs,
            includes = includes,
            defines = ctx.attr.defines,
            local_defines = ctx.attr.local_defines,
            user_compile_flags = [t for c in list(ctx.attr.copts) + list(extra) for t in _expand(ctx, c)],
            additional_inputs = ctx.files.additional_compiler_inputs,
            compilation_contexts = dep_cctxs,
        )
        cctxs.append(cctx)
        outs.append(co)
    if not srcs:
        cctx, co = cc_common.compile(
            actions = ctx.actions, feature_configuration = fc, cc_toolchain = tc, name = ctx.label.name,
            public_hdrs = ctx.files.hdrs, includes = includes, defines = ctx.attr.defines,
            compilation_contexts = dep_cctxs)
        cctxs.append(cctx)
        outs.append(co)
    merged_outs = cc_common.merge_compilation_outputs(compilation_outputs = outs)
    linking_context, linking_outputs = cc_common.create_linking_context_from_compilation_outputs(
        actions = ctx.actions,
        feature_configuration = fc,
        cc_toolchain = tc,
        compilation_outputs = merged_outs,
        name = ctx.label.name,
        linking_contexts = [c.linking_context for c in dep_ccinfos],
        disallow_dynamic_library = True,
        alwayslink = ctx.attr.alwayslink,
    )
    files = []
    if linking_outputs.library_to_link:
        lib = linking_outputs.library_to_link
        files = [f for f in [lib.static_library, lib.pic_static_library] if f != None]
    exported = cc_common.merge_compilation_contexts(compilation_contexts = cctxs[:1] + dep_cctxs)
    return [
        DefaultInfo(files = depset(files)),
        CcInfo(compilation_context = exported, linking_context = linking_context),
        OutputGroupInfo(objects = depset(merged_outs.objects + merged_outs.pic_objects)),
    ]

cc_per_source_library = rule(
    implementation = _impl,
    attrs = {
        "srcs": attr.label_list(allow_files = True),
        "hdrs": attr.label_list(allow_files = True),
        "deps": attr.label_list(providers = [CcInfo]),
        "includes": attr.string_list(doc = "package-relative include roots (source and genfiles twin)"),
        "defines": attr.string_list(),
        "local_defines": attr.string_list(),
        "copts": attr.string_list(doc = "flags every source gets"),
        "per_source_copts": attr.string_list_dict(doc = "package-relative source (or basename) -> its own flags"),
        "additional_compiler_inputs": attr.label_list(allow_files = True,
                                                      doc = "files a compile reads besides headers (an .incbin'd blob)"),
        "alwayslink": attr.bool(default = False),
        "linkstatic": attr.bool(default = True, doc = "accepted for cc_library parity; the rule only ever archives"),
    },
    fragments = ["cpp"],
    toolchains = use_cc_toolchain(),
    provides = [CcInfo],
    doc = "A cc_library whose sources each get flags of their own; CppCompile per source, one archive, CcInfo.",
)
