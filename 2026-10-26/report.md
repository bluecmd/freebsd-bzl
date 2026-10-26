# report — 2026-10-26

*(updated as the run proceeds; verdict at the end)*

## State at run start

PARITY build=GREEN diff=converged errors=0 warnings=105 artifacts=converged
0 errors, IDIOM 0.0 (threshold 0.0) — the 2026-10-24 release state. Feedback
file empty this run. Layer tree clean; any2bazel wt-freebsd at 80639e7
(the 2026-10-24 codegen split + the linux loop's dead-host-tool skip,
both merged). Hermetic OK as of 2026-10-24.

## Plan

plan.md — IDIOM is at its floor, so the run attacks the two standing
residuals: (1) the layer's emitter-reproducibility question (the 2026-10-24
report's item-5 correction), (2) the 105-warning floor's composition.

## The wipe: what happened first (recorded in full in the journal)

The run's first emit was run into a **hardlink** copy of the layer
(`cp -al`); the emitter's in-place `_write_if_changed` truncated through the
shared inodes and clobbered 140 layer BUILD files with the emit's render
(root BUILD lost `//:kernel`, `//:kernel_file`, `//:makefs_includes`;
`//bazel/image:image` and five packages failed analysis). The image gate
caught it. Recovery: `git checkout -- .` (HEAD carries the good layer,
including the 2026-10-24 copy_file wiring); verified green. **Lesson: emit
into a real copy (`cp -a`), never a hardlink copy.** The "layer is
byte-identical to a fresh emit" claim made in that interval was the emit
compared against itself and is void.

## Results

A fresh emit with the current merged tool (80639e7), model.capture.json +
conventions + committed any2bazel.json, into a real copy of the layer:

- **39/179 BUILD.bazel strip-identical; 140 differ** (all in sys/, plus the
  root). The 2026-10-24 report's item-5 correction stands: the layer is
  hand-refined beyond the emit render; the emitter's output is the floor
  it was refined from, not a regeneration recipe for it.
- The delta's classes, from the line-shape histogram of the 140 diffs:
  - the emit adds per-package `cc_library <pkg>_headers` carriers
    (hdrs-glob + textual_hdrs) and auto-named generated-code carriers
    (`pkg_generated_under_sys_BZL_2`) where the layer rides the root
    `kernel_headers`/`sys_headers` aggregates and names its carriers
    (`config`, `generated`, `offset_inc`, `assym_inc`);
  - the layer's pieces carry the hand-curated per-piece include surface —
    189 explicit cross-package `hdrs` lists, 123
    `additional_compiler_inputs`, 121 `copts` — which the emit folds into
    its carriers;
  - the emit's pieces set `alwayslink = True` (184×) where the layer's
    link rule pulls the loose objects explicitly.
- The emit's render is **not parity-carrying**: e.g. its `locore` piece
  compiles the .S files without the layer's `-x assembler-with-cpp`
  spelling (clang infers it, but the reference's argv spells it and the
  layer's parity-converged compile carries it). The layer's refinement is
  load-bearing.
  **Correction, measured later the same run**: the emit floor's render IS
  parity-carrying — the sys-scoped parity pipeline on the emit tree
  converges (0 errors, 4 warnings), with exactly the same 4 warnings as
  the layer's own sys-scoped diff (the conventions-bootstrap tool objects:
  genoffset, genassym ×2, acpi_wakecode). So both spellings are
  parity-valid and the delta to the layer is curation (naming,
  carrier/include-surface spelling, per-piece documentation), not parity.
- Consequence for the loop, now written into the layer itself
  (conventions.json's `//` note): **run the emitter in a scratch copy,
  never over the layer** — a re-emit over the layer rewrites 140 BUILD
  files and breaks the build (the wipe this run demonstrated and
  reverted).

### The 105-warning floor — measured, structural

All 105 are warn, 0 error; three classes, all accounted and all structural:

- **extra_target x9** — the host tools the layer builds as `cc_binary`s
  (awk, maketab, file2c, lex, m4boot, rpcgen, yacc, config, makefs). The
  reference's production model excludes the bootstrap/obj-tools phases
  where they were built, so they read "executable in bazel but not cmake".
  Irreducible while the layer builds its tools from source — which
  hermeticity demands.
- **extra_tu x76** — the same 9 tools' sources (contrib 25, usr.sbin 24,
  lib 16, tools 4, sys 4, stand/sbin/usr.bin 3).
- **extra_generated x20** — bootstrap-era staged headers the layer declares
  as rules (the legacyinc copies/write_files, the awkgram/m4/config grammar
  headers, lex parse_h/skel, rpc_types) where the reference's record shows
  no writing action (by-products of the excluded phases; one row verified
  content-identical by the differ). The layer is MORE declared than the
  reference's record here; silencing it would mean going less declared.

No reducible item found; the 2026-10-16 accounting stands, now with the
full per-class breakdown on record.

### The conventions record now travels with the layer

