# report — 2026-10-09

*(updated as the run proceeds; verdict at the end)*

## State at run start

PARITY build=GREEN diff=converged errors=0 warnings=132 artifacts=converged
0 errors. IDIOM score=8.9 (threshold 8.9): packages_vs_dirs 8.8 +
genrules_per_tu 0.1, every other detector 0. HERMETIC OK and BOOT-SSH OK
carried from 2026-10-07. any2bazel main at cec8b97; the linux loop's
per-directory-package machinery (package_dirs) is on `kbuild-intree`, not
merged.

## What landed

The kernel package `sys/BZL` was split into **one package per kernel
source directory** (135 new packages; the transform:
`split_packages.py` in this run dir, one-off, hand-shaped because the
kernel BUILD is not emitter-reproducible):

- The 22 compile groups whose sources are tree files moved to the
  package of their source directory; a group spanning directories
  (cc_003 = 1,027 sources over 103 dirs) was split per directory.
  Pieces are cut on *runs* of one directory in the group's srcs (the
  list spells the reference's link-line object order, and alphabetical
  listing interleaves a parent dir with its subdirs), so a repeated
  dir's later run is `cc_NNN_2` — 155 pieces total. Piece order in the
  kernel link's deps is the reference's object order; the transform
  self-checks the pre/post source sequence over the spliced deps.
- The reference's link consumes loose objects (`OutputGroupInfo(objects)`)
  in deps order, not archives, and the differ is grouping-agnostic for
  libraries — so regrouping is parity-neutral as long as the object
  sequence is preserved. The 2026-10-07 "cc_NNN archives load-bearing"
  conclusion was re-examined and holds only for the three groups whose
  archives gen_offsets / acpi_wakecode read *by member* (cc_000, cc_061,
  cc_062 — kept in `sys/BZL`, srcs re-spelled to package labels).
- Staying in `sys/BZL`: all codegen (kernel_config, makeobjops/awk
  generators, newvers, vdso, rpcgen_xdr, wakecode), the filegroup
  "generated", force-dynamic-hack, both freebsd_kernel_link targets, and
  the 25 generated-source groups.
- 91 of the 135 dirs hold headers → a `headers` filegroup carrier each
  (glob `**/*.h`, `**/*.inc` — covering the dir's unpackaged subdirs);
  the root package's kernel_headers/sys_headers/makefs_includes take the
  carrier labels (`glob(...) + [labels]` — Starlark does not flatten a
  nested glob). New packages `exports_files(glob(["**/*"]))` so files in
  an unpackaged subtree of a packaged dir (a nested `*_if.m`) are
  addressable as `//pkg:sub/file`.
- Cross-package references re-spelled `//:sys/<dir>/<f>` →
  `//<dir>:<f>` (nearest packaged ancestor); `makeobjops` derives its
  outs from the src label and learned to strip a `pkg:file` component.
  `outs` spell generator output paths relative to sys/BZL's bin dir and
  are deliberately NOT re-spelled.

## Results

- `bazel build //sys/BZL:kernel`: GREEN (1,159 actions).
- PARITY build=GREEN diff=converged errors=0 warnings=132
  artifacts=converged — identical warning count to the pre-split state.
- IDIOM **0.8** (threshold was 8.9): packages_vs_dirs ~0.7
  (377 rules / 167 dirs), genrules_per_tu 0.1, everything else 0.

## Results

*(to be filled)*

## What remains

- The 32 compiled-source dirs that still have no own package are host-tool
  implementation dirs (`usr.sbin/makefs/ffs`, `usr.bin/m4`,
  `contrib/one-true-awk`, `lib/libc/*`, …) — sources of one tool each,
  not tree-layout directories; splitting them buys ~0.7 of score for a
  second round of hand re-spelling. Not taken.
- 7 genrules remain (0.1 of score): force-dynamic-hack.c and the image
  deliverable's copy/rootdisk glue. All other detectors are 0
  (recipe_replay, env_replayed, shape_duplicates, tool_as_genrule,
  manual_rules, grp_splits, todo, layering, include_flags,
  repeated_flags, hermeticity).
- The linux loop's generic `package_dirs` emitter machinery is still not
  merged to any2bazel main; this run did the equivalent by hand for
  FreeBSD's shape (the kernel BUILD is not emitter-reproducible). If a
  later run wants the host tools split too, the generic machinery is the
  right tool.

## Verdict

publish: release

- PARITY build=GREEN diff=converged errors=0 warnings=132
  artifacts=converged (unchanged from the pre-split state; verified twice,
  before and after the formatting pass).
- IDIOM score=0.8 — previous release threshold 8.9, so well under it.
- HERMETIC OK: //bazel/image:image builds in a clean container.
- BOOT-SSH OK after 3s: FreeBSD 15.1-RELEASE (kernel 15.3MB + UFS root
  disk, PVH direct boot, virtio, sshd up).
- The tree at /scratch/bluecmd/freebsd-bzl/freebsd is the base tag plus
  the layer with this run's changes (135 new per-directory packages,
  re-spelled sys/BZL / root / consumer BUILD files, one-line makeobjops
  basename fix in bazel/rules/kernel_generator.bzl). The one-off
  transform and its manifest live in this run dir
  (split_packages.py, split_manifest.json; `--restore` undoes it).
