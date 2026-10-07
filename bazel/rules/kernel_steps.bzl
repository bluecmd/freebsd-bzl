"""The kernel's build steps, as rules.

Between the generated sources (kernel_generator.bzl) and the link, the
kernel build runs a handful of steps the tree drives with shell drivers and
environment: the offsets/assym tables (genoffset.sh / genassym.sh over the
compile products), config(8) over the kernel configuration file, newvers.sh
over the version metadata, the vDSO images (sys/tools/*_vdso.sh), the ACPI
wakecode stub, and rpcgen over the RPCSEC_TLS .x files. A genrule per step
copies the recipe; the rule is the step: the inputs it takes, the tools it
runs, the outputs it names, with the tree's own drivers underneath.

    load("//bazel/rules:kernel_steps.bzl", "gen_offsets", ...)

    gen_offsets(
        name = "assym_inc",
        archive = ":cc_061",            # the compile products archive
        member = "genassym.o",
        script = "//:sys/kern/genassym.sh",
        awk = "//usr.bin/awk:awk",
        out = "assym.inc",
    )

Each rule runs the same commands the tree's makefiles run for that step --
the drivers expect a compile-directory layout (a staged sys tree, the
generated headers beside them), so the actions stage it the same way.
"""

# the toolchain's target triple, as the drivers spell it
_DEFAULT_TARGET = "x86_64-unknown-freebsd15.1"


def _run_step(ctx, mnemonic, inputs, tools, outputs, command):
    ctx.actions.run_shell(
        mnemonic = mnemonic,
        inputs = inputs,
        tools = tools,
        outputs = outputs,
        command = command,
    )


def _gen_offsets_impl(ctx):
    # the generator reads the compiled member the makefiles left in the
    # compile directory and asks nm for its symbols; genassym.sh also runs
    # the tree's awk. Everything the script sees is named the way the
    # makefiles name it, from the compile directory the action stages.
    command = """
        A="$(pwd)/{archive}"
        NM="$(pwd)/{nm}"
        SH="$(pwd)/{script}"
        OUT="$(pwd)/{out_dir}"
        {awk_env}mkdir t && cd t
        ar p "$A" {member} > {member}
        NM="$NM" NMFLAGS= sh "$SH" {member} > "$OUT/{out}"
        cd .. && rm -rf t
    """.format(
        archive = ctx.file.archive.path,
        nm = ctx.file._nm.path,
        script = ctx.file.script.path,
        out_dir = ctx.outputs.out.dirname,
        out = ctx.outputs.out.basename,
        member = ctx.attr.member,
        awk_env = 'AWK="$(pwd)/%s" ' % ctx.executable._awk.path if ctx.attr.awk else "",
    )
    inputs = [ctx.file.archive, ctx.file.script]
    tools = [ctx.file._nm]
    if ctx.attr.awk:
        tools.append(ctx.executable._awk)
    _run_step(ctx, "GenOffsets", inputs, tools, [ctx.outputs.out], command)

gen_offsets = rule(
    implementation = _gen_offsets_impl,
    attrs = {
        # the compile-products archive (ar) the step's member sits in
        "archive": attr.label(mandatory = True, allow_single_file = True),
        # the member's name in the archive (genassym.o, genoffset.o, ...)
        "member": attr.string(mandatory = True),
        # genassym.sh / genoffset.sh: reads the member, nm(1) for symbols
        "script": attr.label(mandatory = True, allow_single_file = True),
        "awk": attr.label(default = None, executable = True, cfg = "exec"),
        "out": attr.output(mandatory = True),
        "_nm": attr.label(default = "@kernel_llvm//:bin/llvm-nm", allow_single_file = True),
        "_awk": attr.label(default = "//usr.bin/awk:awk", executable = True, cfg = "exec"),
    },
)

