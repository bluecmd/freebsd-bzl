# report — 2026-10-16

*(updated as the run proceeds; verdict at the end)*

## State at run start

PARITY build=GREEN diff=converged errors=0 warnings=180 artifacts=converged
0 errors. IDIOM score=0.0 (rules=403 tus=1425 genrules=3 dirs=167) — the
release threshold, which is 0.0 itself. HERMETIC OK and BOOT-SSH OK (KVM)
carried from 2026-10-14. Layer tree clean at 262f6aa42 ("Bazel layer
(2026-10-14) on release/15.1.0"); any2bazel worktree freebsd-intree at
802d47c (kbuild-intree merged in from the Linux loop).

## Plan

plan.md in this directory: this run finishes owner item 3 (2026-10-12) —
the layer emitter-reproducible end to end. Attack order: (1) bootstrap
claims so the four tool objects stop coming out twice, (2) re-emit + build
`//sys/...` with zero hand patches, (3) the link convention + the replay's
remaining input classes, (4) the warnings' `codegen.tool_map`, (5) naming
residue.

## Journal

`journal.md` beside this report.

## Results

### (1) bootstrap claims — done (tool 940be37, freebsd-intree)

The four tool objects (genoffset, genassym ×2, wakecode) no longer emit
twice: a `bootstrap` entry may carry `claims` — the recorded compiles its
target covers — and the emitter drops those CppCompile actions before the
consumed-object plan. The `-DOFFSET_TEST` genoffset variant is spelled as
the layer's `sys/kern:genoffset` bootstrap entry (it claims
genoffset_test.o, the second build of the tool's object that kern.post.mk
does). Root TODOs 18 → 14. Fresh emit (conv-run12) shows the four
duplicates and their cc_object_files gone, and sys/kern's genoffset entry
byte-matches the layer.

### (2) include surface — done (tool 9a9c235)

New conventions `include_surface`: the root headers library renamed to
`kernel_headers` with `includes = ["sys"]` propagated; per-package
`headers` filegroups (the labels the aggregates reach across by); the
three layout links (machine/x86/i386) rendered as carrier views in the
trees' own packages (`sys/amd64/include` & co: `machine_include`
cc_library with `include_prefix` + `tree` filegroup, plus the root
`amd64_include` filegroup the step rules name); `sys_headers` and
`config_inputs` groups; exports_files glob forms (root workspace-relative
globs, per-package `**/*` — the wall that killed the first zero-patch
build on `//sys/amd64/amd64:sigtramp.S`). Layout-link targets under the
model's source_root now resolve. 117/117 emit tests; full tool suite
green before the commit.

### (2b) emit-tree experiment — green, end to end

