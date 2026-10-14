# journal — 2026-10-14

- (earlier, pre-compaction) TCG gate analysis: reproduced the runner's
  `panic: TSC not initialized` mechanism (PVH + baked
  `machdep.disable_tsc_calibration=1` → `tsc_disabled` → `lapic_init`
  KASSERT) and the second mechanism (tunable=0 → PIT-calibration DELAY →
  `xen_delay` fault on unmapped shared_info). Disassembled TCGTEST's
  `start_TSC` to pin the faulting call. Concluded `-kernel` PVH cannot
  boot this kernel under TCG.
- Boot-recipe hunt: hand-built GPT disk (pmbr→gptboot→loader) — fixed
  pmbr header layout and GUIDs (freebsd-boot = 83bd6b9d-…, freebsd-ufs =
  516e7cb6-…); pmbr now loads the boot partition but gptboot hangs before
  its first disk read (virtio trace: reads stop at the boot partition).
  Left open; suspect 64 KB vs gpart's 512 KB boot partition (gptldr copies
  8×32 KB blocks) — did not chase.
- ISO pivot: `makefs -t cd9660` + El Torito `bootimage=i386;boot/cdboot;
  no-emul-boot` from the reference legacy makefs. First boot: loader ran
  but could not open any file (plain ISO9660 names); added `-o rockridge`
  (what release/amd64/mkisoimages.sh uses) → full loader.
- TCG validation: cdboot→loader→kernel under explicit `-accel tcg` with
  the UFS root disk on virtio. TCGTEST kernel: full boot + SSH.
  Deliverable BZL kernel (INVARIANTS on): full boot + SSH (~10 s), no
  panic — the "TSC not initialized" panic is PVH-specific, not a kernel
  config problem. Root cause of the runner gate failure is the boot path.
- Verified the layer-built makefs also supports cd9660/rockridge/bootimage.
- Wrote the full TCG section into report.md. Time-boxed the GPT loader
  path as "attempted, hangs, not chased" in the report.
- Emitter experiment started: emit_build.py runs on the freebsd model
  capture out of the box (empty conventions -> 3643-line root BUILD, 1
  cc_binary kernel.full + 21 flag-group cc_libraries + 12 genrules, 256
  TODOs). Gap vs the delivered layer: no per-package routing (the model's
  3 kbuild targets span 116 source dirs), no split of the kernel target,
  generators as genrules instead of the layer's kernel_steps rules.
- Owner item 2 landed in the delivered layer: all 190 cc_NNN targets
  renamed to component/reason names by rename_targets.py (mechanical
  rule: single source -> stem (+_ext on collision); multi-source ->
  defines slug, -I leaf, shared stem prefix, else the directory's leaf;
  the package's core group claims the leaf first; three pinned
  overrides: ck/src -> ck, libb2 -> blake2_ref, BZL cc_053 -> vers_c).
  rename_manifest.json records old->new for all 190. Two script bugs hit
  and fixed mid-run (cross-package refs resolved before renames were
  known; the local-label pass dropped the ':'), state restored from the
  item-4 patch each time. kernel_steps.bzl's doc example and one stale
  BZL comment followed the rename. bazel query parses; the full parity
  gate is running.
- Naming rule notes for the emitter spec: the delivered names are
  exactly what _grp_name's docstring promises (the TU, not an index)
  once a per-package split convention exists; the manifest's mapping is
  the conventions record (group_name_map) for the three pinned names.

