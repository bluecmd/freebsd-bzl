# journal — 2026-10-24

## The run's shape

The 2026-10-22 run was cut off after writing `bazel/rules/boot_iso.bzl`
but before wiring it into BUILD — the cdboot target is still a genrule,
which is the whole IDIOM 0.1 (genrules 4 vs the release's 3). This run
finishes that work:

- `boot_iso.bzl` was generalized into `bazel/rules/makefs_image.bzl` with
  two purpose rules — `boot_iso` (the El Torito CD) and `ufs_rootdisk`
  (the UFS root disk) — sharing one `_run_stage` helper. Both image
  genrules leave; tree-wide genrules 4 → 2 (usr.bin/lex and sys/BZL keep
  theirs, emitter-controlled).
- One real bug caught before it could cost parity: the first wiring used
  `out.short_path` for `--out`; a genrule's `$@` expands to the FULL
  declared path under `bazel-out/`, so the ISO landed in the execroot
  (`bazel/image/cd.iso`, undeclared) and Bazel failed "output not
  created" — while the script itself printed success (makefs ran fine).
  Reproduced manually (the script works), fixed with `out.path`.
  `make-rootdisk.py` shares the mechanism (it passes `args.out` raw to
  makefs); both now get the declared path.
- `//bazel/image:image` builds green through the rules: kernel,
  root.img (70 base files, 38 shared libraries), cd.iso (55 base files +
  the kernel, El Torito cd9660).

## A second, older break: the image gate's kernel path

- Running the harness's own `build-image.sh` failed: `cp -fL bazel-bin/
  kernel` — no such file. **`KERNEL_OUT=bazel-bin/kernel` (project.env)
  has been stale since the 2026-10-16 layer** moved the kernel endgame
  into sys/BZL and left `//:kernel` as an ALIAS: the alias keeps the
  //:kernel BUILD name but the stripped ELF's file stays at
  `bazel-bin/sys/BZL/kernel`. The 2026-10-14/16 harness acceptances
  recorded image=1 because a **stale pre-alias `kernel` file still sat in
  the output tree** from the 2026-10-12/14-era layer layout (Bazel does
  not prune it; the gate copied the STALE kernel and booted it — uname
  still says 15.1-RELEASE, so it looked fine). The cache losing that file
  exposed the break; the harness has not measured the gate since.
- Fix in the layer, not the harness env (project.env is the owner's):
  the root package's `//:kernel` is now a **copy_file** of the stripped
  ELF (filegroup `kernel_file` = `//sys/BZL:kernel` output_group kernel),
  out = "kernel", is_executable — the file lands at `bazel-bin/kernel`
  where KERNEL_OUT and the workflow's upload look. The duplicate copy at
  `bazel/image:kernel` was dropped (same action count tree-wide: one
  CopyFile, just in the root package; the image filegroup consumes
  `//:kernel`); `bazel/image:kernel_file` points at `//:kernel_file`.
- Verified: `bazel build //:kernel` → `bazel-bin/kernel` (15326536,
  exec bit), `build-image.sh` IMAGE green, KVM PVH boot-ssh **OK after
  4s** (the harness's BOOT_ARGS form, port 2245).
- TCG proof on the rule-built ISO: **BOOT-SSH OK after 6s (tcg)** —
  `FreeBSD 15.1-RELEASE` / `FreeBSD 15.1-RELEASE BZL`, TSC timecounter
  present, i8254/HPET/ACPI-fast choices as before.

## Pending

- parity re-run (the layer change is bazel/image + the new rule module;
  expect converged / 105 / 0 and IDIOM 0.0, genrules=2).
- TCG boot proof on the rule-built ISO (running), KVM PVH re-check,
  hermetic-build.sh with the rules in place.
- The owner-side boot-test change, written out exactly in the report.

## The emit-vs-layer link question — measured to ground truth (01:00–)

The suspicion "the emit's bzl merge breaks the kernel link order" needed
three measurements to settle, and the first two reversed my working model:

1. **The layer's kernel link deps list is NOT in the reference ld order.**
   Checked all 187 deps against the capture's CppLink input order (1151
   objects, unique stems — the earlier "config.o three times" was a
   substring artifact: exconfig.o/getnetconfig.o): **32 first-position
   decreases, 39 span overlaps**. The layer's deps are alphabetical by
   package with the method `_c` singles and the specials in blocks. The
   **emit's 152-dep list IS ld-ordered** (mechanical). Both converge in
   parity — so link input order is not a parity axis at all; layout
   differences are tolerated by design.
2. **Within-piece srcs order**: the emit's pieces are ld-ordered (0
   inversions, 6 gaps over the kern piece), the layer's has 5 inversions
   and 18 gaps (alphabetical with hand pins). Again the emit is the more
   faithful one.
3. **The real emit-vs-layer gap is the 2026-10-14 report's declared
   residual "codegen-aware split not implemented"**: the emitter folds
   the generated .c compiles into the `bzl` core bucket (one regime, 33
   TUs, one link position) where the layer keeps single-generated-file
   pieces (`acpi_if_c` … 28 of them, `vers_c`, the rpcgen pair on
   `rpctls`, the config step's .c on `bzl`'s `:config` group).

The model's data decides the rule cleanly: kernel.full has **37 generated
TUs, all in sys/BZL** — 28 interface method files (Genrule outputs),
vnode_if.c, vers.c, the 4 rpctls rpcgen outputs, and config.c/env.c/hints.c
(the config step's outputs, `gen_outs_all` gains them when the step rule
renders). Rule implemented in `_split_by_package` + two helpers
(`_gen_rule_map` from the rendered rules' outs, `_gen_tu_groups`): a
(package, regime) piece splits out each codegen-rule group as its own
piece, named by the component rule (`bus_if_c` — the generator claims the
stem), the core keeps the regime name. Configure-time-only sources stay in
the core (gen_outs_all excludes them by construction). This should move
the emitted kernel link deps 152 → ~184 (layer: 187) and put the method
files' objects at their own link positions. Fresh emit → structural diff
vs layer → build the emit tree's kernel → suites.

## The codegen split, landed and proven (≈02:50)

Fresh emit (model.capture + conventions, `--no-commit`) with the patched
`_split_by_package`: **sys/BZL renders 36 pieces** — 28 `*_if_c` singles,
`bzl` (config.c/env.c/hints.c, the config step's group), `bzl_2`/`bzl_3`
(the two rpcgen groups — the layer hand-merges them into one `rpctls`;
the emitter has no data saying they are one, so two is what the model
yields), `vnode_if_c`, `vers_c`, plus genoffset/genassym/
acpi_wakecode_s. The `free` carve-out released each piece's own
stem+ext reservation (`vnode_if.c` → `vnode_if_c` again, not
`vnode_if_2`); names otherwise unchanged. Kernel link deps **152 → 183**
(layer: 187); each generated TU's object sits at its reference ld
position; span overlaps of the generated groups against the layer's
hand-merge: the vnode_if/rpctls folds account for the 4-dep difference.

Emit tree built GREEN: git worktree `emit-wt2` at layer HEAD 140dfa0ab +
the new emit's BUILD files overlaid; `bazel build //sys/BZL:kernel` —
**1669 actions, success**. Sizes: kernel.full 61,078,120 (old emit
61,074,984, layer 61,076,360), stripped kernel 15,328,296 (old 15,325,160,
layer 15,326,536), kernel.debug **51,476,712 — identical size** to the old
emit's. Layout-only movement, as a reorder implies.

**Boot proof: BOOT-SSH OK after 3s: FreeBSD 15.1-RELEASE** — the harness's
boot-ssh-test.sh, KVM, PVH direct boot of `emit-wt2/bazel-bin/sys/BZL/
kernel` + the layer's root.img, port 2257. The reordered codegen-split
link boots.

Remaining before commit: re-run the 22 suites + vocabulary + corpus sweep
on the final tool state (the earlier suite run predated the `free`
carve-out edit), then commit on freebsd-intree if all green.

## Closed (≈03:00)

`check-invariants.sh` on the final tool state (after the `free` carve-out
edit): **INVARIANTS OK** — suites 22/22 green, vocabulary clean, CORPUS=1
sweep **37 converged before, 37 after** (zero regression; picocom/uhubctl
pre-existing lint deltas unchanged). Tool change **committed on
freebsd-intree as 7ff91e0** (89+/5− in emit_build.py). Scratch cleaned
(/tmp/emit-*, /tmp/ldpos.json, /tmp/e1, /tmp/e2, worktrees emit-wt and
emit-wt2 removed; emit-tree is pre-existing, kept). Report verdict:
**publish: release**.
