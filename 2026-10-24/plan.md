# plan — 2026-10-24

## State at run start

PARITY build=GREEN diff=converged errors=0 warnings=105 artifacts=converged,
IDIOM 0.1 (threshold 0.0) — the score is **entirely the 4th genrule**: the
cdboot genrule the cut-off 2026-10-22 run left uncommitted in the layer tree
(`bazel/image/BUILD.bazel`, `make-cdboot.py`, `bazel/rules/boot_iso.bzl`).
The 2026-10-16 release state (genrules=3) scored 0.0.

The 2026-10-22 journal records: the cdboot ISO as a layer artifact is
written, and **the TCG boot was already proven on the genrule's output**
(SSH in at 8 s under `-accel tcg`, `FreeBSD 15.1-RELEASE ... BZL`,
root on vtbd0). What the run never got to: the `boot_iso.bzl` rule was
written but never wired into BUILD (the genrule is still there), parity was
re-run with the genrule in place (105 warnings, converged), hermetic was
not re-run, and the report was never finished.

## Plan

1. **Finish the 2026-10-22 work in idiomatic shape.** Replace the cdboot
   genrule with the `boot_iso` rule already in the tree (check it actually
   works — it was written but never exercised: `python3` via
   `use_default_shell_env` is a suspect). Also convert the `rootdisk`
   genrule to a rule of the same kind: genrules 4 → 2 tree-wide, IDIOM
   back under the release threshold with headroom (0.0 is the floor now,
   any genrule costs it). The two image scripts share one mechanism —
   a stage script the rule runs with the project's own makefs(8) — so one
   bzl module with two purpose rules (or one generalized rule) is the
   shape.
2. **Parity as the guard rail**: build `//bazel/image:image`, then the
   full parity run; expect converged / 105 / 0 and IDIOM ≤ 0.0.
3. **Prove the boots again on the rule-built outputs**:
   - TCG: the ISO through cdboot → loader → kernel (the runner's only
     viable boot path), the 2026-10-22 recipe on today's `:image`.
   - KVM PVH direct boot (the harness acceptance form, project.env
     BOOT_ARGS) — unchanged and must stay green.
4. **Hermetic**: `hermetic-build.sh freebsd` with the new rules (the
   genrule it passed last time did not exist in the release; the rules
   must not pull in anything new from the host — python3 is on the
   runner's apt set, makefs/readelf come from the tree).
5. **The owner-side change, written out exactly**: boot-ssh-test.sh needs
   a `--cdrom` form and project.env's BOOT_ARGS the ISO form, so the
   runner's TCG test stops using the PVH `-kernel` path that panics.
   (Shared script — report, not edit.)
6. If all gates green: `publish: release`, with the layer commit the
   harness squashes carrying the finished image rules.

## What "done" is

- `//bazel/image:image` builds through rules (0 genrules added by this
  run; tree-wide genrules ≤ 3), IDIOM 0.0, parity converged / 105 / 0.
- TCG boot OK on the ISO, KVM PVH boot OK, hermetic OK.
- report.md states the exact boot-test change the owner applies.
