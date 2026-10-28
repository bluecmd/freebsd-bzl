# report — 2026-10-28

*(updated as the run proceeds; verdict at the end)*

## State at run start

PARITY build=GREEN diff=converged errors=0 warnings=105 artifacts=converged
0 errors, IDIOM 0.0 (threshold 0.0) — the 2026-10-26 release state.
Feedback file empty this run. Layer tree clean; any2bazel wt-freebsd at
3eff38e (80639e7 line + the linux loop's two generic fixes: the
`./`-word/stage_dests matcher ad852cf, the run_shell-wrapper read c2a9c8d).
Hermetic OK as of 2026-10-24; boot proven both ways as of 2026-10-26.

## Plan

plan.md — IDIOM at floor, parity converged, all gates green: the run
attacks the emit-vs-layer identity (140/179 BUILD files differ, curation
only, both spellings parity-carrying), class by class, starting with the
sys/contrib vendor dirs.

## Journal

journal.md in this directory.

## Results

*(in progress)*

**The per-package piece render** (tool fdccd6a + 1d6c916, suites 131/131
emit_build + all 20 other suites green, invariants OK with corpus sweep
37/37 no regressions):

- per-package piece plans and names (`(name, package)` keys) — fixed
  the duplicate-libsodium render (sys/opencrypto rendered the piece
  twice while sys/crypto/libsodium lost its TUs entirely);
- piece_shape v5 (190 pieces / 136 packages; `[]` recorded for pieces
  with no additional_compiler_inputs — the absence is a fact);
- the emit's `generated` filegroup now carries the recorded awk
  generators' outputs too (vnode_if.{c,h,newproto,typedef}.h,
  acpi_quirks.h): without them the first emit-tree build failed 171
  TUs with `vnode_if.h file not found` — a gap the earlier aquery-only
  emit-floor proofs could not see;
- shaped pieces keep their derived deps over the shape's surface (the
  aesni pieces' `@kernel_llvm//:clang_builtins` — without it
  `wmmintrin.h file not found`; the emit-vs-layer "redundant dep"
  reading was wrong, the dep is parity-needed);
- the `generated` filegroup is in pkg_of before the pieces' respell (a
  piece's `:generated` resolved to `//:generated` before) and is final
  after its creation respell (a second respell re-crosses stripped
  paths);
- sys/kern's bootstrap entry re-spelled `genoffset.c` bare (it had
  carried the old hand render's `//sys/kern:genoffset.c` label).

First emit-tree build ran RED through three distinct failures (missing
vnode_if.h, missing clang builtins, `//:generated`); each root-caused
and fixed above; the emit tree now builds //sys/... — see below.

**The emit floor proven end to end, then installed.** The full `//...`
build in emit28 (emit's sys tree + kept hand-written root + untouched
non-sys files) is GREEN — exit 0, zero errors, through `//:kernel` and
`//bazel/image:image`. Installed with /tmp/install-emit.sh: of the 139
sys BUILD files 96 were already byte-identical, **43 written**;
`freebsd-bazel-probe.json` added (the conventions' toolchain_probe
reference is no longer dangling). The sys-scoped pipeline on emit28
converged (0 errors, 4 warnings) at IDIOM 0.0 before the install.

**Emitter-reproducibility on the installed tree: proven.** A fresh
scratch copy of the installed layer (emit29, real copy, bazel-*
symlinks out), re-emit with the same model + conventions: all 139 sys
BUILD files re-render byte-identical (0 differing), 0 TODOs. The root
is keep_files as before (the side-copy BUILD.bazel.root diverges only
in the known hand-curated surface). The conventions header now states
this: the delivered sys BUILD files *are* the emitter's render; only
the workspace root is hand-curated.

**Gates on the installed layer** *(live numbers below)*:

- **PARITY build=GREEN diff=converged errors=0 warnings=105
  artifacts=converged 0 errors, IDIOM 0.0 (rules=404 tus=1425
  genrules=2 dirs=167)** — byte-for-byte the released 2026-10-26
  numbers; the 105 warnings are the same accounted structural floor
  (x76 extra_tu + x20 extra_generated bootstrap-era headers).
