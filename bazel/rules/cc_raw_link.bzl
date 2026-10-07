"""A link the reference performed with the linker itself, not the compiler
driver: the kernel's `ld -m elf_x86_64 -T vmlinux.lds ...`, its boot
`setup.elf`, `realmode.elf`, the vdso, a firmware image. cc_binary links
through the driver (its own crt, libs, flags); this rule runs the cc
toolchain's `ld` with the reference's line, inputs named by label:

    cc_raw_link(
        name = "setup_elf",
        out = "setup.elf",
        args = ["-m", "elf_i386", "-z", "noexecstack", "-T", "$(location arch/x86/boot/setup.ld)",
                "--whole-archive", "$(location :setup_elf_objs)", "--no-whole-archive"],
        srcs = ["arch/x86/boot/setup.ld"],          # files $(location ...) names
        deps = [":setup_elf_objs"],                  # cc targets: their archive stands for their objects
    )

`$(location :<dep>)` in `args` expands to the dep's own static library (or
its objects when it has none); every other `$(location ...)` is a file of
`srcs`. The action's mnemonic is CppLink, so any2bazel's differ compares its
line with the reference's. `-o` is the rule's.
"""

load("@rules_cc//cc:find_cc_toolchain.bzl", "find_cc_toolchain", "use_cc_toolchain")
load("@rules_cc//cc/common:cc_info.bzl", "CcInfo")

def _own_libraries(dep):
    # a cc target: its own static library (or its objects when it has none).
    # A produced archive (rules_cc+'s cc_static_library provides no CcInfo,
    # only the merged file): the file is the library.
    if CcInfo not in dep:
        return list(dep[DefaultInfo].files.to_list())
    out = []
    for li in dep[CcInfo].linking_context.linker_inputs.to_list():
        if li.owner != dep.label:
            continue
        for l in li.libraries:
            f = l.static_library or l.pic_static_library
            if f != None:
                out.append(f)
            else:
                out.extend(l.objects or l.pic_objects or [])
    return out

def _impl(ctx):
    tc = find_cc_toolchain(ctx)
    out = ctx.actions.declare_file(ctx.attr.out)
    inputs = list(ctx.files.srcs)
    subst = {}
    for d in ctx.attr.deps:
        libs = _own_libraries(d)
        inputs.extend(libs)
        for key in ("$(location :%s)" % d.label.name, "$(location %s)" % str(d.label),
                    "$(location //%s:%s)" % (d.label.package, d.label.name)):
            subst[key] = [f.path for f in libs]
    args = []
    for a in ctx.attr.args:
        if a in subst:
            args.extend(subst[a])
        else:
            args.append(ctx.expand_make_variables("args", ctx.expand_location(a, targets = ctx.attr.srcs), {}))
    ctx.actions.run(
        executable = tc.ld_executable,
        arguments = args + ["-o", out.path],
        inputs = depset(inputs, transitive = [tc.all_files]),
        outputs = [out],
        mnemonic = "CppLink",
        progress_message = "Linking %s with the linker itself" % out.short_path,
    )
    return [DefaultInfo(files = depset([out]))]

cc_raw_link = rule(
    implementation = _impl,
    attrs = {
        "out": attr.string(mandatory = True, doc = "the output file, as a path under the package (arch/x86/boot/setup.elf)"),
        "args": attr.string_list(mandatory = True, doc = "the linker's line, inputs as $(location ...)"),
        "srcs": attr.label_list(allow_files = True, doc = "files the line names (scripts, objects)"),
        "deps": attr.label_list(providers = [[CcInfo], [DefaultInfo]],
                                doc = "cc targets whose archives the line names (or a produced archive)"),
    },
    toolchains = use_cc_toolchain(),
    fragments = ["cpp"],
    doc = "A link by the cc toolchain's ld with the reference's own line (see the module docstring).",
)