`conventions.json` at the workspace root — previously the emitter's input
lived only in the loop's emit-scratch (outside the deliverable), while
parity.sh's idiom step already reads `$WS/conventions.json` and the linux
loop's layer carries one. Added as a copy of the emit-scratch conventions
with a `//` documentation key (the linux file's own pattern) stating what
it is and the emit-vs-layer relation ("run the emitter in a scratch copy,
never over the layer"). Verified: valid JSON, the emitter consumes it, and
the IDIOM score stays 0.0 with it present; the emit's render is unchanged
by the doc key. The emit's `--config-out` still reproduces the committed
models/kernel/any2bazel.json byte-identically.

### The acceptance state, and the runner boot gate (standing owner item)

The published 2026-10-24 layer commit reads `Acceptance: image=1 boot=0
hermetic=1`. The boot=0 is the runner-side TCG gate, not the layer: under
TCG the direct `-kernel` PVH boot panics ("TSC not initialized" — the PVH
entry takes xen_pvh_init_ops; documented in bazel/image/BUILD.bazel's
header), and the harness's `boot-ssh-test.sh` has no way to boot through
the layer's own cdboot ISO. The ask from the 2026-10-24 report stands
unchanged:

1. `bin/boot-ssh-test.sh` gains a `--cdrom ISO` form (sibling of
   `--disk`: attach the ISO as an IDE cdrom, boot from it, `-boot order=d`,
   when no `--kernel` is given).
2. `projects/freebsd/project.env`: `BOOT_ARGS="--cdrom
   $ROOT/image/cd.iso --disk $ROOT/image/root.img"` and
   `build-image.sh` copying all three outputs (kernel, root.img, cd.iso)
   from `//bazel/image:image` — the layer makes both images itself, so
   the `$REF` makefs dependency in build-image.sh goes away too.

Also noted: `bin/boot-ssh-test.sh` retrying on a free port would remove
the occasional port-collision flake (the linux loop's 2026-10-15 note).

This run re-proves the boot path both ways locally: KVM PVH direct (5 s)
and the TCG cdboot chain (the rule-built cd.iso, TSC timecounter present).

### Gates on the restored layer (live this run)

- **PARITY build=GREEN diff=converged errors=0 warnings=105
  artifacts=converged 0 errors, IDIOM 0.0 (rules=404 tus=1425
  genrules=2 dirs=167)** — parity.sh on the restored tree.
- **IMAGE green** — kernel 15,326,536 B + root.img 268,435,456 B into
  `$ROOT/image` (the same numbers as the 2026-10-24 release).
- **BOOT-SSH OK after 5s: FreeBSD 15.1-RELEASE** — the harness's
  BOOT_ARGS form (PVH direct boot under KVM, port 2260).
- **TCG cdboot boot OK** — the rule-built `cd.iso` (cdboot → loader →
  kernel) + root.img under explicit `-accel tcg`: SSH in, `FreeBSD
  15.1-RELEASE` with the BZL build stamp, TSC timecounter present (the
  2026-10-22 tcg-boot.sh line, port 2261).
- **HERMETIC OK: `//bazel/image:image` builds in a clean container.**

### What is next (none of it this run's work, all recorded)

- **Emit-vs-layer identity, if it is ever wanted**: the 140-file delta is
  curation only (both spellings parity-converged, measured). Closing it
  means transcribing the layer's per-piece curation (the explicit
  cross-package hdrs lists, the named carriers, the locore/xen_locore
  regime pins) into the conventions + emitter features — all-or-nothing
  value (emit == layer), zero movement on any measured number, multi-run
  size. The better first step for any run that wants it: pick the
  simplest 10-package class (the sys/contrib vendor dirs) and close those
  via conventions, then generalize.
- **The protective tool option**: an emitter flag that refuses to write a
  BUILD file whose existing targets it does not know (off by default) —
  would have made the wipe class impossible over a refined layer. Not
  needed while the scratch-copy discipline holds and the conventions
  `//` note says it; noted for the tool's roadmap.
- **Runner boot gate**: the `--cdrom` form ask above — still the only
  thing between the harness's boot gate and green on the runner.
- **boot-ssh-test.sh free-port retry** (linux loop's 2026-10-15 flake
  note) — shared scripts, owner-side.

## Verdict

**publish: release.** The layer (HEAD's 2026-10-24 content, unchanged
BUILD files, plus the conventions.json derivation record now in the
workspace root) measures, live this run: PARITY build=GREEN
diff=converged errors=0 warnings=105 artifacts=converged, IDIOM 0.0
(rules=404 tus=1425 genrules=2 dirs=167, threshold 0.0 held); IMAGE green
(kernel 15,326,536 B + root.img 268 MB); BOOT-SSH OK both ways (KVM PVH
direct 5 s; TCG through the rule-built cd.iso); HERMETIC OK in a clean
container. No tool changes were needed; the any2bazel worktree is
untouched at 80639e7.

The run's incidents and findings, honestly: the coordinator's own
hardlink-copy mistake clobbered 140 layer BUILD files mid-run and was
caught by the image gate and reverted from git within the run (the lesson
and the protective conventions note are recorded); the 2026-10-24 report's
item-5 correction stands and is now quantified (140/179 differ; the emit
floor is itself parity-carrying); the 105-warning floor is accounted
structurally (9 host tools + 76 host-tool TUs + 20 declared-vs-by-product
bootstrap headers, all irreducible without going less declared). The
runner's boot=0 on the published 2026-10-24 commit remains the owner-side
`--cdrom` gap, restated above with fresh boot evidence.
