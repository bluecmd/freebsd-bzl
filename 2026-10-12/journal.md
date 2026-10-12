# journal — 2026-10-12

## Round 0: state, plan (00:20-00:45)

- Parity-before GREEN (converged, errors=0, warnings=132, artifacts
  converged), IDIOM 0.8 = release threshold. Anatomy from
  models/kernel/idiom.json: packages_vs_dirs t=0.0719 (155 pkgs / 167
  dirs; 16 tree dirs un-packaged) + genrules_per_tu t=0.0098 (7
  genrules / 1423 TUs); every other detector 0.
- 16 un-packaged dirs (aquery dir analysis): lib/libc/gen, lib/libc/stdlib,
  lib/libc/string, lib/libutil, contrib/libc-pwcache, contrib/libc-vis,
  contrib/mtree, contrib/mknod, sbin/newfs_msdos, stand/libsa/zfs,
  usr.sbin/makefs/{cd9660,ffs,msdos,zfs}, contrib/flex/src,
  tools/build/bootstrap-m4, usr.bin/m4 (inittokenizer.c),
  usr.sbin/makefs (root already packaged — its TUs ride the umbrella).
- Plan written to plan.md; report stubbed. 7 genrules: libc:legacyinc,
  lex:skel, awk:proctab, config:kernconf, sys/BZL:force-dynamic-hack.c,
  bazel/image:kernel, bazel/image:rootdisk.

## Round 1: the 16-dir split (00:45-00:55)

- lib/libc:legacyinc genrule → 4 copy_file (namespace.h, libc_private.h,
  un-namespace.h from tree sources; getopt.h from include/, sys/queue.h
  from sys/sys/) + 4 write_file stubs (libsys.h, sys/_types.h,
  sys/_pthreadtypes.h, sys/_sigset.h) + `filegroup("legacyinc")` over the
  9 outputs; the umbrella `legacy` became hdrs-only cc_library with
  includes=["legacyinc"]; 6 piece packages (pwcache, vis, libc gen/stdlib/
  string, libutil) take `//lib/libc:legacyinc` in srcs and spell
  -Ilib/libc/legacyinc + -I$(GENDIR)/lib/libc/legacyinc in copts.
- makefs subtree: 8 piece packages (cd9660, ffs, msdos, zfs, newfs_msdos
  mkfs_msdos, libsa/zfs nvlist, contrib/mtree, contrib/mknod) + a
  hdrs-only `headers` carrier in usr.sbin/makefs supplying -I. and -Izfs
  to the backends in the same order the umbrella used to.
- contrib/flex/src: piece cc_library `flex` (18 TUs), the generated
  surface (config.h, parse.h, skel.c) reached by label/-I copts.
- tools/build/bootstrap-m4: piece `m4boot` (inittokenizer.c + the
  usr.bin/m4 parser src), //usr.bin/m4:m4boot keeps its own rule and now
  deps the piece.
