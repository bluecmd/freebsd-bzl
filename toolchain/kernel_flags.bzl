"""The kernel's own compile line as the recorded reference cross-build spelled
it (models/kernel/model.capture.json, the 1091-TU base set; each entry is a
mechanical copy of the reference's argv tokens, never typed from memory).

Split as:
  KERNEL_COPTS        everything universal across every kernel TU (compiles of
                      kernel.full, the unlinked genassym/genoffset/bootstrap
                      objects and the force-dynamic-hack .pico) -- the
                      `kernel_compile_flags` feature of the kernel cc
                      toolchain.
  KERNEL_DIR_COPTS    the compile-directory facts every kernel TU carries:
                      -I$(GENDIR) (the reference's `-I.` with cwd sys/BZL),
                      the source-tree include roots, HAVE_KERNEL_OPTION_HEADERS
                      and the `-include opt_global.h` that only exists in the
                      compile directory. Shared copts of the kernel targets.
  KERNEL_WERROR       -Werror, which the rpcgen-generated rpctls_* files do
                      NOT carry in the reference (FreeBSD compiles those
                      without it) -- a shared copt, not a toolchain flag.
"""

KERNEL_COPTS = [
    # the reference's cross-target identity (its argv's first tokens, spelled
    # by the cross-build driver): without it clang targets the host and
    # __FreeBSD__ is undefined, which sends the tree's headers down their
    # linux/host branches.
    "-target",
    "x86_64-unknown-freebsd15.1",
    "-O2",
    "-pipe",
    "-fno-strict-aliasing",
    "-g",
    "-nostdinc",
    "-D_KERNEL",
    "-fno-common",
    "-fno-omit-frame-pointer",
    "-mno-omit-leaf-frame-pointer",
    "-mcmodel=kernel",
    "-mno-red-zone",
    "-mno-mmx",
    "-mno-sse",
    "-msoft-float",
    "-fno-asynchronous-unwind-tables",
    "-ffreestanding",
    "-fwrapv",
    "-fstack-protector",
    "-gdwarf-4",
    "-Wall",
    "-Wstrict-prototypes",
    "-Wmissing-prototypes",
    "-Wpointer-arith",
    "-Wcast-qual",
    "-Wundef",
    "-Wno-pointer-sign",
    "-D__printf__=__freebsd_kprintf__",
    "-Wmissing-include-dirs",
    "-fdiagnostics-show-option",
    "-Wno-unknown-pragmas",
    "-Wswitch",
    "-Wno-error=tautological-compare",
    "-Wno-error=empty-body",
    "-Wno-error=parentheses-equality",
    "-Wno-error=unused-function",
    "-Wno-error=pointer-sign",
    "-Wno-error=shift-negative-value",
    "-Wno-address-of-packed-member",
    "-Wno-format-zero-length",
    "-mno-aes",
    "-mno-avx",
    "-std=gnu17",
]

KERNEL_DIR_COPTS = [
    "-I$(GENDIR)",
    "-Isys",
    "-Isys/contrib/ck/include",
    "-Isys/contrib/libfdt",
    "-DHAVE_KERNEL_OPTION_HEADERS",
    "-include",
    "$(GENDIR)/opt_global.h",
]

KERNEL_WERROR = [
    "-Werror",
]
