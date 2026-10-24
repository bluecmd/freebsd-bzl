# report — 2026-10-24

*(updated as the run proceeds; verdict at the end)*

## State at run start

PARITY build=GREEN diff=converged errors=0 warnings=105 artifacts=converged,
IDIOM 0.1 — above the release threshold 0.0 for the first time, and the
cause is not a corpus regression: it is exactly the 4th genrule the cut-off
2026-10-22 run left uncommitted in the layer tree (the cdboot genrule;
`bazel/rules/boot_iso.bzl` was written but never wired into BUILD). The
release state itself (genrules=3) is intact. The 2026-10-22 journal records
a TCG boot proof on that ISO's output (SSH in at 8 s under `-accel tcg`),
never reported. Runs 2026-10-18/20 produced nothing (the deleted
bazel-cache fault, documented there).

## What this run landed

### (1) The cdboot ISO as rules, not genrules (the IDIOM gate)

`bazel/rules/boot_iso.bzl` (written but never wired last run) became
`bazel/rules/makefs_image.bzl`: two purpose rules sharing one `_run_stage`
helper — **`boot_iso`** (the El Torito CD) and **`ufs_rootdisk`** (the UFS
root disk). Both image genrules leave the layer; tree-wide genrules
**4 → 2** (the residue is `usr.bin/lex` and `sys/BZL`, emitter-controlled),
and IDIOM is back to **0.0** with rules=404 unchanged.

One real bug caught in the wiring: a genrule's `$@` expands to the FULL
declared path under `bazel-out/`; the first rule wiring used
`out.short_path`, so makefs wrote the ISO into the execroot
(`bazel/image/cd.iso`, undeclared) while the script printed success —
Bazel failed "output not created". Fixed with `out.path`; both scripts get
the declared path.

### (2) The image gate's kernel path was broken — silently, since 2026-10-16

Running the harness's own `build-image.sh` failed: `cp -fL bazel-bin/
kernel` — no such file. **`KERNEL_OUT=bazel-bin/kernel` (project.env) has
been stale since the 2026-10-16 layer** moved the kernel endgame into
sys/BZL and left `//:kernel` as an *alias*: the alias keeps the //:kernel
BUILD name, but the stripped ELF's file stays at `bazel-bin/sys/BZL/
kernel`. The 2026-10-14/16 harness acceptances recorded image=1 because a
**stale pre-alias `kernel` file still sat in the output tree** from the
2026-10-12/14-era layer layout (Bazel never pruned it; the gate copied the
STALE kernel and booted it — uname still says 15.1-RELEASE, so it looked
right). The cache losing that file exposed the break; the harness has not
measured this gate since 2026-10-16.

Fix in the layer (project.env is the owner's file): the root package's
`//:kernel` is now a **copy_file** of the stripped ELF (filegroup
`kernel_file` = `//sys/BZL:kernel` output_group kernel), so the file lands
at `bazel-bin/kernel` where KERNEL_OUT and the workflow's upload look. The
duplicate copy at `bazel/image:kernel` was dropped — same action count
tree-wide (one CopyFile, in the root package), warnings unchanged at 105,
rules unchanged at 404, IDIOM 0.0.

### (3) All four gates, on the final layer

- **PARITY build=GREEN diff=converged errors=0 warnings=105
  artifacts=converged 0 errors, IDIOM score=0.0 (rules=404 tus=1425
  genrules=2 dirs=167)** — parity.sh on the final tree; the 105 are the
  accounted host-tool floor (76 extra_tu + 20 extra_generated + 9
  extra_target), unchanged from the 2026-10-16 release.
- **IMAGE green** — the harness's `build-image.sh`: kernel 15,326,536 B +
  root.img (268 MB) into `$ROOT/image`.
- **BOOT-SSH OK after 4s: FreeBSD 15.1-RELEASE** — the harness's
  BOOT_ARGS form (PVH direct boot under KVM, port 2245).
- **TCG boot OK after 6s** — the runner's form: `-accel tcg`, the
  rule-built `cd.iso` (cdboot → loader → kernel) + `root.img`, SSH in,
  `FreeBSD 15.1-RELEASE` / `FreeBSD 15.1-RELEASE BZL`, TSC timecounter
  present, root on vtbd0.
- **HERMETIC OK: //bazel/image:image builds in a clean container.**

### (4) The owner-side change, exactly

The runner's TCG gate needs two owner-file edits (both mechanical, the
layer now supplies everything):

1. **`bin/boot-ssh-test.sh` gains a `--cdrom ISO` form** (sibling of
   `--disk`): attach the ISO as an IDE cdrom (`-drive
   "file=$ISO,format=raw,if=ide,media=cdrom"`) and boot from it
   (`-boot order=d`) when no `--kernel` is given; the serial log on
   stderr as today. The validated QEMU line is runs/2026-10-22/
   `tcg-boot.sh` (re-proven this run on the rule-built ISO).
2. **`projects/freebsd/project.env`**: the runner's boot test wants
   `BOOT_ARGS="--cdrom $ROOT/image/cd.iso --disk $ROOT/image/root.img"`
   (drop the `--kernel`/`--append` — the loader.conf inside the ISO
   carries `vfs.root.mountfrom`); and `build-image.sh` should build
   `//bazel/image:image` (HERMETIC_TARGET) and copy all three outputs —
   kernel, root.img, **cd.iso** — into `$ROOT/image` instead of
   rebuilding the root disk with the reference's makefs (the layer now
   makes both images itself; the `$REF` makefs dependency goes away).