- (segment, post-compaction) Emitter split landed in the tool. The
  debugging chain in full, since each fix was load-bearing: (a) the
  core regimes were not "plain" — after `_copts` their copts still
  carried the rule-injected block (the item-4 fold) and the prefix maps,
  so the define slug named four packages' cores
  `have_kernel_option_headers`; fixed with conventions `rule_supply`
  (GENDIR twins folded, `-include` pairs as one unit) and
  `_drop_supplied`, which gives the naming rule the argv minus probe
  minus rule-injection; (b) `_deviates` false positives —
  stack_protector.c (no -fstack-protector in its argv) and 6 aesni TUs
  (no -O2/-nostdinc) forced whole-line spelling; measured on the model:
  only 7 of 1149 kernel.full compiles miss any supply token, and all 7
  enabled the feature in the layer → conventions `supply_additive`
  (early return False in _deviates); (c) `largest_plain` — my
  comprehension bound `s` never (crash), then bound s=copts after
  reordering the unpack (all cores fell to stems[0]); the correct unpack
  is `for s, _c, p`; (d) cross-package duplicate piece names — the
  emitter keys targets by name globally, so two `acpica` pieces
  overwrote each other in per_target and routing orphaned pieces;
  fixed with per-package naming seeded with the global used-set
  (`_split_used_global`), `EmitTarget.split_pkg` presetting the routed
  package, and absolute `//pkg:name` dep labels on the parent link;
  (e) group_name_map pin keys — the layer's conventions spell
  `<package>:<basename>`; added the basename fallback lookup (the
  workspace-relative key misses because tus are spelled
  workspace-relative) and fixed the libb2 key to the real basename
  `blake2b-ref.c`.
- Comparison: cmp_pieces.py (emit-scratch) parses kernel.full's dep
  labels from the emitted root BUILD, keeps those that are
  cc_per_source_library rules in their package, and diffs against
  rename_manifest.json. One comparator bug found and fixed on the way:
  the label regex `[\w/.]+` has no `-`, so every `xz-embedded` label was
  dropped (and one stale run had been compared against conv-run2).
  Final numbers from the COMMITTED tool (fresh emit, conv-run4): 136
  packages with kernel.full pieces; 119 identical, 17 differ, all
  classified in report.md (merged plain regimes, global-namespace
  collisions, codegen-aware split not implemented).
- Suites green: emit_build 101/102 (the one failure is the pre-existing
  test_elf_symbols import-path failure), engine 149/149, idiom 1/1,
  probe_toolchain 7/7, codegen 21/21, configure 10/10, build_lint 12/12,
  build_triage 18/18, triage 6/6, extract_capture 180/180. Committed on
  freebsd-intree as 7265867 (emit_build + tests, Co-Authored-By line).
  New tests: package_split naming + whole-link, group_name_map pins,
  global `_2` suffix, supply_additive, rule_supply/_drop_supplied.
- Gates at the end of the run: HERMETIC OK (hermetic-final.txt),
  BOOT-SSH OK KVM exit 0 (boot-ssh-final.txt, deliverable kernel + UFS
  root disk). Report item-3 section rewritten from "staged" to
  "committed tool feature + measured name parity"; Results / What
  remains / Verdict written: publish: release.