def _rpcgen_impl(ctx):
    rg = ctx.executable._rpcgen
    cpp = ctx.file._cpp
    x = ctx.file.x
    for out in ctx.outputs.outs:
        # -hM/-c/-lM pick the file; -M makes the sources MT-safe, as the
        # kernel's build does; -h/-l emit through a pipe, -c through -o
        flags = ctx.attr.flags[out.basename]
        pipe = ctx.attr.grep.get(out.basename)
        cpp_env = ('CPP="%s -target %s -B$(dirname %s)" ' %
                   (cpp.path, ctx.attr.target, cpp.path))
        if flags == "-c":
            command = '%s"%s" -c "%s" -o "%s"' % (cpp_env, rg.path, x.path, out.path)
        elif pipe:
            command = '%s"%s" %s "%s" | grep -v %s > "%s"' % (
                cpp_env, rg.path, flags, x.path, pipe, out.path)
        else:
            command = '%s"%s" %s "%s" > "%s"' % (cpp_env, rg.path, flags, x.path, out.path)
        _run_step(ctx, "RpcgenGenerate", [x], [rg, cpp], [out], command)

rpcgen_xdr = rule(
    implementation = _rpcgen_impl,
    attrs = {
        # the .x protocol description
        "x": attr.label(mandatory = True, allow_single_file = True),
        # per-output rpcgen mode flag (-hM for the header, -c xdr, -lM clnt)
        "flags": attr.string_dict(mandatory = True),
        # per-output filter the build's pipe applies (pthread.h, string.h)
        "grep": attr.string_dict(default = {}),
        "outs": attr.output_list(mandatory = True),
        "target": attr.string(default = _DEFAULT_TARGET),
        "_rpcgen": attr.label(default = "//usr.bin/rpcgen:rpcgen", executable = True, cfg = "exec"),
        "_cpp": attr.label(default = "@kernel_llvm//:bin/clang-cpp", allow_single_file = True),
    },
)

def _newvers_impl(ctx):
    # newvers.sh queries the build through MAKE for what it cannot see: the
    # compiler line (-V CC) and the kernel identity (-V KERN_IDENT). The
    # tree's make -V answers come from a shim that echoes the toolchain's
    # clang; the year comes from the staged COPYRIGHT.
    mk = ctx.actions.declare_file("_%s_mk" % ctx.label.name)
    ctx.actions.write(output = mk, content = """#!/bin/sh
case "$1 $2" in
"-V CC") echo "$CCCMD";;
"-V KERN_IDENT") echo BZL;;
*) exit 1;;
esac
""", is_executable = True)
    command = """
        MAKE="$(pwd)/{mk}" CCCMD="$(pwd)/{cc}" sh "$(pwd)/{script}" -R -d /usr/obj/usr/src/amd64.amd64/sys/{conf} {conf}
        mv vers.c version "{out_dir}/"
    """.format(
        mk = mk.path, cc = ctx.file._cc.path,
        script = ctx.file.script.path, conf = ctx.attr.conf,
        out_dir = ctx.outputs.vers.dirname,
    )
    _run_step(ctx, "NewversGenerate",
              inputs = [ctx.file.script, ctx.file.copyright, mk] + list(ctx.files.sources),
              tools = [ctx.file._cc],
              outputs = [ctx.outputs.vers, ctx.outputs.version],
              command = command)

newvers = rule(
    implementation = _newvers_impl,
    attrs = {
        # sys/conf/newvers.sh, run with the tree's version files staged
        "script": attr.label(mandatory = True, allow_single_file = True),
        "copyright": attr.label(mandatory = True, allow_single_file = True),
        # other files newvers.sh reads (sys/sys/param.h for the version)
        "sources": attr.label_list(allow_files = True),
        # the kernel configuration's name (BZL): -d dir and the identity
        "conf": attr.string(default = "BZL"),
        "vers": attr.output(mandatory = True),
        "version": attr.output(mandatory = True),
        "_cc": attr.label(default = "@kernel_llvm//:bin/clang", allow_single_file = True),
    },
)

