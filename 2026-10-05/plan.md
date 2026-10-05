# plan — 2026-10-05

## Start state
No layer at all (MODULE.bazel missing; parity has no line). First run with a
budget (the 60-min smoke seeded only `sys/amd64/conf/BZL` and
`bazel/image/test_authorized_keys`). Model exists:
`models/kernel/model.capture.json` (3 targets: `kernel.full` = 1149
CppCompile + 1 CppLink, `force-dynamic-hack.pico`, 5 unlinked bootstrap
compiles; 223 codegen actions of which 211 are `<unrecorded>` — the whole
kernel-toolchain/bootstrap world folded into one composite recipe, plus
opt_*.h/config.c/env.c/hints.c and the .pico moves unattributed).

Model namespace lesson (read off the raw capture vs the model): the extractor
rewrote every `src-ref/...` path to `ref/amd64.amd64/...` — i.e. the model's
world has the *source tree* under the objdir (`ref/amd64.amd64/sys/kern/...`,
`-I .../ref/amd64.amd64/sys`) and the compile dir at `.../sys/BZL`. On the
Bazel side the sources are workspace files (`sys/kern/...`) and the compile
dir lives under `$(GENDIR)`; `ignore.include_map` carries both mappings. The
raw argv is the ground truth for what the reference actually spelled
(`-I.`, `-I src-ref/sys`, cwd `ref/.../sys/BZL`).

## Facts established (raw capture)
- Compile tool: `/scratch/bluecmd/freebsd-bzl/llvm/bin/clang` (LLVM 19.1.7),
  `-target x86_64-unknown-freebsd15.1 --sysroot=.../tmp -B.../tmp/usr/bin`,
  then a base flag set shared by 1060 of 1149 compiles; 22 distinct flag sets
  total (per-file `COPTS.<f>`, `-x assembler-with-cpp -DLOCORE` for .S,
  zstd files with `-DZSTD_HEAPMODE=1 -I .../contrib/zstd/lib/freebsd`).
- Link: `ld.lld -m elf_x86_64_fbsd -Bdynamic -L <sys>/conf -T <sys>/conf/ldscript.amd64
  --build-id=sha1 -z max-page-size=2097152 -z notext -z ifunc-noplt --no-warn-mismatch
  --warn-common --export-dynamic --dynamic-linker /red/herring -X <1150 objects>
  force-dynamic-hack.pico` → `kernel.full`; then ctfmerge into kernel.full,
  size/chmod, `objcopy --only-keep-debug kernel.full kernel.debug`,
  `objcopy --strip-debug --add-gnu-debuglink=kernel.debug kernel.full kernel`.
  The model records only the link; CTF and strip are capture-only (not in the
  model) → the differ cannot check them; the boot kernel must still be the
  stripped `kernel`.
- The capture records ctfconvert on every object and ctfmerge at the link;
  neither is in the model (no argv/output attribution). Decision this run:
  the layer reproduces the compiles, the link and the endgame file shape
  (kernel.full → kernel via objcopy) but NOT CTF; disclosed in the report
  (artifact stage cannot see sections; revisit if the owner wants CTF bytes).

## Layer architecture (from the model + the linux loop's proven shape)
- `MODULE.bazel`: toolchains_llvm (19.1.7), rules_cc, skylib, platforms;
  kernel platform (`//platforms:kernel`), kernel cc toolchain repo
  (`//bazel/rules:kernel_llvm_toolchain.bzl` clone) whose config carries the
  probed kernel line; exec toolchain = the same LLVM for host tools.
- `//tools/config:config` — config(8) built from the tree (the generator of
  the compile dir: opt_*.h, config.c/env.c/hints.c, device_if/bus_if, ioconf).
- awk generators as explicit genrules (makeobjops.awk → *_if.c/.h, vnode_if
  awk), assym/genoffset via the recorded shell recipes; awk itself built from
  the tree (one-true-awk + in-tree yacc) — no host PATH.
- Kernel compiles: one target (or a small set) compiling ~1149 TUs with the
  kernel toolchain; the generated-source TUs depend on the generators.
- Link: a `freebsd_kernel` rule (mnemonic **KernelLink**, the value
  project.env sets for EXTRA_MNEMONICS) replaying the recorded ld.lld line
  with `$(location)` objects; then objcopy endgame to `//kernel`.
- `.bazelrc`, `platforms/`, `conventions.json`, `sys/amd64/conf/BZL` (committed copy).

## Order of attack
1. Seed: hand-write the workspace skeleton (MODULE/.bazelrc/platforms/toolchain)
   and get the *first* compile + link actions matching; use emit_build.py over
   the model as the mechanical seed for the per-TU part only if it fits the
   model's degenerate shape — else write the BUILD myself from the model
   (the emitter is optional; the model's single-target shape makes a
   hand-written `kernel` package likely cleaner).
2. Generators: config(8) + awk, one generator at a time, diff-driven.
3. `parity.sh freebsd` after each step; diff/triage is the worklist.
4. build-image.sh + boot-ssh-test.sh once the kernel links.
5. Hermetic build; then idiom reduction (packages for directories, rules for
   repeated shapes — the linux loop's cc_per_source_library / ar_archive /
   tree_recipe pattern applies here too).
6. Tool changes: commit in wt-freebsd as I go, suites green, CORPUS=1 sweep.

## What "done" is
- PARITY build=GREEN, diff errors converged (or a disclosed, justified
  remainder), artifacts stage run.
- Image boots: BOOT-SSH OK.
- Report with verdict; tool changes merged-ready (invariants OK).
- Hermetic + idiom only if time remains (they gate a *release*, not a
  first build).
