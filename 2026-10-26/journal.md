# journal — 2026-10-26

## The wipe: my own mistake, caught and reverted (00:05–00:45)

Planned main item was the emit-reproducibility question (the 2026-10-24
report's item-5 correction: 139/139 sys packages differ between the layer
and a fresh emit). To emit into a scratch tree I did `cp -al freebsd
emit26` — a HARDLINK copy — and ran the emitter into it. The emitter's
`_write_if_changed` opens the output path for writing in place, so every
BUILD file where the emit's render differs from the layer's content got
truncated **through the shared inode** — 140 layer BUILD files were
clobbered with the emit's render (root BUILD lost `//:kernel`/
`//:kernel_file`/`//:makefs_includes`; //bazel/image:image and five
packages referencing `//:makefs_includes` failed analysis).

Caught via the image gate: `build-image.sh` failed "target 'kernel' not
declared", and `bazel build //bazel/image:image` failed analysis on
`//:kernel` and `//:makefs_includes`. The identical nanosecond mtimes of
layer and emit26 files (one inode) were the tell. Lesson for every future
run: **emit into a real copy (`cp -a`), never a hardlink copy.**

Recovery: `git checkout -- .` (HEAD 20e8cf111 carries the good layer —
including the 2026-10-24 copy_file wiring, which IS in HEAD; the
run-start "layer tree clean" was true). Verified: `bazel build //:kernel
//bazel/image:image` green (1736 cached actions, 5 s).

## The reproducibility measurement — redone honestly

The "179/179 byte-identical" claim from the clobbered interval was the
emit compared against itself — void. What is true:

- The working tree at run start == HEAD (2026-10-24 layer, hand-refined,
  with the copy_file kernel wiring and makefs_includes). Parity GREEN,
  warnings 105, IDIOM 0.0 measured on it.
- The emit render differs from the layer in **140 BUILD files** (that is
  exactly what the clobber wrote). The 2026-10-24 item-5 correction
  STANDS: the layer is hand-refined beyond the emit; the emit is not a
  regeneration recipe for it.

(to be re-measured into a real copy for the per-class breakdown)

## The 105-warning floor — measured, structural (00:30)

Read diff.json's warning detail (all 105 are warn, 0 error):

- **extra_target x9**: awk, maketab, file2c, lex, m4boot, rpcgen, yacc,
  config, makefs — the host tools the layer builds as cc_binaries. The
  reference's record carries them under the bootstrap/obj-tools phases the
  production model excludes ("executable in bazel but not cmake").
  Irreducible while the layer builds its tools from source — which
  hermeticity demands.
- **extra_tu x76** by top dir: contrib 25 (flex 18, libc-vis,
  libc-pwcache...), lib 16, usr.sbin 24 (makefs/config), tools 4, sys 4,
  stand/sbin/usr.bin 3 — the same 9 tools' sources.
- **extra_generated x20**: bootstrap-era staged headers the layer declares
  as rules (legacyinc copies/write_files, awkgram/m4/config grammar
  headers, lex parse_h/skel, rpc_types) where the reference's record shows
  no writing action — by-products of phases the production model excludes
  (one row verified identical by the differ). The layer is MORE declared
  than the reference's record; going less declared to silence it would be
  a real regression.

Verdict: the floor is the layer's host-tools tail, structural, not worth
churn. Recorded in the report with these numbers.

## Also noted