- fallout fixed iteratively (bazel build //... GREEN after 4 passes):
  subpackage-boundary label errors (contrib/flex BUILD deleted,
  exports_files re-homed in src/), yacc_generate's CcInfo requirement
  (m4_parser into srcs, not deps), undeclared staged headers (sandbox:
  every reached header must be declared — legacyinc filegroup into each
  piece's srcs, buf.h / mkfs_msdos.h / nvlist.h / pack_dev.h / config.h /
  parse_h cross-package hdrs), libopenbsd's src label re-spelled.
- Fast argv equivalence (pre aquery at models/kernel/aquery.json vs
  scoped post aquery), keyed by (source path, pic/obj variant) over the
  122 moved TU variants: 98 differ, every difference exactly the loss of
  Bazel's `-iquote external/rules_cc+ -iquote external/bazel_tools`
  (and their bare tokens) that hung off the OLD owning targets — bazel
  internal repo roots, quote-only, never present in the reference; all
  defines/-I/copts equal. 24 variants matched byte-for-byte.

## Round 2: parity (01:00-01:30)

- Full `//...` parity: PARITY build=GREEN diff=converged errors=0
  warnings=182 artifacts=converged. IDIOM score=0.1 (was 0.8):
  packages_vs_dirs t=0 (171 packages ≥ 167 dirs), genrules_per_tu 6/1425
  → 0.084 → 0.1 rounded.
- Warning delta investigated, not assumed: diff.py + extract_bazel.py
  unchanged since 2026-10-03/05 (git), model.capture.json unchanged
  (2026-10-04, kernel-only scope: 3 targets — <unlinked>,
  force-dynamic-hack, kernel.full). At full //... scope the pre-split
  tree (worktree at a08a0c124) ALSO shows 26 extra_tu + 22
  extra_generated + 9 extra_target — host-tool facts above the kernel
  reference's scope that the recorded runs never printed because
  parity.sh's triage output is `| head -30`-capped.
- Split delta at full scope is exactly +50 extra_tu = the 49-50 moved
  piece sources (executables' TUs are exempted via host_tool pairing;
  the pieces are now cc_libraries, so they enter the library TU union).
  No sources lost, none newly compiled; +2 TU count = variant
  duplication, sources identical.
- Recorded-baseline comparison at the recorded scope (TARGETS=//sys/...):
  PARITY GREEN converged errors=0 warnings=79 — and the discrepancy SET
  is identical to the pre-split tree re-diffed at the same scope
  (75 generated_tool_diff pre-existing + 4 extra_tu pre-existing:
  acpi_wakecode.S, genassym.c, ia32_genassym.c, genoffset.c). The
  2026-10-09 recorded files (warnings=132) are not reproducible byte
  counts — parity-after.txt is head-30-truncated (15505 bytes, cut
  mid-list at virtio_if) — so set-equality against a re-diff of the
  pre-split tree is the evidence used instead.
- Saved sys-scope artifacts to the run dir (aquery/diff/idiom
  *.sys-scope, parity-sys-scope.txt).

## Round 3: genrule kills, boot, hermetic (01:30-02:10)

- Genrules 7 → 3: legacyinc (with the split, copy_file+write_file),
  image:kernel → copy_file(is_executable), kernconf + proctab → new
  `tool_generate` rule (bazel/rules/tool_generate.bzl — the tree's
  generator program run once over declared inputs/outputs, ToolGenerate
  mnemonic deliberately NOT in aquery filter/codegen.mnemonics since the
  kernel-only reference never recorded host-tool codegen — nothing
  compared, nothing silently converged).
- force-dynamic-hack: tried as write_file (score 0.0) but the tool
  flagged generated_snapshot ("a committed copy... is a snapshot, not a
  reproduction"); reverted to the original one-line genrule, which
  converges silently and keeps the diff set byte-stable. 3 genrules
  remain: lex:skel (3-program pipeline), image:rootdisk (the
  deliverable's glue), force-dynamic-hack.c (differ's judgment).
- Full-scope parity re-run after the conversions: GREEN converged
  errors=0 warnings=180, IDIOM score=0.0 (rules=403 tus=1425 genrules=3
  dirs=167); sys-scope set still identical to pre-split. Artifacts
  copied into the run dir; models/kernel/ holds the final full-scope
  output.
- build-image.sh with REBUILD_ROOT=1 → kernel 15326536 B, root.img
  256 MiB.
- Boot test attempt 1 FAILED (mountroot> hang) — my invocation error:
  script's default --append lacks vfs.root.mountfrom and I passed a
  bogus key. Attempt 2 with `--append "vfs.root.mountfrom=ufs:/dev/vtbd0"`
  and keys/id_ed25519: **BOOT-SSH OK after 3s: FreeBSD 15.1-RELEASE**.
- Hermetic gate: first background launch killed at the background time
  limit mid-build (log truncated in //bazel/image:rootdisk, no error —
  wrapper+container killed together); relaunched with the 2h limit.
  Rerun: **HERMETIC OK**, exit 0 — 1731 action cache hits + the
  remaining action fresh; cache provenance is exclusively the hermetic
  container (its output base lives only under hermetic/cache), so the
  first run's real in-container execution of the full graph is the
  evidence. Two rule/file name-collision warnings noted
  (bazel/image:kernel — new, mirrors the emitter's output-named-rule
  convention; sys/BZL:force-dynamic-hack.c — pre-existing). Left as is:
  label-only, renaming would churn target labels for cosmetics.
- Verdict written: **publish: release** (all gates green, IDIOM 0.0).
- Cleanup: /tmp/fbsd-presplit worktree + /tmp aquery dumps removed.
  any2bazel wt-freebsd confirmed clean at 034a03f — no tool changes
  this run.