Until those land, the local harness acceptance keeps the PVH/KVM form,
which passes (4 s). The verdict's boot gate is measured on it.

### (5) Correction to the 2026-10-16 record: the layer is NOT emit-identical

Owner item 3 was declared complete on the evidence "fresh emit from the
committed tool + conventions.json is byte-identical". Re-measured this
run: the verification compared emit-vs-emit-tree (two experiment trees)
and the config (CONFIG-IDENTICAL holds, re-proven) — **it never compared
the emit against the layer**. Measured now, against both the 2026-10-16
tool (b567fe1) and current HEAD (f903246): **139/139 sys packages'
BUILD.bazel differ** (with `--config` and `--workspace` as well as
without). The structural classes:

1. **Include-surface carriers**: the emit renders a `cc_library
   <pkg>_headers` (hdrs glob + textual_hdrs) per package; the layer
   uses filegroup `headers` carriers under the root `kernel_headers`/
   `sys_headers` aggregates (195 cc_library name deltas).
2. **Method-file carriers**: the emit folded the generated .c compiles
   into one `bzl` core piece; the layer names each interface
   (`acpi_if_c`, `bus_if_c`, ...) — the 2026-10-14 "codegen-aware split
   not implemented" residual. **Fixed this run** — see (6).
3. **Per-piece shape**: the layer's pieces carry
   `features = ["kernel_compile_flags"]` and explicit carrier deps
   (`offset_inc`, `config`, ...); the emit spells the include surface
   differently (56 cc_per_source_library deltas, 45 filegroup deltas).

Two beliefs about link order did not survive measurement, and both
reverse the earlier picture:

- The **layer's** kernel link deps list is NOT in the reference ld
  order: against the capture's CppLink inputs (1151 objects, unique
  stems — an apparent triple `config.o` was a substring artifact:
  `exconfig.o`/`getnetconfig.o`) it has **32 first-position decreases
  and 39 span overlaps** — the deps are alphabetical by package, with
  the `_c` singles and the specials in blocks. The **emit's** deps list
  IS the reference ld order (mechanical).
- Within pieces: the emit's piece srcs are ld-ordered (kern piece: 0
  inversions, 6 gaps over 195 TUs), the layer's are alphabetical with
  hand pins (5 inversions, 18 gaps).

Both builds' kernels converge in parity, so link input order is not a
parity axis — layout differences are the differ's tolerated class. The
practical consequence: the emitted kernel link is MORE
reference-faithful than the layer's, and the layer's "pinned ld order"
premise (under which the bzl merge looked order-breaking) was wrong.

### (6) The codegen-aware split — the 2026-10-14 residual, landed in the emitter

The model decides the rule cleanly: kernel.full has **37 generated TUs,
all in sys/BZL** — 28 interface method files (Genrule outputs), `vnode_if.c`,
`vers.c`, the 4 rpcgen outputs, and `config.c`/`env.c`/`hints.c` (the
config step's outputs; `gen_outs_all` gains them when the step rule
renders). `emit_build.py`'s `_split_by_package` now splits each
(package, regime) piece so that **every TU whose source a rendered
codegen rule wrote leaves the core as its own piece, grouped by the
generating rule** (new helpers `_gen_rule_map` over the rendered rules'
outs, `_gen_tu_groups`); configure-time-only sources stay in the core
(`gen_outs_all` excludes them by construction). The component naming rule
names them — `bus_if_c` beside the `bus_if` generator, `vers_c`,
`bzl` for the config step's three .c — one carve-out added: a piece may
take the stem+extension label of the very file it compiles (the claim
keeps output-file labels free; a piece compiling the file is not one).
Measured on a fresh emit: **sys/BZL 36 pieces** — 28 `_if_c` + `bzl`
(config/env/hints) + `vnode_if_c` + `vers_c` + the two rpcgen groups —
and the kernel link deps **152 → 183** (layer: 187), each group at its
reference ld position. The residue vs the layer is the hand-merges only:
the layer folds `vnode_if.c` into `bzl` and the two rpcgen groups into
one `rpctls` piece, and pins `group_name_map` names.

Verification: all 22 test suites green; a fresh emit's tree builds
//sys/BZL:kernel green (1669 actions) and **boots under KVM/PVH —
BOOT-SSH OK after 3s: FreeBSD 15.1-RELEASE** (the harness's
boot-ssh-test.sh, the layer's root.img). Sizes moved slightly with the
reordered link — kernel.full 61,074,984 → 61,078,120, stripped kernel
15,325,160 → 15,328,296 (layer: 61,076,360 / 15,326,536; reference:
61,955,984), kernel.debug byte-size-identical at 51,476,712 — consistent
with a layout-only change, and parity/artifact_diff is what guards
correctness, not byte size. The change is generic (model codegen data +
rendered rules only) and gated to `package_split` targets — no other
corpus project uses the convention.


## Verdict

**publish: release.** The layer (base tag + one commit, carrying this
run's image rules and the root kernel copy) builds with parity converged,
0 errors, warnings at the 105 floor (unchanged), IDIOM 0.0 at genrules=2;
the kernel boots and accepts SSH under KVM (4 s) and — the standing
release gate — under the runner's TCG through the layer's own cdboot ISO
(6 s); the image target builds hermetically in a clean container. The
runner-facing boot-test change (boot-ssh-test.sh `--cdrom` + project.env
BOOT_ARGS + build-image.sh building //bazel/image:image) is written out
above for the owner to apply; until it lands the runner publishes
pre-release purely for lack of the `--cdrom` form, not for anything the
layer lacks.