- IMAGE outputs staged fresh from the layer's build: kernel
  15,328,296 B, root.img 268,435,456 B, cd.iso 16,695,296 B —
  `//bazel/image:image` built green inside the full parity build.
- **BOOT proven both ways on the emit-rendered kernel**: KVM PVH direct
  — BOOT-SSH OK after 4s, `FreeBSD 15.1-RELEASE` (boot-ssh-test.sh,
  port 2260); TCG through the rule-built cd.iso — BOOT-SSH OK after 9s,
  `FreeBSD 15.1-RELEASE BZL`, `kern.timecounter.choice: TSC(-100) …
  HPET(950)` (tcg-boot.sh, port 2261).
- HERMETIC queued (the image target's inputs changed — the kernel was
  rebuilt from the emit's BUILD files) — **HERMETIC OK: `//bazel/image:image`
  builds in a clean container.**
- Final census: **139/139 sys BUILD files byte-identical** between the
  emit render and the delivered layer — the emit-vs-layer delta that
  motivated this run (140/179 differ at run start) is CLOSED; the only
  remaining delta is the keep_files root, by design.

## What is next

Nothing load-bearing. The goal is achieved and every gate re-proven on
the delivered tree. Notes for the owner / future runs:

- **Runner boot gate (standing owner item, restated)**: the published
  layer commit's boot=0 is the runner-side gate, not the layer —
  `bin/boot-ssh-test.sh` needs a `--cdrom ISO` form (attach as IDE
  cdrom, `-boot order=d`, when no `--kernel` is given), project.env
  needs `BOOT_ARGS="--cdrom $ROOT/image/cd.iso --disk $ROOT/image/root.img"`,
  and `build-image.sh` should copy all three outputs (kernel, root.img,
  cd.iso) from `//bazel/image:image`. Under TCG the PVH direct boot
  panics ("TSC not initialized"); the cdboot ISO boots. Local proof of
  both paths is fresh this run. Also: a free-port retry in
  boot-ssh-test.sh would remove the port-collision flake class.
- **The 105-warning floor is unchanged and structural** (x76
  extra_tu host-tool sources + x20 extra_generated bootstrap-era
  headers, all bootstrap phases the reference's capture excludes);
  going less declared to silence it would be a real regression.
- **Kernel bytes moved ~1.7 KB** (15,326,536 → 15,328,296) with the
  emit's mechanical piece partition: the diff stage and link stage both
  converged, so the movement is only in what the linker was already
  free to reorder. Any future reference-change re-run should expect
  this class of benign movement.
- The conventions now live in the layer (derivation record + render
  claim in its header); a future re-emit of the sys tree from a
  reference update is a mechanical operation: fresh scratch copy, emit,
  prove, install by cmp/cp, re-emit to prove reproducibility, gates.

## Verdict

**publish: release.** The layer's sys BUILD tree is now the emitter's
render, proven end to end on the delivered tree: PARITY build=GREEN
diff=converged errors=0 warnings=105 artifacts=converged, IDIOM 0.0
(rules=404 tus=1425 genrules=2 dirs=167, threshold 0.0 held); emitter
reproducibility proven (139/139 byte-identical on re-emit, 0 TODOs);
IMAGE green; BOOT-SSH OK both ways (KVM PVH direct 4s; TCG cdboot 9s,
TSC timecounter present); HERMETIC OK in a clean container. Tool
changes committed in the any2bazel worktree (fdccd6a + 1d6c916 on
freebsd-intree) with all suites green and no corpus regressions; the
layer tree carries no commits (the harness squashes the working tree —
43 modified sys BUILD files + conventions.json + the probe file land in
the layer commit). ~8h of the 15.4h budget unused: the acceptance test
passed and no remaining idea moves a measured number.

## Verdict

*(pending)*