- The published 2026-10-24 layer commit message reads
  `Acceptance: image=1 boot=0 hermetic=1` — boot=0 is the runner-side TCG
  gate, blocked on the owner's `boot-ssh-test.sh --cdrom` form
  (under TCG the PVH direct boot panics "TSC not initialized"; the
  cdboot ISO boots — documented in bazel/image/BUILD.bazel's header).
  The ask is restated in this run's report.
- The layer root has no conventions.json (parity.sh passes
  `$WS/conventions.json` to idiom.py, which tolerates its absence). The
  emitter's conventions live in emit-scratch, outside the layer. Decision
  pending at the end (linux's layer carries one; but here the conventions
  reproduce the EMIT, not the layer — a re-emit over the layer would wipe
  140 files and break it, as just demonstrated).
- genrules 2 stay: sys/BZL's is `force-dynamic-hack.c` (the empty-TU BFD
  dynamic-mode hack, the reference's recorded `: >` recipe); usr.bin/lex's
  is its skel/parse generation. Score-neutral shape churn at best; not
  taken.

## Gates re-measured on the restored layer (01:00)

- PARITY GREEN, IDIOM 0.0 (parity-after.txt, same numbers as run start).
- IMAGE green: kernel 15,326,536 B + root.img 268,435,456 B.
- BOOT-SSH OK after 5s: FreeBSD 15.1-RELEASE (KVM PVH, port 2260).
- TCG cdboot boot OK (tcg-boot.sh port 2261): FreeBSD 15.1-RELEASE BZL,
  TSC timecounter present.
- HERMETIC OK (clean-container image build).

## The emit-vs-layer delta, classified on honest data (01:20)

emit27 (real reflink copy, `cp -a --reflink=auto`, 18 s — never `cp -al`):
**39/179 strip-identical, 140 differ; all 140 in sys/ except the root.**
Line-shape histogram of the diffs:

- emit-only: 195 `cc_library(` carriers (the per-package
  `<pkg>_headers` + auto-named `pkg_generated_under_sys_BZL_N`),
  137 `hdrs = glob([` + 268 glob closes (textual_hdrs globs), 184
  `alwayslink = True`, 140 extra `load(`s (@rules_cc defs).
- layer-only: 189 explicit per-piece `hdrs = [` (cross-package lists —
  `//sys/BZL:assym_inc`, `offset_inc`, `config`, `generated`...), 123
  `additional_compiler_inputs`, 121 `copts`, 44/39 `cc_per_source_library(`
  pieces both sides render (the layer's rule IS the emit's rule — the
  split machinery is shared; the curation on top differs).

Argv probe (aquery, one piece): the emit's `sys/amd64/amd64:locore`
compile lacks the layer's `-x assembler-with-cpp` (and the layer's is the
parity-converged spelling; the reference argv spells it). So the emit
render is the floor, not a parity-carrying layer. The emit's `--config-out`
DOES reproduce models/kernel/any2bazel.json byte-identically, and its
sys/BZL render has the 36-piece codegen split (the machinery works).

Verdict: closing the gap = transcribing ~140 files of hand curation into
conventions + emitter features; all-or-nothing value (emit==layer), zero
movement on any measured number, multi-run size. Recorded as the roadmap,
not attempted. The protective change is already in place where it matters:
the conventions record lives in the layer with the warning.

## Sharpener: the emit floor itself converges in parity (01:50)

Scoping the parity pipeline to `//sys/...` on the emit27 tree (aquery with
the project's mnemonic set → extract_bazel → diff vs the capture): **converged,
0 errors, 4 warnings** — and the 4 are exactly the conventions-bootstrap
tool objects (genoffset, genassym ×2, acpi_wakecode), the same sys
`extra_tu x4` the layer's own diff carries. So the emit render is not just
buildable-and-bootable (2026-10-24's emit-wt2 proof) but **parity-carrying
on its own**: the layer's refinement above it is curation (naming,
carrier/include-surface spelling, docs), not parity necessity. Two
parity-valid spellings of the same build exist; the delivered one is the
hand-refined, documented, kernel-link-faithful one.

(apples-to-apples confirmed: the layer's sys-scoped diff is also
converged/0 errors with the SAME 4 warnings. Evidence moved into this
run's directory: aquery-emit27.json, aquery-layer-sys.json,
model-emit27.json, model-layer-sys.json, diff-emit27.json,
diff-layer-sys.json. emit27 deleted; scratch clean.)

## Closing (02:00)

Final tree = HEAD's BUILD files (byte-identical) + conventions.json at the
root (the only change). Final parity re-run on that tree: GREEN, converged,
0 errors, warnings 105, IDIOM 0.0. All four gates verified live this run:
parity, image, boot (KVM PVH 5 s; TCG cdboot), hermetic. No tool changes →
no invariants run needed. The run's substance: the wipe incident (caught
via the image gate, reverted from git, lesson recorded), the reproducibility
question settled with exact numbers (140/179; the emit floor is itself
parity-carrying — measured both ways), the 105 floor accounted structurally,
the conventions record added to the layer, the runner boot gate's owner ask
restated with fresh boot evidence both ways. Verdict: publish: release.

## Decisions logged

- conventions.json ADDED to the layer root (copy of the emit-scratch
  conventions + a `//` doc key, the linux file's pattern, saying what it
  is and that a re-emit does not reproduce the layer). Verified: the
  emitter consumes it, the render is unchanged, IDIOM stays 0.0.
- genrules 2 stay; the 105 floor stands; no tool changes (none needed —
  the layer has converged and the reproducibility close is conventions/
  emitter roadmap work for later runs).
- No hand edits to any BUILD file; the only layer change this run is the
  conventions.json record.