def _vdso_impl(ctx):
    # the vDSO driver script compiles the signal trampoline, links it as a
    # shared object and extracts its offsets -- all from a compile directory
    # holding the staged sys tree, opt_global.h and the generated offset
    # headers, with machine/x86/i386 pointing into it. ELFDUMP is left
    # unset: there is no elfdump in the sandbox, exactly as in the reference
    # build, where its RELOCS check fails silently.
    wd = "$(pwd)"
    command = """
        SYS="{wd}/sys"
        G="{wd}/{gen}"
        OUT="{wd}/{out_dir}"
        LD="$(pwd)/{ld}"
        AWK="$(pwd)/{awk}"
        NM="$(pwd)/{nm}"
        CC="$(pwd)/{cc}"
        SCRIPT="$(pwd)/{script}"
        mkdir t && cd t
        cp "$G/{opt_global}" .
        cp "$G/{assym}" .
        ln -s "$SYS/amd64/include" machine
        ln -s "$SYS/x86/include" x86
        {i386}CC="$CC -target {target} -B$(dirname $CC)" \\
            LD="$LD" AWK="$AWK" NM="$NM" ELFDUMP=elfdump S="$SYS" \\
            sh "$SCRIPT"
        {mvs}
        cd .. && rm -rf t
    """.format(
        wd = wd,
        gen = ctx.file.assym.dirname,
        out_dir = ctx.outputs.outs[0].dirname,
        opt_global = ctx.file.opt_global.basename,
        assym = ctx.file.assym.basename,
        i386 = 'ln -s "$SYS/i386/include" i386\n' if ctx.attr.i386 else "",
        cc = ctx.file._cc.path,
        ld = ctx.file._ld.path,
        awk = ctx.executable._awk.path,
        nm = ctx.file._nm.path,
        target = ctx.attr.target,
        script = ctx.file.script.path,
        mvs = " && ".join(["mv %s \"$OUT/\"" % o.basename for o in ctx.outputs.outs]),
    )
    _run_step(ctx, "VdsoGenerate",
              inputs = [ctx.file.script, ctx.file.assym, ctx.file.opt_global] +
                       list(ctx.files.includes) + list(ctx.files.sources),
              tools = [ctx.file._cc, ctx.file._ld,
                       ctx.file._nm, ctx.executable._awk],
              outputs = list(ctx.outputs.outs),
              command = command)

vdso_image = rule(
    implementation = _vdso_impl,
    attrs = {
        # sys/tools/amd64_vdso.sh / amd64_ia32_vdso.sh
        "script": attr.label(mandatory = True, allow_single_file = True),
        # the staged compile directory's generated headers
        "opt_global": attr.label(mandatory = True, allow_single_file = True),
        "assym": attr.label(mandatory = True, allow_single_file = True),
        # the staged sys tree the include symlinks point into
        "includes": attr.label_list(allow_files = True),
        # the trampoline, its wrap file and the linker script
        "sources": attr.label_list(allow_files = True),
        "i386": attr.bool(default = False, doc = "stage the i386 include symlink too (ia32 vDSO)"),
        "outs": attr.output_list(mandatory = True),
        "target": attr.string(default = _DEFAULT_TARGET),
        "_cc": attr.label(default = "@kernel_llvm//:bin/clang", allow_single_file = True),
        "_ld": attr.label(default = "@kernel_llvm//:bin/ld.lld", allow_single_file = True),
        "_nm": attr.label(default = "@kernel_llvm//:bin/llvm-nm", allow_single_file = True),
        "_awk": attr.label(default = "//usr.bin/awk:awk", executable = True, cfg = "exec"),
    },
)

