"""makefs_image: the images a boot test consumes, laid by the tree's makefs(8).

Both deliverable images are one mechanism: a staging script (a sibling of
the rule, its docstring holding the recipe) populates a staging tree from
the pinned release's base.txz, then the layer's own makefs(8) lays the
image. A genrule cannot be the shape: the staging script cds into the tree
it makes (makefs resolves the El Torito bootimage path against its cwd) and
the recipe is a project step, not a shell one-liner. The rules keep the
action a single script invocation; `python3` comes from the environment,
every other input comes from Bazel.

    load("//bazel/rules:makefs_image.bzl", "boot_iso", "ufs_rootdisk")

    boot_iso(name = "cdboot", ...)
    ufs_rootdisk(name = "rootdisk", ...)
"""

def _run_stage(ctx, out, flags, inputs, tools):
    """Run the staging script: `python3 <stage> <flags> --out <image>`.

    `flags` is the flat [flag, path, ...] tail; the script's location is
    relative to the execroot and the action's cwd is the execroot, and the
    script absolutizes what it must before it moves its own cwd into the
    staging tree.
    """
    argv = ctx.actions.args()
    argv.add(ctx.file.stage.path)
    argv.add_all(flags)
    # out.path (execroot-relative, under bazel-out) — the declared output's
    # real path, what a genrule's $@ expands to; the staging script derives
    # its staging tree and makefs target from it.
    argv.add("--out", out.path)
    ctx.actions.run_shell(
        command = "python3 \"$@\"",
        arguments = [argv],
        inputs = depset([ctx.file.stage], transitive = [inputs]),
        tools = tools,
        outputs = [out],
        use_default_shell_env = True,
        mnemonic = "MakefsImage",
    )

def _boot_iso_impl(ctx):
    out = ctx.actions.declare_file(ctx.attr.out)
    flags = ["--base-txz", ctx.file.base_txz.path,
             "--kernel", ctx.file.kernel.path,
             "--makefs", ctx.executable.makefs.path]
    inputs = depset([ctx.file.base_txz, ctx.file.kernel])
    _run_stage(ctx, out, flags, inputs, [ctx.executable.makefs])
    return [DefaultInfo(files = depset([out]))]

boot_iso = rule(
    implementation = _boot_iso_impl,
    attrs = {
        "stage": attr.label(allow_single_file = True, mandatory = True,
                            doc = "the staging script (argparse: --base-txz --kernel --makefs --out)"),
        "base_txz": attr.label(allow_single_file = True, mandatory = True,
                               doc = "the base system archive /boot is staged from"),
        "kernel": attr.label(allow_single_file = True, mandatory = True,
                             doc = "the kernel ELF, installed as /boot/kernel/kernel"),
        "makefs": attr.label(executable = True, cfg = "exec", mandatory = True,
                             doc = "makefs(8) from the tree, the image's tool"),
        "out": attr.string(mandatory = True, doc = "the image file's name"),
    },
    doc = "The El Torito boot CD for the TCG boot test (cdboot -> loader -> kernel; see make-cdboot.py).",
)

def _ufs_rootdisk_impl(ctx):
    out = ctx.actions.declare_file(ctx.attr.out)
    flags = ["--base-txz", ctx.file.base_txz.path,
             "--rc", ctx.file.rc.path,
             "--authorized-keys", ctx.file.authorized_keys.path,
             "--makefs", ctx.executable.makefs.path,
             "--readelf", ctx.executable.readelf.path]
    inputs = depset([ctx.file.base_txz, ctx.file.rc, ctx.file.authorized_keys])
    _run_stage(ctx, out, flags, inputs,
               [ctx.executable.makefs, ctx.executable.readelf])
    return [DefaultInfo(files = depset([out]))]

ufs_rootdisk = rule(
    implementation = _ufs_rootdisk_impl,
    attrs = {
        "stage": attr.label(allow_single_file = True, mandatory = True,
                            doc = "the staging script (argparse: --base-txz --rc --authorized-keys --makefs --readelf --out)"),
        "base_txz": attr.label(allow_single_file = True, mandatory = True,
                               doc = "the base system archive the root disk's programs are staged from"),
        "rc": attr.label(allow_single_file = True, mandatory = True,
                         doc = "the /etc/rc the image boots with"),
        "authorized_keys": attr.label(allow_single_file = True, mandatory = True,
                                      doc = "the test key root accepts"),
        "makefs": attr.label(executable = True, cfg = "exec", mandatory = True,
                             doc = "makefs(8) from the tree, the image's tool"),
        "readelf": attr.label(executable = True, cfg = "exec", mandatory = True,
                              doc = "readelf(1), the toolchain's, for the image's checks"),
        "out": attr.string(mandatory = True, doc = "the image file's name"),
    },
    doc = "The UFS root disk the boot test hands the kernel (see make-rootdisk.py).",
)
