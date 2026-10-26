# plan — 2026-10-26

## State at start

PARITY build=GREEN diff=converged errors=0 warnings=105 artifacts=converged;
IDIOM 0.0 (threshold 0.0), rules=404 tus=1425 genrules=2 dirs=167 — every
detector at 0 except benign rates. Feedback file empty. Layer tree clean at
release/15.1.0 + the 2026-10-24 layer; any2bazel wt-freebsd at 80639e7
(merge of kbuild-intree: the 2026-10-24 codegen split 7ff91e0 + the linux
loop's dead-host-tool skip / host_tool_checked 933efe3). Hermetic OK on the
2026-10-24 layer.

## The two standing axes (why this run is not empty)

IDIOM is at its floor, so the score gives no work list. What remains:

1. **The layer is not emitter-reproducible** — the 2026-10-24 report's
   correction: the fresh emit (current tool) renders sys/BZL as the
   codegen-aware split (36 pieces, link deps 183, each generated TU's
   object at its reference ld position), while the layer still carries the
   pre-split hand shape (vnode_if folded into `bzl`, the two rpcgen groups
   merged on `rpctls`, 187 deps). The emit build was proven green and
   boot-tested (3 s KVM) in a worktree — but never installed. A re-emit
   today would wipe the layer's hand merges silently. The goal statement
   ("mechanically emitted BUILD from the recorded evidence") is not yet
   literally true for sys/BZL.
2. **The warnings floor (105 = 76 extra_tu + 20 extra_generated +
   9 extra_target)** is "the only remaining axis" per the 2026-10-24
   verdict. Two possibly-reducible classes: the extra_generated rows whose
   files exist in-tree (legacyinc headers spelled as copy_file/write_file
   generation; the reference treats them as by-products), and any dead
   host tools the emitter's new skip (933efe3, never measured on this
   project) would drop.

Also standing: the layer root has **no conventions.json** — parity.sh passes
`--conventions $WS/conventions.json` and the file does not exist (idiom.py
tolerates it); the linux loop's layer carries one. The conventions that
generate the layer live in emit-scratch, outside the deliverable.

## Plan, in order

1. **Fresh emit with the current tool** (80639e7) — model.capture.json +
   the emit-scratch conventions, into a scratch tree; strip-compare vs the
   layer; classify the deltas (expected: the sys/BZL codegen split, the
   root BUILD, dead-tool skips). "Done": a classified delta list.
2. **Install the emit into the layer** (the emit's BUILD files over the
   layer's, hand-written infra kept) — re-verify from scratch: parity.sh
   (expect converged / ≤105 / 0, IDIOM ≤0.0), `bazel build //:kernel`,
   build-image.sh, boot-ssh-test.sh (KVM PVH), the TCG boot on the
   rule-built cd.iso. Revert to the current layer if any gate regresses.
3. **Warnings floor investigation** — read diff.json's warning detail:
   can legacyinc-style extra_generated become plain sources (in-tree
   files) without losing parity? Do the dead-tool skips move extra_tu?
   Only generic, parity-preserving moves.
4. **conventions.json into the layer root** — the durable record, the
   sibling precedent (linux), so a re-emit is reproducible from the repo.
5. **Re-emit gate** — re-emit after install; expect byte-identical outside
   comments (this is what makes the layer emitter-reproducible, the real
   close of the corrected item 3).
6. **Final gates** — hermetic-build.sh (clean container) on the final
   layer; check-invariants.sh if the tool changed; report + journal.

Parity is the regression test for every step; a step that regresses any
gate is reverted, not excused.
