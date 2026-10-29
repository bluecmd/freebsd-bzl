# plan — 2026-10-30

## Where we start

Every gate green at the 2026-10-28 release state, re-measured by the
harness before this run: PARITY build=GREEN diff=converged errors=0
warnings=105 artifacts=converged, IDIOM 0.0 (threshold 0.0, the floor),
HERMETIC OK, boot proven both ways. Feedback file empty. Layer tree
clean. Tool worktree at 7064ad6 = the merge that carries the linux
loop's two generic fixes.

So the idiom attack has no work: the score cannot go below 0. This run
is verification + honesty, ordered by risk:

## The work

1. **Verify the merged tool still reproduces the layer.** The linux
   run (2026-10-29) found its merged tool rendered freebsd 179/179
   identical to the pre-merge tool, but the LAYER differs from the
   fresh render on exactly 4 files: root BUILD.bazel +
   sys/{amd64,i386,x86}/include/BUILD.bazel. I checked conventions.json
   locally: keep_files is exactly those 4 — so the delta is by design,
   not drift. Still, the claim is only as good as my own check:
   fresh real copy of the layer, emit with 7064ad6, cmp all BUILD
   files, require "only the 4 keep_files differ, 0 TODOs".
   Done = confirmed or root-caused otherwise.

2. **Make the emitted-vs-hand story honest.** The conventions header
   (per the 2026-10-28 report) claims "the delivered sys BUILD files
   are the emitter's render; only the workspace root is hand-curated".
   But keep_files carries 3 include-package BUILD files too. Read the
   actual diffs (layer vs render) for those 3: if the delta is pure
   style (multiline globs, load spelling, comments) that a conventions
   style fact could carry, converge them — 3 fewer hand-converged
   files, the layer one step closer to fully emitter-reproduced. If
   they carry content the emitter cannot express, keep them keep_files
   and fix the header's claim to name all four.

3. **Re-prove the gates on whatever the layer ends up carrying**
   (likely only conventions.json text, which Bazel never reads):
   parity (should be byte-identical to parity-before.txt), image,
   boot-ssh (KVM PVH direct; TCG through the rule-built cd.iso if
   budget allows), hermetic only if any Bazel-read input changed.
   Done = parity byte-identical to the release numbers, boot OK,
   honest header.

4. **Tool**: commit any generic fix with suites green + corpus
   invariants (expected: none; the linux run already proved the merged
   tool renders freebsd identically to the pre-merge tool).

## What "done" is

- Emit check: only keep_files differ, 0 TODOs (or fixed).
- PARITY/IDIOM byte-identical to parity-before.txt.
- IMAGE green, BOOT-SSH OK.
- Conventions header states the real hand-curated surface.
- report.md ends with a verdict line.