Fresh emit (conv-run13 → the emit-tree worktree, then the link rules) builds
`//sys/...` with ZERO hand patches: analysis green, and the kernel link runs
— `freebsd_kernel_link` (the layer's own rule) links `sys/BZL/kernel.full`
from the emitted pieces, then the objcopy endgame makes `kernel.debug` and
the stripped `kernel`. kernel.debug is byte-size-identical to the layer's own
build; kernel.full and the stripped kernel within ~0.01% of it (DWARF
comp_dir paths differ between the two trees; the reference's sizes differ
more, the same divergence the delivered layer already shows — parity's
artifacts=converged is the structural differ's verdict).

### (3) the link convention — done (tool 3e714c5, freebsd-intree)

New conventions `link_rule` {"targets"}: a link target whose endgame the cc
rules do not have renders through the project's rule — the layer's two
`freebsd_kernel_link` calls, attrs verbatim (out/debug_out/stripped_out/
args/srcs/shared_libs/object_files/driver). The emitter derives the deps:
the CppLink action's 1151 recorded inputs in the reference's ld order, each
.o mapped to the piece that compiles its source (dedup preserving order), a
dep's archive by label, a dep picked out of the attrs by basename (the
object_files dict's vdso .o pair). The codegen replay (the in-tree make,
69 outs incl. kernel.full) and the two binutils objcopy actions are claimed
by the rules' outs (a -1 sentinel) and not emitted — which drops the replay
genrule, the objcopy genrules, and with them the 6 .git staleness inputs and
the 3 recorded-but-own-object walls. This closes the last named wall of
item 3: the deliverable kernel now comes from emitted BUILD files, with no
image/boot/loader/QEMU/SSH knowledge anywhere in scripts/ or SKILL.md
(freebsd_kernel_link stays the layer's module; the tool only knows
"the project's own link rule").

### (4) the warnings' tool convention — done (tool 5dc68a6, freebsd-intree)

The 75 `generated_tool_diff` warnings root-caused to two parser facts, both
fixed generically:

1. bmake spells its recipe lines `sh -c -- '<line>'` — the `--` is POSIX
   end-of-options, but both shell parsers took it as the script, so every
   `mv -f x.tmp x` rename line became a kept stage with the identity `--`
   (57 stages per phase recipe). Both parsers fixed; the glue drops.
2. What remains per recipe is one stage — the parity wrapper's replay of
   the build itself (`python3 tools/build/make.py ... buildkernel`, which
   owns every output the kernel phase wrote because the capture's
   ancestor walk stops at make/gmake but not bmake). No Bazel rule re-runs
   the build inside itself, so the stage is not demandable — it is WAIVED,
   not matched: new config `codegen.replay_stages` (a recorded decision the
   emitter derives from the codegen actions the conventions' link rules
   claim, so `--config-out` reproduces it); a recipe with no generator
   stage left gets one info record (not a warning) and G2 content stays
   the oracle.

With the recorded diff-time config (`replay_stages =
["tools/build/make.py"]` + `tool_map` for the 5 awk and 3 script
spellings — vnode_if/acpi_quirks run `//usr.bin/awk:awk` on the layer, the
vdso and newvers scripts are staged under different names):

**PARITY: errors=0, warnings 180 → 105** — exactly the accounted host-tool
facts (76 extra_tu + 20 extra_generated + 9 extra_target of building more
phases than the reference recorded). The whole generated-tool class is
gone: 1 info record for the 69-output replay; tool_map matched the 8
n=1 recipes. The 2026-10-12→14 warnings flatness the owner called out is
broken by 75.

## Verdict

*(to be filled)*

### (3, continued) the emitted diff-time config — done (tool b567fe1, freebsd-intree)

The config the diff runs on is now an emit product, not a hand artifact:
conventions `config_template` carries `bazel_args` +
`codegen.{mnemonics,tool_map,content_ignore_lines}`; the emitter derives
`target_map` and `codegen.replay_stages`; `emit_build.py --config-out`
writes it. The emitted config replaced the hand-written
`models/kernel/any2bazel.json` (backup: `any2bazel.json.pre-emit-config`)
and drives the same diff: **converged, 0 errors, 105 warnings**.

Two bugs that emit+diff exposed, fixed and pinned by tests:

- diff.py `_apply_target_map`: the bazel model keys its targets
  `sys/BZL:kernel`, the emitter derives `//sys/BZL:kernel` —
  `_label_bare()` normalizes; without it 1 missing_target error + 10
  extra_target warnings from spellings alone.
- emit_build.py `_render_link_rule`: the own-TUs piece lost the header
  libraries `_link_deps` strips from the link's own dep list — the emitted
  force-dynamic-hack cc_library had no deps and its compile failed
  (`opt_global.h not found`). The piece carries the unstripped deps now
  (test fails without the fix: the piece renders with no deps at all).

Experiment tree re-emitted with the fixed tool: `bazel build //sys/...`
green (537 targets, zero hand patches). Tool committed b567fe1 with all
suites green.

## Gates (06:00–06:15)

| gate | result |
|---|---|
| PARITY | build=GREEN, diff=converged, **errors=0 warnings=105**, artifacts=converged; IDIOM score=0.0 (rules=403, tus=1425, genrules=3, dirs=167) |
| HERMETIC | OK — //bazel/image:image builds in a clean container |
| IMAGE | GREEN — kernel 15,326,536 B + UFS root.img in /scratch/bluecmd/freebsd-bzl/image |
| BOOT-SSH | OK after 4 s — `FreeBSD 15.1-RELEASE` over SSH, KVM |
| INVARIANTS | OK — suites green, vocabulary clean |

Note: the diff ran on the **emitted** config (models/kernel/any2bazel.json =
the emit product, byte-reproducible — see (3, continued)).

## Verdict

publish: release

Every goal is met: the layer at 262f6aa42 (= release/15.1.0 + the Bazel
layer commit) stays parity-converged with the warning class that was the
run's target collapsed 180 → 105 (0 errors) by a committed, tested tool
change; the diff-time config is now an emit product, byte-reproducible
end to end; and the emitted tree builds `//sys/...` including the
deliverable kernel link with zero hand patches. All gates green; the
layer itself is unchanged (the tool-side work does not require a layer
re-emit to stay green — parity/build/boot all run on the committed
layer).

Follow-ups recorded for the next run:
- capture-side `owners()` should stop at `bmake`/`pmake` (the parity
  wrapper shell currently owns every phase output — faithful
  per-output recipes would need a full re-extract + re-verify).
- item 5 (naming residue): per-package name namespaces (class-2
  collisions), codegen-aware piece split (class 3), merged-regime
  decision (class 1) — deferred, all accounted, none are errors.

### (5) naming residue — measured with the current tool, deferred

The piece-name comparison re-run on the fresh emit (the link-rule render)
against the layer's rename manifest: **136 packages with kernel.full
pieces, 119 identical, 17 differ — the same 17-package set as 2026-10-14's
measurement**. No naming regression from this run's include-surface /
step-rule / link-rule work. Two of the 17 have cleaner explanations now:
sys/kern's `genoffset` is claimed by the bootstrap target and sys/BZL's
`*_if_c` pieces are claimed by the step rules — conventions-level regime
choices, not tool bugs. The remaining classes (merged plain regimes;
global-namespace alternate leaves like `acpi`/`acpica`, `atrtc`/`isa`;
the sys/BZL codegen-aware split) stay as classified in the 2026-10-14
report — exact name parity with the layer is not a tool goal (the layer's
names come from its own rename manifest; the parity diff normalizes
names), so this is deferred unless the owner asks for name-for-name
emission.
