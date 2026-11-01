# plan — 2026-11-01

## State at start

PARITY build=GREEN diff=converged errors=0 warnings=105 artifacts=converged,
IDIOM 0.0 (threshold 0.0), rules=404 tus=1425 genrules=2 dirs=167 —
byte-identical to the 2026-10-30 release measurement (parity-before.txt).
Layer tree: 0 changed/untracked files. Tool worktree: 1864082 — the exact
SHA the 2026-10-30 run proved reproduces this layer's render (179/179).
Feedback file: empty. No detector fires; idiom.json worst counts are all 0
(the only nonzero t is genrules_per_tu at 0.0028, which contributed 0.0).
The linux sibling run (2026-10-31) re-proved the same floor for its layer
under this tool with a full gate sweep — nothing generic to take from it
except its failed-first-hermetic note (a leftover output-base lock, not a
hermeticity finding).

## Assessment

The standing goal state is fully achieved and measured: parity green,
idiom at the 0.0 floor the threshold was lowered to, hermetic proven, boot
proven both ways (KVM PVH + TCG cdboot), emit reproduction proven for this
(layer, tool) pair. Nothing in the detector list, the warnings floor, or
the genrule count has a lever: the score cannot go below 0, the 105
warnings are the reference's own (parity-visible), and the 2 genrules carry
0.0.

## Environmental obstacle first

/scratch is 100% full (3.9G of 500G free; the 2026-10-30 run left 115G).
Something consumed ~110G since — possibly this project's own scratch
(ref/src-ref/freebsd out dirs), possibly other tenants. Parity and image
builds need tens of GB. Plan: locate the consumer; clean ONLY this
project's own regenerable scratch (previous run scratch dirs, my own emit
copies) — never the reference/capture/model inputs, never other tenants'
trees, never the src-ref. If the space is not mine to free, report it and
run the gates anyway if they fit, or with a fresh output base on /tmp.

## Order of work

1. Disk triage (above). Do not proceed to gates until at least ~40G free
   or a working alternative is proven.
2. Re-prove emit reproduction on a fresh scratch copy under 1864082
   (cheap; gives this run its own evidence rather than inheriting
   yesterday's).
3. PARITY: parity.sh freebsd, full output captured to the run dir.
4. IMAGE: build-image.sh; kernel + root.img byte sizes vs release numbers
   (15,328,296 / 268,435,456).
5. BOOT-SSH: boot-ssh-test.sh (KVM PVH direct).
6. TCG-CDBOOT: the run-local helper (tcg-cdboot.sh, mirroring the 2026-10-30
   helper) — the shared script still has no --cdrom form (standing ask
   restated below).
7. HERMETIC: hermetic-build.sh freebsd (only if the gates above are green;
   it is slow and its failure mode last week was environmental).

## What "done" is

All gates green and freshly measured in this run's dir, report.md stating
the verdict. If any gate fails, it becomes the work list instead.

## Standing owner asks (reported, not editable by this loop)

- bin/boot-ssh-test.sh has no `--cdrom ISO` form (4th run restating): the
  TCG/cdboot path needs a run-local helper each time. Also the free-port
  retry (port taken at boot start) — both are shared-script changes the
  loop tooling owner must make; this run again provides its working helper
  as the reference qemu line.