- The emitted tree was built (time-boxed experiment; ~30 min). Setup:
  `git -C freebsd worktree add /scratch/bluecmd/freebsd-bzl/emit-tree
  --detach d7ef77b83` + `git apply` the layer's diff + overlay the
  emitted BUILD files (conv-run5). Result: `bazel query //:kernel.full`
  loads all 137 packages (the tree parses). First build hit a REAL
  emitter bug — the hoisted `_RECIPE_ENV` constant was rendered only
  into the root BUILD; `sys/BZL`'s routed genrules reference it in cmd
  (Raw) and died on the undefined name. Fixed
  (`_package_text.needs_env` now also fires on values carrying
  `_RECIPE_ENV`), test added, suites still 102/103 (the pre-existing
  test_elf_symbols import), committed 94f4c8c. Rebuild then stops at the
  step rules: `//sys/BZL:acpi_wakecode_bin` — the wakecode recipe reads
  `sys/BZL/acpi_wakecode.o`, an object of a compile the model does not
  record (the unrecorded bmake bootstrap), and the emitter's TODO names
  the missing convention (`object_files.load`); the layer implements it
  as kernel_steps `gen_offsets(archive, member)` / `acpi_wakecode`. One
  speculative convention addition was tried and reverted (object_files →
  //bazel/rules:cc_object_files.bzl: no such module in the layer).
  No kernel compile ran yet — analysis aborts first; whether the ~1100
  emitted TUs compile is answered only after the step-rule conventions.
  emit-tree worktree removed after the experiment; conv-run5 +
  conventions.json stay in emit-scratch.

## 2026-10-14 (later) — the step rules land in the tool

The mapping insight that changed item 3's shape: the model's 12 Genrule
+ 211 unrecorded ConfigureFile actions map nearly 1:1 onto the layer's
`sys/BZL` step rules, and the only compiles the capture misses are the
bmake bootstrap's tool objects. Implemented three ways in the emitter
(commit 5f923b3 then 9efe3bb, suites 106/107 + 30/30 + 12/12):

* `recipe_kinds` `awk_modes` (5f923b3): the bmake awk step family —
  `awk -f script src [mode]` passes of one (script, input) pair group
  into one `awk_generate` call with `outs` + `modes`. Verified against
  the real model: the emitted `acpi_quirks` call is byte-identical to
  the layer's; vnode_if differs only in list formatting. 5 of the 12
  genrules gone.
* `unrecorded_codegen` entries may now carry `attrs` (the rule call's
  spellings) and may claim the outs of a RECORDED action: the entry
  fires once at claim-sighting, the action keeps only its unclaimed
  outs — all claimed, the action is not emitted. The buildkernel replay
  collapses to `kernel.full` alone (9 of the 12 genrules gone).
* `bootstrap` convention + entry `pkg` (9efe3bb): the genoffset /
  genassym / acpi_wakecode tool objects the capture records nothing for
  are emitted verbatim from `bootstrap`, pinned to their package; a
  step rule whose outs the rule derives (makeobjops) names its package
  (`pkg`) because routing cannot see derived outs — the respell rebases
  the attrs' logical spellings.

Scratch table generator `emit-scratch/gen_steps.py` turns the layer's
own `sys/BZL` spelling + the model into the 39-entry step table (28
makeobjops, kernel_config over 209 outs, 3 gen_offsets, wakecode,
newvers, 2 vdso_image, 2 rpcgen_xdr, force-dynamic-hack) + 3 bootstrap;
conventions.json now carries recipe_kinds + the 39 entries + bootstrap.

conv-run8 (full table): every step rule + bootstrap lands in
`sys/BZL/BUILD.bazel` — 28 makeobjops (name, src) pairs IDENTICAL to
the layer, kernel_config outs/attrs identical, all outs respelled
package-relative, relative labels (`:opt_global.h`, `:assym.inc`,
`:acpi_wakecode_s`) intact. Root BUILD TODOs down 227 → 18 (the four
"recipe reads its object(s)" + link flags + layout links — the staged
items). Only 3 genrules remain in sys/BZL (force-dynamic-hack,
kernel.debug, kernel) + the kernel_full replay with kernel.full as its
only out. sys/BZL census vs layer: every step-rule kind 1:1; the
residual diffs are the staged items (cc_library 60 vs 0,
cc_per_source_library 5 vs 35, freebsd_kernel_link 2 vs 0 — include
surface + kernel link + object_files).

Emit-tree re-run (worktree d7ef77b83 + layer diff + conv-run8 overlay,
experiment hand-patches on top — config_inputs/exports preamble from
the layer's root BUILD, per-package `exports_files(glob(["**/*"]))`,
`headers` filegroups for 91 packages, kernel_headers→pkg_headers alias
+ the 3 include-tree carriers, the layer's `generated` filegroup list):

* `bazel query //:kernel.full` loads all 137 packages;
* analysis passes ALL step rules (the old wall — `acpi_wakecode_bin` —
  is gone; the wakecode rule extracts its member from the bootstrap
  archive the layer's way);
* real compiles run: config(8), rpcgen, the awk steps, newvers all
  execute, and the bootstrap tool objects (genoffset.c, genassym.c,
  acpi_wakecode.S) compile — after the include-tree carriers were
  wired, which was the include-surface item doing exactly its job
  (`machine_include`/`x86_include`/`i386_include` on the -I line);
* `//sys/BZL:kernel_full` analyzes (7058 targets configured) and runs
  to a 13-file missing-input wall: the 6 `.git` staleness files the
  reference's in-tree build read (Bazel ignores `.git` by default) and
  the 7 `object_files.load` `.o` files (genoffset/genassym ×2/
  acpi_wakecode/locore/subr_ticks/xen-locore) — the two remaining
  convention gaps, precisely named.

The kernel-TU compile sample (sys/kern, sys/amd64/amd64, sys/vm,
sys/netinet, sys/x86/x86, sys/dev/virtio, acpica `:all`) — result
recorded in the report; that question ("whether the ~1100 emitted TUs
compile") is now answered.

**TU sample result (measured):** with the `rule_supply` drop landed
(a92a2b0), the sample compiled to a single wall — `vnode_if.h` does
`#include "vnode_if_typedef.h"` by sibling and the per-piece
`pkg_generated_under_*` filegroups name only the headers the argv
spells (the generated-header transitive-closure half of the
include-surface item). Experiment hand-patch (switching the sampled
pieces to the layer-style full `pkg_generated` carrier): **build green,
342 actions / 341 compile commands, exit 0** — kern, amd64, vm,
netinet, x86/x86, virtio, geom all compile. The `//sys/...` full tree
then stopped at the last wall found this run: the bootstrap tool
objects come out twice (the conventions' `bootstrap` entries in
sys/BZL, byte-identical to the layer, AND source-package pieces from
the recorded compiles — `sys_amd64_acpica_acpi_wakecode`, the per-source
`sys_*_genassym` cc_libraries). The capture backs the layer's
spellings: two recorded genoffset compiles (plain, `-MTgenoffset.o`;
`-DOFFSET_TEST`, `-MTgenoffset_test.o`) mirror the layer's
sys/BZL:genoffset / sys/kern:genoffset pair exactly. Next conventions
step: `bootstrap` entries claim their recorded compiles (the same
suppression the step rules already do). Committed a92a2b0; suites
emit_build 107/108 (pre-existing `test_elf_symbols` import-path
failure), artifact_diff 30/30, build_lint 12/12.

**Full-tree result (measured):** with the two named conventions gaps
hand-patched in the experiment tree (full `pkg_generated` carrier; the
layer's aesni builtin-include spelling — the reference argv never spells
clang's resource dir, the driver adds it, so only conventions can carry
it) and the bootstrap-object duplicates deleted, `//sys/...` minus the
kernel_full replay **builds green: 1171 actions, 1170 compile commands
in the sandbox, exit 0** (~135 packages, 51s). A third gap surfaced: the
emitted tree has no `-DOFFSET_TEST` genoffset compile anywhere — the
reference's second genoffset variant (`-MTgenoffset_test.o`, mirroring
the layer's sys/kern:genoffset) is missing from the emission. So the
remaining walls to the link are exactly the bootstrap-object claims
(+ the plain/test pair's routing) and the link convention itself
(`object_files.load` + the `.git` staleness inputs).

**aesni builtin-include surface landed in the tool** (5d2ac30):
conventions `builtin_include` — copts + dep, srcs keyed
project-relative via `codegen_key` (the model's own spelling; the
fixture's first spelling, repo-root-prefixed, did not match -- the
reconstructed model stores project-relative srcs). Verified twice: the
emit suite's new test, and the emit-tree -- the fresh conv-run10
emission's `sys/crypto/aesni` BUILD compiles green with NO hand patch
(5 compiles, exit 0). Remaining carrier gap: the generated-header
transitive closure (vnode_if.h → typedef.h).

**Generated-header reach closure landed in the tool** (22097d6):
conventions `generated_header_includes` — the edges spelled
project-relative, keyed through `codegen_key` (the reach's members are
the capture's build paths); `_reachable_generated` closes over them.
Measured on the real model: the per-piece carriers in sys/BZL went
from 0 to 58 carrying the vnode_if trio. Suites: 109/110, 30/30,
12/12. Both carrier gaps are now tool features; the remaining walls to
the link are the bootstrap-object claims and the link convention
(`object_files.load` + the `.git` staleness inputs).
