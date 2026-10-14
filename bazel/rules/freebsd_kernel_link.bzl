"""The FreeBSD kernel's link and objcopy endgame.

The reference links `kernel.full` with the linker itself
(`ld.lld -m elf_x86_64_fbsd -T sys/conf/ldscript.amd64 ... <objects>
force-dynamic-hack.pico`), then `objcopy --only-keep-debug kernel.full
kernel.debug` and `objcopy --strip-debug --add-gnu-debuglink=kernel.debug
kernel.full kernel`. The objects come from the kernel compile targets' loose
object output groups (OutputGroupInfo(objects) -- cc_per_source_library), not
from an archive: the reference links loose .o files, and `ld.lld -X` +
`--export-dynamic` wants every TU's objects in the line. Mnemonic KernelLink
(the value project.env carries in EXTRA_MNEMONICS) so the differ compares the
link line with the reference's.
"""

load("@rules_cc//cc:find_cc_toolchain.bzl", "find_cc_toolchain", "use_cc_toolchain")
load("@rules_cc//cc/common:cc_info.bzl", "CcInfo")

def _objects(dep):
    """The dep's loose objects: cc targets expose them as their `objects`
    output group (cc_per_source_library); a plain files provider stands in
    for a single-file dep (the force-dynamic-hack .pico)."""
    if OutputGroupInfo in dep:
        g = getattr(dep[OutputGroupInfo], "objects", None)
        if g != None:
            return list(g.to_list())
    return list(dep[DefaultInfo].files.to_list())

def _impl(ctx):
    tc = find_cc_toolchain(ctx)
    full = ctx.actions.declare_file(ctx.attr.out)
    debug = ctx.actions.declare_file(ctx.attr.debug_out) if ctx.attr.debug_out else None
    stripped = ctx.actions.declare_file(ctx.attr.stripped_out) if ctx.attr.stripped_out else None

    # the line: the reference's tokens, the objects appended after.
    # $(location ...) expands against srcs (and the driver); $(GENDIR) against
    # the bin tree, exactly as the cc compiles' copts expand it.
    drv = [ctx.attr.driver] if ctx.attr.driver else []
    args = [ctx.expand_make_variables(
                "args",
                ctx.expand_location(a, targets = ctx.attr.srcs + drv),
                {"GENDIR": ctx.bin_dir.path},
            ) for a in ctx.attr.args]
    exe = ctx.file.driver if ctx.attr.driver else tc.ld_executable
    drv_files = [ctx.file.driver] if ctx.attr.driver else []
    objs = []
    picked = list(ctx.attr.object_files.keys())
    for d in ctx.attr.deps:
        if d in picked:
            continue
        objs.extend(_objects(d))
    # single files picked out of a multi-output dep (the vDSO link objects
    # are outs of the vdso genrules, which also carry the sigtramp .pico and
    # the offsets header that must NOT be linked)
    # the dict's keys are the dep targets, its values the basename list
    for dep, names in ctx.attr.object_files.items():
        want = names.split(",")
        for f in dep.files.to_list():
            if f.basename in want:
                objs.append(f)
    # shared libraries linked by name: `-L<dir> -l:<basename>`. The reference
    # passes its -shared hack object by bare basename (its link runs in the
    # object directory); lld records the searched name in DT_NEEDED, so a
    # path spelling here would put the sandbox path into the kernel's
    # dynamic section instead of the reference's bare name.
    libs = []
    libfiles = []
    for d in ctx.attr.shared_libs:
        for f in d[DefaultInfo].files.to_list():
            libs += ["-L", f.dirname, "-l:" + f.basename]
            libfiles.append(f)
    ctx.actions.run(
        executable = exe,
        arguments = args + [o.path for o in objs] + libs + ["-o", full.path],
        inputs = depset(objs + libfiles + list(ctx.files.srcs) + drv_files,
                        transitive = [tc.all_files]),
        outputs = [full],
        mnemonic = "KernelLink",
        progress_message = "Linking the kernel %s" % full.short_path,
    )

    outs = [full]
    # kernel.full -> kernel.debug (keep debug) -> kernel (strip debug,
    # --add-gnu-debuglink points at kernel.debug, so it is an input). The
    # kernel endgame only; a bare -shared link (the force-dynamic-hack .pico)
    # produces its single file and stops.
    if debug != None:
        ctx.actions.run(
            executable = tc.objcopy_executable,
            arguments = ["--only-keep-debug", full.path, debug.path],
            inputs = depset([full], transitive = [tc.all_files]),
            outputs = [debug],
            mnemonic = "ObjcopyEndgame",
            progress_message = "Keeping debug info of %s" % debug.short_path,
        )
        outs.append(debug)
    if stripped != None:
        ctx.actions.run(
            executable = tc.objcopy_executable,
            # the debuglink is opened in the action's cwd, which in the sandbox
            # is the execroot: spell the path as the execroot sees it (objcopy
            # still stores the file's basename in .gnu_debuglink)
            arguments = ["--strip-debug", "--add-gnu-debuglink=" + debug.path,
                         full.path, stripped.path],
            inputs = depset([full, debug], transitive = [tc.all_files]),
            outputs = [stripped],
            mnemonic = "ObjcopyEndgame",
            progress_message = "Stripping %s" % stripped.short_path,
        )
        outs.append(stripped)
    groups = {"kernel_full": [full]}
    if stripped != None:
        groups["kernel"] = [stripped]
    if debug != None:
        groups["kernel_debug"] = [debug]
    return [
        DefaultInfo(files = depset(outs)),
        OutputGroupInfo(**groups),
    ]

freebsd_kernel_link = rule(
    implementation = _impl,
    attrs = {
        "out": attr.string(mandatory = True, doc = "kernel.full, under the package"),
        "debug_out": attr.string(doc = "kernel.debug; the objcopy endgame runs when set"),
        "stripped_out": attr.string(doc = "stripped kernel; requires debug_out"),
        "args": attr.string_list(mandatory = True, doc = "the reference's link line; $(location ...) names files of srcs"),
        "srcs": attr.label_list(allow_files = True, doc = "files the line names (the ldscript)"),
        "deps": attr.label_list(providers = [[CcInfo], [DefaultInfo]],
                                doc = "the kernel's compile targets (loose objects via OutputGroupInfo(objects))"),
        "shared_libs": attr.label_list(
            doc = "shared libraries linked by name (-L<dir> -l:<basename>; lld records the searched name in DT_NEEDED)"),
        "driver": attr.label(allow_single_file = True,
            doc = "compiler driver to run instead of the linker (the reference drives its -shared links through the compiler)"),
        "object_files": attr.label_keyed_string_dict(
            doc = "dep -> comma-separated basenames of its files to append to the link, in attribute order"),
    },
    toolchains = use_cc_toolchain(),
    fragments = ["cpp"],
    doc = "The kernel's ld link + objcopy endgame (see module docstring).",
)
