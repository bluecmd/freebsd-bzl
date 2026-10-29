# report — 2026-10-30

*(updated as the run proceeds; verdict at the end)*

## State at run start

PARITY build=GREEN diff=converged errors=0 warnings=105 artifacts=converged,
IDIOM 0.0 (threshold 0.0) — the 2026-10-28 release state, re-measured by
the harness (parity-before.txt). HERMETIC OK (2026-10-28). Boot proven
both ways on the delivered tree (2026-10-28). Feedback file empty; layer
tree clean; tool worktree 7064ad6 (merge carrying the linux loop's two
generic fixes). plan.md — no idiom work exists below 0; this run is
verification + honesty: emitter-reproduction of the layer under the
merged tool, the keep_files story, then gate re-proofs.

## Journal

journal.md in this directory.

## Results

**The 4-file question from the linux run is resolved: it was keep_files,
not drift — and three of the four files now converge into the render.**

- The linux 2026-10-29 report found its merged tool rendered freebsd
  identically to the pre-merge tool but the LAYER differed from the
  fresh render on 4 BUILD files (root + sys/{amd64,i386,x86}/include),
  described as "hand-converged text neither tool reproduces" —
  contradicting the 2026-10-28 claim that only the root diverges.
- Checked here: conventions.json `keep_files` is exactly those 4 files,
  and a fresh emit with the merged tool (fb30) honors them — "leaves
  BUILD.bazel untouched", 179/179 BUILD files identical to the layer,
  0 TODOs. The linux run's "the emit rewrote the 4 files" does not
  reproduce; no regression from the merge or its fixes.
- A keep_files-limited emit (fb30b) rendered the 3 include dirs: the
  delta vs the layer is PURE STYLE — load spelling
  (`@rules_cc//cc:defs.bzl` render vs the layer's
  `@rules_cc//cc:cc_library.bzl`; the layer was internally
  inconsistent with its own sys tree), multiline-vs-inline globs, hand
  comments, filegroup order. Rule sets, names, attrs, globs identical.
- **The 3 include trees are now part of the render.** The layer carries
  their render text (semantically identical, unified load spelling);
  conventions.json keep_files narrowed to the root alone. Proof: fresh
  emit (fb31) 179/179 identical, 0 TODOs; sentinel test (fb32) —
  markers appended to the 3 files were rewritten to the render
  byte-for-byte, so the emit really writes them and the reproduction
  is not an untouched-copy coincidence. The layer's hand-converged
  surface is now exactly the workspace root, which is what keep_files
  says and what the header claims (amended: it also honestly names the
  host-tool/infra BUILD files outside the render set).
- No tool fix was needed for this; the emitter already reproduced the
  layer everywhere it writes.

**Tool**: one generic commit, 545fc67 — the common-stem naming
heuristic's deprecated `os.path.commonprefix()` replaced with the
equivalent min/max character scan (silences the DeprecationWarning
every emit of every project printed). All suites green; re-emit
byte-identical (179/179, config identical); check-invariants.sh
CORPUS=1: INVARIANTS OK, corpus 37 converged before, 37 after.

**Gates on the delivered tree** (all fresh this run):

- **PARITY build=GREEN diff=converged errors=0 warnings=105
  artifacts=converged 0 errors, IDIOM 0.0 (rules=404 tus=1425
  genrules=2 dirs=167)** — byte-identical to parity-before.txt; the
  include-tree convergence is parity- and idiom-neutral.
- IMAGE: kernel **15,328,296 B = the release number exactly**, root.img
  268,435,456, cd.iso 16,695,296 (release sizes).
- **BOOT-SSH OK after 4s: FreeBSD 15.1-RELEASE** (KVM PVH direct,
  port 2260).
- **TCG-CDBOOT OK after 9s: FreeBSD 15.1-RELEASE**, TSC timecounter
  present (TSC(-100) … HPET(950)) — the shared script still has no
  --cdrom form, so this rode a run-local helper
  (runs/2026-10-30/tcg-cdboot.sh) mirroring boot-ssh-test.sh's
  qemu/ssh shape.
- **HERMETIC OK**: `//bazel/image:image` builds in a clean container
  (re-proven, since the 3 include BUILD files are Bazel-read inputs
  that changed bytes).

## What is next

Nothing load-bearing. The layer is one hand-curated file (the workspace
root, by design the deliverable plumbing) away from fully
emitter-reproduced, parity is at the release numbers, and all gates are
fresh. Standing asks unchanged:

- **Runner boot gate (owner item, third restatement)**:
  `bin/boot-ssh-test.sh` needs a `--cdrom ISO` form (attach as IDE
  cdrom, `-boot order=d`, when no `--kernel` is given), project.env
  needs `BOOT_ARGS="--cdrom $ROOT/image/cd.iso --disk
  $ROOT/image/root.img"`, and `build-image.sh` should copy cd.iso too.
  This run's helper (`tcg-cdboot.sh` in the run dir) is a working
  reference for the qemu line. Plus the free-port retry ask (the linux
  loop's first boot failed on port 2222 again this week).
- A future reference-update re-run is a mechanical operation: fresh
  scratch copy, emit, prove (the sentinel test is the cheap proof the
  write actually happens), gates.

## Verdict

**publish: release.** The 2026-10-28 release state is re-proven gate by
gate on the delivered tree — PARITY build=GREEN diff=converged errors=0
warnings=105 artifacts=converged, IDIOM 0.0 (threshold 0.0 held),
IMAGE green at release bytes, BOOT-SSH OK both ways (KVM PVH 4s; TCG
cdboot 9s, TSC present), HERMETIC OK fresh. The layer's only content
change is the three machine/i386/x86 include trees converging into the
emitter's render (semantically identical, proven parity- and
artifact-neutral: same PARITY line, same kernel bytes) and the
conventions.json honesty fix; the tool carries one generic cleanup
(545fc67) with all suites green and the corpus sweep clean. ~15h of the
15.4h budget unused: the acceptance test passed and no remaining idea
moves a measured number.
