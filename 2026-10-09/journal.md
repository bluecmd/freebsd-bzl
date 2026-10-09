# journal — 2026-10-09

## Round 0: reading the state (00:30-01:00)

- Parity-before (run dir): GREEN, converged, 132 warnings, artifacts
  converged. IDIOM 8.9 — packages_vs_dirs 8.8 is 99% of the remaining
  score; every other detector is zero.
- Feedback = the two prior runs' verdict lines only (2026-10-05
  pre-release, 2026-10-07 release at IDIOM 8.9, tool merged=no).
- Sibling linux loop (2026-10-08): went from one root package to **one
  package per Kbuild directory** (2,322 BUILD files) with the generic
  `package_dirs` conventions key in emit_build.py (commits 56b90e5,
  8b08627, 21a3c8c, 8049f8f), IDIOM 19.9 → 5.2, parity held. Those commits
  are on `kbuild-intree` (worktree wt-kernel) but **not merged** into
  `main` (cec8b97) — our branch predates them.
- The layer: root package + `sys/BZL` (3,421 lines). 57
  `cc_per_source_library` groups, 49 single-dir, 8 multi-dir (cc_003 =
  1,027 sources over 103 dirs). `freebsd_kernel_link` consumes each
  group's **loose objects** via `OutputGroupInfo(objects)` in `deps` order
  spelled as the reference's link-line order — the reference links loose
  .o files, not archives.
- 2026-10-07's rejection of the split ("cc_NNN archives load-bearing") is
  re-examined: the link takes objects, not archives; the differ is
  grouping-agnostic for libraries. The load-bearing thing is the object
  sequence, which a regrouping preserves if spelled carefully. Plan written
  with this as the go/no-go gate (step 2).
- Toolchain: the layer's kernel toolchain defines `kernel_compile_flags`
  (feature) — d392e8b is in; the include supply already rides the feature
  + `//:kernel_headers`.

Plan: runs/2026-10-09/plan.md. Report stubbed.

## Round 1: the split transform (01:00-02:30)

- Rewrote split_packages.py from scratch (third version, incremental
  testing): ast-parse sys/BZL/BUILD.bazel; 22 groups movable (57 total;
  35 kept: 3 KEEP_GROUPS cc_000/cc_061/cc_062 whose archives gen_offsets /
  acpi_wakecode read by member, 25 generated-source groups, plus the
  codegen targets and both links stay).
- Pieces are cut on RUNS of one directory in the group's srcs (the srcs
  list spells the reference link-line object order, and alphabetical
  listing interleaves a parent dir's files with its subdirs' — sys/crypto
  appears twice inside cc_003), so a repeated dir's later run becomes
  `cc_NNN_2`. 155 pieces over 135 dirs.
- Link-order self-check: pre/post source sequences over the spliced link
  deps are equal for both freebsd_kernel_link targets.
- 90 of the 135 dirs hold headers → "headers" filegroup carriers
  (glob(["**/*.h","**/*.inc"]) covers the dir's unpackaged subdirs);
  root's kernel_headers/sys_headers globs become glob(...) + [carrier
  labels], makefs_includes takes the two sys/fs carriers.
- Bugs hit and fixed on the way: glob-matching anchors (comment lines
  between the rule call and its name; single-line globs have no
  `\n    ),` — replaced line-anchored surgery with a balanced-bracket
  expr_end scanner); Starlark does NOT flatten `[glob(...), labels]` —
  must spell `glob(...) + [labels]`; awk_generate outs spell the
  generator's OUTPUT paths relative to sys/BZL's bin dir and must not be
  re-spelled (respell_stay is line-based, skips outs); makeobjops derives
  outs from the src label (fixed to strip a `pkg:file` component);
  per-piece text must carry only the piece's own srcs (the first cut
  embedded the whole group, duplicating names and crossing subpackages);
  and the patch that added single-line exports_files handling had
  dropped the `root = "\n".join(out)` line, making the entry-drop loop
  dead code for a while (also restricted it to plain exports_files
  lists — glob patterns and include roots are not file lists).
- bazel query //... is clean (0 errors, 376 targets). Kernel build
  started.

- After the hdr_dirs walk fix (do not descend only into dirs that are
  themselves packages — the old filter excluded everything), 91 carriers;
  fe_25_5/constants.h now reaches kernel_headers through the ref10
  carrier. `bazel build //sys/BZL:kernel` GREEN: 1159 actions. On to
  parity.sh.

## Round 2: parity (02:30-03:10)

- parity.sh: PARITY build=GREEN diff=converged errors=0 warnings=132
  artifacts=converged — byte-for-byte the same warning count as the
  pre-split state. IDIOM score=0.8 (was 8.9): packages_vs_dirs ~0.7
  (377 rules / 167 dirs), genrules_per_tu 0.1. The grouping-agnostic
  differ + preserved object order carried the split as designed.

## Round 3: image + boot (03:10-03:30)

- build-image.sh: kernel 15.3MB + root.img reused; **boot-ssh-test.sh:
  BOOT-SSH OK after 3s: FreeBSD 15.1-RELEASE** — the split tree's kernel
  boots (PVH direct ELF) and accepts SSH with the same boot args as the
  committed layer (sourced project.env; first attempt without it printed
  "nothing to boot").
- Remaining gates: hermetic (clean container, running), then the 7
  genrules (genrules_per_tu 0.1) if time allows.

## Round 4: hermetic (03:30)

- **HERMETIC OK: //bazel/image:image builds in a clean container.** All
  four gates green on the split tree: PARITY converged (errors=0,
  warnings=132, artifacts converged), IDIOM 0.8, HERMETIC OK, BOOT-SSH
  OK. Definition of done met — verdict will be publish: release.

## Round 5: closing (03:35)

- Formatting pass on the generated BUILD files (one src per line, no
  stray indent line) — rebuild fully cached (1,391 action cache hits,
  argv unchanged); parity re-run: same GREEN/converged/132/0.8.
- The remaining 32 un-packaged compiled-source dirs are host-tool
  implementation dirs (makefs/ffs, libc/string, one-true-awk, ...) —
  sources of one tool each, not tree layout. Splitting them buys ~0.7
  for a second round of hand re-spelling; not taken. 7 genrules (0.1)
  stay (force-dynamic-hack + image glue).
- Report finalized with verdict publish: release. All four gates green;
  definition of done met. Tree change set is exactly 135 new package
  BUILD files + 6 rewritten BUILD files + the one-line makeobjops
  basename fix. No tool (any2bazel) changes this run.
