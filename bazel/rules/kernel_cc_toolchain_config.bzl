"""A cc toolchain config for Linux kernel code: the kernel's own compile line
as toolchain features (docs/FRONTEND-kbuild.md, docs/DESIGN-kbuild.md).

Kbuild compiles every object of a module with a line that is a function of
the kernel tree and its .config: `-nostdinc`, the tree's include roots, the
`-include` chain, `-D__KERNEL__`, the arch, codegen and warning flags. That
line belongs to a toolchain, not to a BUILD file; `scripts/probe_kernel.py`
writes it from a recorded module build as `KERNEL_COPTS` /
`KERNEL_INCLUDE_DIRS`, and this rule turns them into a CcToolchainConfigInfo
a `kernel_module` compiles with (selected through its platform transition).

    load("@any2bazel_rules//:kernel_cc_toolchain_config.bzl", "kernel_cc_toolchain_config")
    load(":kernel_flags.bzl", "KERNEL_COPTS", "KERNEL_INCLUDE_DIRS")

    kernel_cc_toolchain_config(
        name = "octeon_kernel_cc_toolchain_config",
        tool_prefix = "/opt/toolchain/bin/mips64-openwrt-linux-musl-",
        copts = KERNEL_COPTS,
        builtin_include_directories = KERNEL_INCLUDE_DIRS,
        env = {"STAGING_DIR": "..."},          # what a vendor's compiler wrapper needs
        target_cpu = "mips64", target_system_name = "mips64-openwrt-linux-musl",
    )

The module's own objects are linked by `ld -r` (kernel_module.bzl runs the
toolchain's `ld` itself), so no link features are defined here.
"""

load("@rules_cc//cc:action_names.bzl", "ACTION_NAMES")
load(
    "@rules_cc//cc:cc_toolchain_config_lib.bzl",
    "action_config",
    "env_entry",
    "env_set",
    "feature",
    "flag_group",
    "flag_set",
    "tool",
    "tool_path",
    "variable_with_value",
)
load("@rules_cc//cc/common:cc_common.bzl", "cc_common")
load("@rules_cc//cc/toolchains:cc_toolchain_config_info.bzl", "CcToolchainConfigInfo")

_compile_actions = [
    ACTION_NAMES.c_compile,
    ACTION_NAMES.cpp_compile,
    ACTION_NAMES.assemble,
    ACTION_NAMES.preprocess_assemble,
    ACTION_NAMES.cpp_header_parsing,
]

_TOOLS = ["gcc", "g++", "cpp", "ld", "ar", "nm", "objcopy", "objdump", "strip", "gcov"]

_ACTIONS_BY_TOOL = {
    "gcc": _compile_actions + [ACTION_NAMES.cpp_link_executable, ACTION_NAMES.cpp_link_dynamic_library,
                               ACTION_NAMES.cpp_link_nodeps_dynamic_library],
    "ar": [ACTION_NAMES.cpp_link_static_library],
    "strip": [ACTION_NAMES.strip],
}

def _impl(ctx):
    if ctx.attr.tool_prefix:
        p = ctx.attr.tool_prefix
        tool_paths = [tool_path(name = t, path = p + ctx.attr.tools.get(t, t)) for t in _TOOLS]
        action_configs = []
    else:
        # tools by label: the hermetic LLVM repository's files (toolchains_llvm)
        tool_paths = []
        files = {"gcc": ctx.file.clang, "ar": ctx.file.ar, "strip": ctx.file.strip}
        action_configs = [
            action_config(action_name = a, enabled = True, tools = [tool(tool = f)])
            for name, f in files.items()
            if f != None
            for a in _ACTIONS_BY_TOOL[name]
        ]
    features = [
        # how the archiver is driven (what the tool_paths route gets from
        # Bazel's legacy features; an action_config toolchain spells it)
        feature(
            name = "archiver_flags",
            enabled = True,
            flag_sets = [
                flag_set(
                    actions = [ACTION_NAMES.cpp_link_static_library],
                    flag_groups = [
                        flag_group(flags = ["rcsD"]),
                        flag_group(flags = ["%{output_execpath}"], expand_if_available = "output_execpath"),
                    ],
                ),
                flag_set(
                    actions = [ACTION_NAMES.cpp_link_static_library],
                    flag_groups = [flag_group(
                        iterate_over = "libraries_to_link",
                        flag_groups = [
                            flag_group(
                                flags = ["%{libraries_to_link.name}"],
                                expand_if_equal = variable_with_value(name = "libraries_to_link.type", value = "object_file"),
                            ),
                            flag_group(
                                flags = ["%{libraries_to_link.object_files}"],
                                iterate_over = "libraries_to_link.object_files",
                                expand_if_equal = variable_with_value(name = "libraries_to_link.type", value = "object_file_group"),
                            ),
                        ],
                        expand_if_available = "libraries_to_link",
                    )],
                ),
            ],
        ),
        feature(
            name = "kernel_compile_flags",
            # off by default: the targets of a directory that compiles with
            # its own regime of the kernel's line (realmode, boot, the vDSOs)
            # must NOT carry it -- they spell their whole line, and Bazel has
            # no per-target way to switch a feature off (`disabled_features`
            # is native-only). So the targets whose argv carries the whole
            # line request it (`features = ["kernel_compile_flags"]`,
            # emit_build.py), and the others don't.
            enabled = False,
            flag_sets = [flag_set(
                actions = _compile_actions,
                flag_groups = [flag_group(flags = ctx.attr.copts)],
            )],
        ),
    ]
    if ctx.attr.env:
        features.append(feature(
            name = "kernel_env",
            enabled = True,
            env_sets = [env_set(
                actions = _compile_actions,
                env_entries = [env_entry(key = k, value = v) for k, v in ctx.attr.env.items()],
            )],
        ))
    return cc_common.create_cc_toolchain_config_info(
        ctx = ctx,
        toolchain_identifier = ctx.attr.toolchain_identifier or ctx.label.name,
        host_system_name = "local",
        target_system_name = ctx.attr.target_system_name,
        target_cpu = ctx.attr.target_cpu,
        target_libc = "kernel",
        compiler = "gcc",
        abi_version = ctx.attr.abi_version,
        abi_libc_version = "kernel",
        tool_paths = tool_paths,
        action_configs = action_configs,
        features = features,
        cxx_builtin_include_directories = ctx.attr.builtin_include_directories,
    )

kernel_cc_toolchain_config = rule(
    implementation = _impl,
    attrs = {
        "tool_prefix": attr.string(doc = "a non-hermetic toolchain: its tool path prefix (…/bin/<triple>-)"),
        "tools": attr.string_dict(doc = "with tool_prefix: tool name -> suffix when it is not the name (ar -> gcc-ar)"),
        "clang": attr.label(allow_single_file = True, doc = "a hermetic toolchain: the compiler file (@llvm_toolchain_llvm//:bin/clang)"),
        "ar": attr.label(allow_single_file = True),
        "strip": attr.label(allow_single_file = True),
        "copts": attr.string_list(mandatory = True, doc = "KERNEL_COPTS: the kernel's compile line, in order"),
        "builtin_include_directories": attr.string_list(mandatory = True,
                                                        doc = "KERNEL_INCLUDE_DIRS: the directories that line searches"),
        "env": attr.string_dict(doc = "environment every compile gets"),
        "target_cpu": attr.string(mandatory = True),
        "target_system_name": attr.string(mandatory = True),
        "abi_version": attr.string(default = "kernel"),
        "toolchain_identifier": attr.string(),
    },
    provides = [CcToolchainConfigInfo],
)
