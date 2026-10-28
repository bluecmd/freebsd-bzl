# plan — 2026-10-28

State at start: PARITY build=GREEN diff=converged errors=0 warnings=105
artifacts=converged, IDIOM 0.0 (threshold 0.0), hermetic OK, boot OK (KVM
PVH + TCG cdboot). Feedback file empty. IDIOM is at its floor, parity is
converged, every gate green — so per the standing goal, this run attacks
the one recorded residual with real value: the **emit-vs-layer identity**
(2026-10-26: a fresh emit with the then-merged tool is 39/179
strip-identical, 140 differ — all sys/ + root; the delta is the layer's
hand-curation, and both spellings are parity-carrying).

## Why this run's target

Closing emit-vs-layer means the layer stops being hand-maintained: a fresh
emit from the model + conventions reproduces the deliverable byte-for-byte,
so (a) tool/render changes can be proven against the layer directly, (b) the
loop's emit step becomes the update path instead of a hazard (the 2026-10-26
hardlink wipe happened precisely because emit and layer had diverged), and
(c) the layer's 189 explicit hdrs lists / 123 additional_compiler_inputs /
121 copts become machine-checked facts instead of prose. The 2026-10-26
report's roadmap said: start with the simplest class (the sys/contrib vendor
dirs), close those via conventions, generalize.

## Order of attack

1. **Re-measure the delta with the current merged tool** (80639e7 line +
   ad852cf + c2a9c8d from the linux loop): fresh emit into a REAL copy
   (`cp -a`, never `cp -al` — the 2026-10-26 wipe lesson) of the layer in
   scratch; strip-diff against the layer; classify the delta again. The
   two linux-loop commits changed the emitter's render since the last
   measurement, so the numbers must be re-taken before any planning.
2. **Class-by-class closure.** For each delta class, in order of
   simplicity (contrib vendor dirs first):
   - express the layer's curation in conventions.json (facts the emitter
     can consume) or as generic emitter features when the shape is
     project-independent;
   - prove it: fresh emit, the class' packages strip-identical, all
     suites green, corpus unregressed (check-invariants.sh);
   - commit (tool) / record (conventions).
3. **When all classes are closed**: install the emit render over the layer
   (real copy discipline), re-run full parity.sh — the regression test —
   then build-image.sh, boot-ssh-test.sh (both ways if the cd.iso path is
   touched), and hermetic-build.sh only if the image target's inputs
   changed.

## What "done" is

- Best case: fresh emit == layer (179/179 strip-identical, root BUILD
  included), parity re-proven GREEN on the emitted tree, image + boot
  green, hermetic green → release with an emitter-reproducible layer.
- Acceptable: the classes closed so far are proven and committed; the
  remaining delta classes are quantified in the report; parity, image,
  boot stay green → release with the layer unchanged where not closed.
- Never: parity worse than converged, or a render that is more
  transcript-like than the layer's (IDIOM must stay at 0.0; the layer's
  curation is documentation, not recipe replay — the emitter's closure
  must preserve that).

## Non-goals (recorded, not this run unless cheap)

- The protective emitter flag (refuse to overwrite a BUILD whose existing
  targets the emit does not know) — tool roadmap; only if time remains,
  since it is small and would make the wipe class impossible.
- The runner boot gate (`boot-ssh-test.sh --cdrom` + project.env BOOT_ARGS)
  — shared scripts are report-only; restated in the report.
- The 105-warning floor — accounted structural (9 host tools + 76 TUs +
  20 bootstrap staged headers), already at its declared ceiling.

## Discipline carried from 2026-10-26

Emit only into a real copy (`cp -a --reflink=auto`), never a hardlink
copy, never over the layer directly. Every emitter change lands with all
suites green and the corpus unregressed before the next step.