def _acpi_wakecode_impl(ctx):
    # the real-mode wake stub: compiled (in the archive the step's cc
    # target left it), stripped to its binary, its symbols as #defines and
    # the binary itself as a C array, exactly the pipeline the makefiles
    # run for it.
    command = """
        A="$(pwd)/{archive}"
        OC="$(pwd)/{objcopy}"
        NM="$(pwd)/{nm}"
        F2C="$(pwd)/{file2c}"
        OUT="$(pwd)/{out_dir}"
        mkdir t && cd t
        ar p "$A" {member} > {member}
        "$OC" -S -O binary {member} acpi_wakecode.bin
        "$NM" -n --defined-only {member} |
            while read offset dummy what; do
                printf '#define\\t%s\\t0x%s\\n' "$what" "$offset"
            done > acpi_wakedata.h
        "$F2C" -sx 'static char wakecode[] = {{' '}};' < acpi_wakecode.bin > acpi_wakecode.h
        mv acpi_wakecode.bin acpi_wakecode.h acpi_wakedata.h "$OUT/"
        cd .. && rm -rf t
    """.format(
        archive = ctx.file.archive.path,
        member = ctx.attr.member,
        objcopy = ctx.file._objcopy.path,
        nm = ctx.file._nm.path,
        file2c = ctx.executable._file2c.path,
        out_dir = ctx.outputs.bin.dirname,
    )
    _run_step(ctx, "AcpiWakecode",
              inputs = [ctx.file.archive],
              tools = [ctx.file._objcopy, ctx.file._nm, ctx.executable._file2c],
              outputs = [ctx.outputs.bin, ctx.outputs.hdr, ctx.outputs.data],
              command = command)

acpi_wakecode = rule(
    implementation = _acpi_wakecode_impl,
    attrs = {
        # the archive holding the compiled stub
        "archive": attr.label(mandatory = True, allow_single_file = True),
        "member": attr.string(default = "acpi_wakecode.o"),
        "bin": attr.output(mandatory = True),
        "hdr": attr.output(mandatory = True),
        "data": attr.output(mandatory = True),
        "_objcopy": attr.label(default = "@kernel_llvm//:bin/llvm-objcopy", allow_single_file = True),
        "_nm": attr.label(default = "@kernel_llvm//:bin/llvm-nm", allow_single_file = True),
        "_file2c": attr.label(default = "//usr.bin/file2c:file2c", executable = True, cfg = "exec"),
    },
)

def _kernel_config_impl(ctx):
    # config(8) over the kernel's configuration file, into the compile
    # directory the tree stages for it: config resolves the file's
    # includes (DEFAULTS, the machine's conf dir) through the symlink farm
    # it expects, writes its outputs next to the directory (-d) and the
    # build takes the sources and the opt_*.h option headers from there.
    command = """
        CFG="$(pwd)/{config}"
        BZL="$(pwd)/{conf_file}"
        OUT="$(pwd)/{out_dir}"
        W="$(pwd)/w"
        mkdir -p w/sys/amd64 w/sys
        ln -s ../../../sys/amd64/conf w/sys/amd64/conf
        ln -s ../../sys/conf w/sys/conf
        cd w/sys/amd64/conf
        "$CFG" -d "$OUT/_cfg" -I "$(pwd)" "$BZL"
        cp "$OUT/_cfg"/config.c "$OUT/_cfg"/env.c "$OUT/_cfg"/hints.c \\
           "$OUT/_cfg"/opt_*.h "$OUT/"
        cd "$OUT" && rm -rf _cfg "$W"
    """.format(
        config = ctx.executable._config.path,
        conf_file = ctx.file.conf.path,
        out_dir = ctx.outputs.outs[0].dirname,
    )
    _run_step(ctx, "KernelConfig",
              inputs = [ctx.file.conf] + list(ctx.files.conf_includes),
              tools = [ctx.executable._config],
              outputs = list(ctx.outputs.outs),
              command = command)

kernel_config = rule(
    implementation = _kernel_config_impl,
    attrs = {
        # the kernel configuration file (sys/amd64/conf/BZL)
        "conf": attr.label(mandatory = True, allow_single_file = True),
        # files the configuration's include line pulls in (DEFAULTS, ...)
        "conf_includes": attr.label_list(allow_files = True),
        # the option headers (opt_*.h), config.c, env.c, hints.c
        "outs": attr.output_list(mandatory = True),
        "_config": attr.label(default = "//usr.sbin/config:config", executable = True, cfg = "exec"),
    },
)
