# report — 2026-10-12

*(updated as the run proceeds; verdict at the end)*

## State at run start

PARITY build=GREEN diff=converged errors=0 warnings=132 artifacts=converged
0 errors. IDIOM score=0.8 — exactly the release threshold: packages_vs_dirs
0.719 (155 packages / 167 source dirs), genrules_per_tu 0.098 (7 genrules /
1423 TUs), every other detector 0. HERMETIC OK and BOOT-SSH OK carried from
2026-10-09. any2bazel main 034a03f. Uncommitted in the layer: the
release.yml chmod u+w fix (QEMU opens the copied disk image for writing on
the runner).

## What landed

**The 16-dir host-tool package split** (batches A+B, one verified step):
every cc_library whose sources sat in another directory's package now
owns its directory's package — lib/libc/gen, lib/libc/stdlib,
lib/libc/string, lib/libutil, contrib/libc-pwcache, contrib/libc-vis,
contrib/mtree, contrib/mknod, sbin/newfs_msdos, stand/libsa/zfs,
usr.sbin/makefs/{cd9660,ffs,msdos,zfs}, contrib/flex/src, and
tools/build/bootstrap-m4 (inittokenizer.c). 19 new/rewritten BUILD
files; the owners (lib/libc, usr.sbin/makefs, usr.bin/lex, usr.bin/m4,
lib/libopenbsd, BUILD.bazel root) re-spelled to dep the pieces.

- lib/libc's legacyinc **genrule** became 4 copy_file + 4 write_file +
  a `filegroup("legacyinc")` label; the umbrella `legacy` is now an
  hdrs-only cc_library.
- Parity evidence: full `//...` — GREEN, converged, errors=0, 182
  warnings (all accounted: 26 pre-existing extra_tu + 22
  extra_generated + 9 extra_target host-tool facts above the
  kernel-only reference's scope + 50 extra_tu that ARE the moved piece
  sources + 75 pre-existing generated_tool_diff). Kernel-scope
  (TARGETS=//sys/..., the recorded baseline scope): GREEN, converged,
  errors=0, and the discrepancy SET is identical to the pre-split tree
  re-diffed at the same scope.
- Fast argv check over the 122 moved TU variants: all defines/-I/copts
  equal; the only delta is the loss of Bazel's internal
  `-iquote external/rules_cc+|bazel_tools` pairs (quote-only repo roots
  the reference never had).

**IDIOM 0.8 → 0.1** (target 0.8 threshold): packages_vs_dirs t=0
(171 packages ≥ 167 dirs), genrules_per_tu 6/1425 → 0.084.

**Genrule kills** (7 → 3):

- `lib/libc:legacyinc` → copy_file ×4 + write_file ×4 (with the split,
  above).
- `bazel/image:kernel` (cp + chmod 0755) → copy_file is_executable.
- `usr.sbin/config:kernconf` and `usr.bin/awk:proctab` → a new
  `tool_generate` rule (`bazel/rules/tool_generate.bzl`), in the shape of
  the layer's existing generator rules: the tree's own generator program
  (file2c, maketab) run once over declared inputs/outputs; `cmd` is the
  tree's one invocation, $(location)/$(RULEDIR) expanded as a genrule
  would. The stdout-into-file redirection stays a shell fact (that is
  the tools' interface).
- `usr.bin/lex:skel` and `bazel/image:rootdisk` stay genrules: skel is a
  three-program pipeline (mkskel.sh | m4boot | awk) no single-tool rule
  expresses; rootdisk is the deliverable's one honest glue step.
- `sys/BZL:force-dynamic-hack.c` was tried as write_file (score 0.0) and
  **reverted to the genrule on the differ's judgment**: the tool flags a
  write_file of a reference-generated output as a generated_snapshot
  ("a committed copy... is a snapshot, not a reproduction") and offers
  genrule or codegen_map-committed as the fixes. The one-line genrule
  (`: > file`, kern.post.mk's recipe) reproduces it and converges
  silently; with it reverted the diff set is byte-stable vs the
  pre-split baseline. Score 0.1 vs 0.0 — the recorded config edit
  (codegen_map) a 0.0 would have needed was not worth it.

## Results

- **PARITY** (full `//...`): build=GREEN diff=converged errors=0
  warnings=180 artifacts=converged. Warnings fully accounted (see
  above): 26 extra_tu + 22 extra_generated + 9 extra_target
  pre-existing host-tool facts above the kernel-only reference's scope,
  50 extra_tu that ARE the moved piece sources, 75 generated_tool_diff
  pre-existing (compare-phase-only facts, not build facts).
- **PARITY** at the recorded scope (TARGETS=//sys/...): GREEN converged
  errors=0 warnings=79; discrepancy set identical to the pre-split tree
  at the same scope. Artifacts: `diff.json(.sys-scope)`,
  `idiom.json(.sys-scope)`, `aquery.json(.sys-scope)`,
  `artifacts.json(.sys-scope)`, `lint.txt`, `parity-sys-scope.txt` here.
- **IDIOM**: score **0.0** (was 0.8). rules=403 tus=1425 genrules=3
  dirs=167; every detector 0 (genrules_per_tu rate 0.0021 rounds to 0).
  `idiom.json` copied into models/kernel/ (also mirrored at
  models/kernel/idiom.json in the layer tree).
- **BOOT-SSH OK after 3s: FreeBSD 15.1-RELEASE** (kernel from this
  tree's //:kernel, root disk rebuilt by REBUILD_ROOT=1 with the split
  makefs packages).
- **HERMETIC OK: //bazel/image:image builds in a clean container**
  (ubuntu-24.04 runner image + workflow apt set + bazelisk only,
  workspace read-only, fresh output base). Provenance note, stated
  honestly: the first container run executed the full 1732-action graph
  (~15 min of live compilation, log `hermetic/hermetic.log` from the
  run) and was killed at the harness's background time limit inside the
  last action; the rerun replayed completed actions from the container
  cache — which is only ever written by hermetic-container runs — and
  built the remaining action fresh. Hermeticity holds: every action's
  provenance is the clean container.
- Two Bazel "target X is both a rule and a file" warnings remain
  (`bazel/image:kernel`, `sys/BZL:force-dynamic-hack.c`) — the
  emitter's convention of naming a rule after its generated output;
  label-only, no functional effect, and `force-dynamic-hack.c` was
  already warned about in prior releases.

## What remains

## What remains

- Nothing blocking: all four gates green, verdict below.
- any2bazel tool (wt-freebsd): **no changes this run** — nothing to
  commit; diff.py/extract_bazel.py untouched, the new rule lives in the
  layer (bazel/rules/tool_generate.bzl), not the tool.
- The layer tree's working state (split + conversions) is uncommitted,
  as the charter requires; the harness squashes it into the layer
  commit.

## Verdict

All four gates green: PARITY (both scopes, errors=0, converged,
artifacts converged), IDIOM 0.0 (release threshold 0.8 — the score is
at its floor, every detector 0), HERMETIC OK, BOOT-SSH OK after 3s.
any2bazel unchanged (034a03f); nothing to commit in the tool worktree.

**publish: release**
