# journal — 2026-10-30

## 00:10 — setup + the 4-file question

Start state: every gate green at the 2026-10-28 release numbers
(parity-before.txt re-measured by the harness: build=GREEN, converged,
0 errors, warnings=105, IDIOM 0.0). Feedback empty. Tool worktree at
7064ad6 = merge carrying the linux loop's two generic fixes
(claimed-readers skip 046b2ca, style.file_target_bare 19e1626).

The linux 2026-10-29 report left one freebsd thread: its merged+fixed
tool rendered freebsd identically to the pre-merge tool, but the LAYER
differed from the fresh render on 4 BUILD files (root +
sys/{amd64,i386,x86}/include) — described as "hand-converged text
neither tool reproduces", contradicting the 2026-10-28 claim that only
the keep_files root diverges.

Facts established this run:

- conventions.json keep_files = exactly those 4 files. The delta is by
  design, not drift — the 2026-10-28 report's "only the root" claim
  simply understated its own keep_files list.
- My own emit (fresh real copy fb30, merged tool 7064ad6, layer's
  conventions): "conventions keep_files leaves BUILD.bazel untouched",
  0 TODOs; census 179/179 BUILD files identical to the layer. The
  linux run's "the emit rewrote the 4 files" does not reproduce —
  keep_files is honored.
- keep_files-limited emit (fb30b, keep_files = root only) renders the
  3 include dirs; diff vs layer is PURE STYLE: load spelling
  (`@rules_cc//cc:defs.bzl` render vs the layer's
  `@rules_cc//cc:cc_library.bzl` — the layer was internally
  inconsistent), multiline-vs-inline globs, hand comments, filegroup
  order. Rule sets, names, attrs, globs identical.

## 00:20 — the include trees converge into the render

Decision: install the 3 include renders into the layer, drop them from
keep_files (root stays), amend the header claim. Layer deltas: 3
BUILD.bazel files (semantically identical render text, unified load
spelling), conventions.json (keep_files narrowed; header states the
render now covers the include trees and honestly names the hand-kept
host-tool/infra files it does not write).

Proof (fb31 + sentinel test fb32):
- fb31 (fresh copy of the updated layer, emit): 179/179 identical,
  0 TODOs.
- Sentinel test: marker appended to the 3 include BUILD files, re-emit
  → all 3 rewritten to the render byte-for-byte. The emit WRITES them;
  the reproduction is real, not an untouched-copy coincidence.
- So the layer's hand-converged surface = the workspace root only,
  exactly as keep_files says.

## Gates

*(in progress)*

- Emitted config: /tmp/fb31.json == models/kernel/any2bazel.json
  byte-for-byte (and /tmp/fb31.json == /tmp/fb30.json — the config is
  reproducible and matches the delivered layer).
- PARITY re-run with full output captured (first run's PARITY/IDIOM
  lines were lost to a `tail -5`; diff.json reads converged, 0 errors,
  105 warnings — the same accounted floor).
- **PARITY/IDIOM byte-identical to parity-before.txt**: build=GREEN
  diff=converged errors=0 warnings=105 artifacts=converged, IDIOM 0.0
  (rules=404 tus=1425 genrules=2 dirs=167). The include-tree
  convergence is parity- and idiom-neutral, as it should be (same
  rules, different formatting only).
- IMAGE: kernel **15,328,296 B = the release number exactly**, root.img
  reused (268,435,456); //:kernel built green. cd.iso staged fresh from
  //bazel/image:image: 16,695,296 B (the release size).
- **BOOT-SSH OK after 4s: FreeBSD 15.1-RELEASE** (KVM PVH direct,
  port 2260) — identical to the release proof.
- **TCG-CDBOOT OK after 9s: FreeBSD 15.1-RELEASE**, TSC timecounter
  present (`TSC(-100) i8254(0) ACPI-fast(900) HPET(950)`) — identical
  to the release proof (the shared script still has no --cdrom form;
  the test rode a run-local helper, runs/2026-10-30/tcg-cdboot.sh,
  mirroring boot-ssh-test.sh's qemu/ssh shape — the standing ask
  unchanged).
- **HERMETIC OK** (fresh this run; the 3 include BUILD files are
  Bazel-read inputs and changed bytes, so the gate was re-proven rather
  than argued).

## Tool

One generic commit, 545fc67: the common-stem naming heuristic's
`os.path.commonprefix()` replaced with the equivalent min/max character
scan (silences the DeprecationWarning every emit of every project
printed; the semantics — a character prefix, validated by startswith —
are unchanged). All suites green; re-emit with the patched tool:
179/179 BUILD files byte-identical, any2bazel.json identical, 0
DeprecationWarnings. check-invariants.sh CORPUS=1: INVARIANTS OK,
corpus 37 converged before, 37 after.

## Scratch

fb30–fb33 removed after the gates; 115G free.
