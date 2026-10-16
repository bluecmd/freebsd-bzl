# journal — run 2026-10-16

## 2026-10-16 ~00:20 — start
- Read prompt.md, feedback.md, plan.md (written), report.md skeleton (written).
- Base state: parity GREEN (converged, 180 warnings), IDIOM 0.0, HERMETIC OK, BOOT-SSH OK.
- This run's work: owner item 3 — emitter-reproducible layer end to end.

## 2026-10-16 ~00:26 — bootstrap claims (tool commit 940be37, wt-freebsd)
- Conventions `bootstrap` entries gained `claims`: the recorded compiles their
  target covers (build-relative outs). `_drop_bootstrap_claims()` removes those
  CppCompile actions before `_plan_consumed_objects` — no more duplicate
  sys_kern_genoffset / sys_amd64_amd64_genassym / sys_compat_ia32_ia32_genassym /
  sys_amd64_acpica_acpi_wakecode pieces and their cc_object_files.
- The `-DOFFSET_TEST` genoffset variant is spelled as the layer's
  `sys/kern:genoffset` bootstrap entry (claims genoffset_test.o).
- Root TODOs 18 → 14; the four duplicates are gone from a fresh emit (conv-run12).
- Test added: test_bootstrap_claims_silence_the_recorded_compiles. Suites green → committed.

## 2026-10-16 ~00:50–01:30 — include surface (tool commit 9a9c235)
- New conventions `include_surface` block: aggregate rename (root headers
  library → `kernel_headers`), `includes` propagated by the aggregate,
  `package_headers` (per-package headers FILEGROUP `headers` — the label the
  aggregates reach across by; a cc_library's DefaultInfo names artifacts, not
  hdrs), `carriers` (layout links rendered as views in the trees' OWN package:
  `machine_include` cc_library with include_prefix + `tree` filegroup in
  sys/amd64/include, x86, i386; root label filegroups amd64/x86/i386_include),
  extra aggregates (`sys_headers`) and groups (`config_inputs`), and
  exports_files glob forms (root workspace-relative globs; per-package `**/*`).
- Layout-link targets under the model's source_root now resolve (the kernel's
  compile-directory symlinks point at the captured source tree); targets under
  the repo root get the project prefix stripped via _pkg_rel.
- Carriers are rendered once, from the root render, routed by pkg+pin into
  their own package BUILD — no cross-package glob needed.
- Test added: test_include_surface_reaches_across_the_package_boundaries.
  All suites green (117/117 emit tests + full suite run) → committed.

## 2026-10-16 ~01:30–02:50 — step_outputs (tool commit 8ba2ed4) + emit-tree green on //sys/...
- Conventions `include_surface.step_outputs` {"name", "pkg", "exclude"}: one
  pinned filegroup of a generator package's generated files, so a target reads
  them by label instead of naming every step. Exclude carries the steps that
  sit downstream of the bootstrap targets it feeds (transitive: a step reading
  an excluded step's out is excluded too).
- Emitted into the emit-tree worktree: `bazel build //sys/...` ANALYZES green
  (535 targets) with zero hand patches; the only failure left was the replay
  genrule kernel_full's 3 recorded-but-own-object inputs (locore.o,
  subr_ticks.o, xen-locore.o) — the replay runs the whole make inside, and
  those objects are the link's inputs, produced by the emitted pieces.

## 2026-10-16 ~03:00–03:45 — link_rule (tool commit 3e714c5): the link endgame is emitted
- Conventions `link_rule` {"targets"}: the layer's two `freebsd_kernel_link`
  calls render through the project's rule, attrs verbatim (out /
  debug_out / stripped_out / args / srcs / shared_libs / object_files /
  driver), deps DERIVED by the emitter: the CppLink action's 1151 recorded
  inputs in the reference's ld order, each .o mapped to the piece that
  compiles its source (the split pieces), dedup preserving order; a dep's
  archive maps by label; a file picked out of a dep by basename maps to the
  object_files dict's key (the vdso .o pair); header libraries ride the
  pieces, not the link.
- The codegen replay (the in-tree make: 69 outs incl. kernel.full) and the two
  binutils objcopy actions (kernel.debug, kernel) are claimed by the rules'
  outs (a -1 sentinel) and not emitted — the replay genrule, the objcopy
  genrules, and with them the 6 .git staleness inputs and the 3 missing .o.
- emit-tree: `bazel build //sys/...` GREEN end to end (537 targets, zero hand
  patches): "Linking the kernel sys/BZL/kernel.full", keep-debug and
  strip-debug run. kernel.debug is byte-size-IDENTICAL to the layer's own
  build (51,476,712 both); kernel.full / stripped kernel within ~0.01% of the
  layer's (DWARF comp_dir paths differ between the two trees). Reference
  sizes differ more (unstripped 61.9 MB vs 61.0) — the same divergence the
  delivered layer shows; parity's artifacts=converged is the structural
  differ's verdict, which is what the gate measures.
- Test added: test_link_rule_convention_renders_the_projects_own_link_endgame
  (attrs verbatim, ld-order deps, replay claimed, determinism).
  118/119 emit tests (the one failure is the pre-existing environmental
  test_meson_archives import), all other suites green → committed.

## Next
- plan item 3's Done is reached on the experiment tree: the deliverable
  kernel comes from emitted BUILD files. Remaining: warnings
  (codegen.tool_map for the 67 `*_if`, the script-spelling 8), then gates.

## 2026-10-16 (later) — item 4: the generated-tool class collapses (tool 5dc68a6)

Root cause of the 67+8 generated_tool_diff warnings, found in the capture
itself:

- bmake spells its recipe lines `sh -c -- '<line>'` (POSIX end-of-options,
  guarding a leading dash). `_is_shell_c`/`shell_command` took `--` as the
  script, so every `mv -f x.tmp x` rename line became a kept stage with the
  identity `--` — 57 stages per phase recipe. Fixed in both parsers
  (codegen.py `_is_shell_c`, extract_capture.py `shell_command`): the line
  is the next operand after the skipped `--` run, and the `mv` glue drops —
  the 69-output phase recipe is ONE stage: the build's own replay
  (`python3 tools/build/make.py ... buildkernel`).
- Why the reference recipe is a replay at all: FileTrace.owners() stops the
  ancestor walk at make/gmake but not bmake, so the parity wrapper shell
  (`sh -c 'cd src-ref && python3 tools/build/make.py ... buildkernel'`)
  owns every output the kernel phase wrote. Deliberately NOT re-fixed
  capture-side this run (re-extract blast radius over the whole emit
  pipeline); reported as a follow-up instead.
- A build-driver stage cannot be demanded of Bazel: no rule re-runs the
  build inside itself. New config `codegen.replay_stages` (recorded
  decision, like tool_map): the differ waives those stage identities, a
  recipe with no generator stage left waives the whole recipe compare for
  the action and emits ONE info record (infos do not count as warnings);
  G2 content stays the oracle. The emitter derives the list from the
  codegen actions the conventions' link rules claim wholesale, so
  `emit_build.py --config-out` reproduces the config — and the fix also
  revealed that link-rule claims keyed bare (`sys/BZL/kernel.full`) while
  cmake models key generated outputs under the project root: claims are
  keyed in both spellings now.
- diff.py: `_diff_codegen_tools` waiver + info record. A subtle regression
  caught by the new engine test before any run: the waiver refactor had
  dropped `pb` (the bazel pipeline), which NameError'd 5 tests.
- Config for this project (models/kernel/any2bazel.json, diff-time,
  hand-recorded as the owner's convention):
  `codegen.replay_stages = ["tools/build/make.py"]` (the diff rebases stage
  identities against the project root; the capture's absolute
  `/scratch/.../src-ref/tools/build/make.py` rewrites to that) +
  `codegen.tool_map = {"awk": "//usr.bin/awk:awk",
  "sys/tools/amd64_vdso.sh": "$SCRIPT", "sys/tools/amd64_ia32_vdso.sh":
  "$SCRIPT", "sys/conf/newvers.sh": "$(pwd)/sys/conf/newvers.sh"}`.
- Tests: `--` parse (codegen 22/22, extract_capture 181/181), the waiver
  (test_replay_recipe_stages_are_waived_by_codegen_replay_stages, engine
  150/150), the emitter's derivation + the both-spellings claim
  (link_rule test extended; emit 118/119, the one failure the pre-existing
  environmental meson import). All other suites green. Committed 5dc68a6.

Result (diff re-run on the existing models): **180 → 105 warnings, 0
errors** — the whole generated-tool class gone; 1 info record for the
69-output replay; the 5 awk + 3 script spellings matched by tool_map; what
remains is exactly the accounted host-tool facts (76 extra_tu, 20
extra_generated, 9 extra_target) of building more phases than the
reference recorded.

## 2026-10-16 (later) — item 3 close-out: the emitted config, and the last two tool fixes (b567fe1)

- The diff-time config is now emitter-produced: conventions `config_template`
  carries bazel_args + codegen.{mnemonics,tool_map,content_ignore_lines}; the
  emitter derives `target_map` and `codegen.replay_stages` from the emit;
  `--config-out` writes it. The emitted config (emit-scratch/conv-run14.json)
  replaced the hand-written models/kernel/any2bazel.json (the hand version is
  backed up as any2bazel.json.pre-emit-config). Diff re-run with it: converged,
  0 errors, 105 warnings.
- Two bugs the emit+diff of that config exposed, both fixed and pinned by
  tests (tool commit b567fe1):
  - diff.py `_apply_target_map`: the bazel model keys its targets `sys/BZL:kernel`
    while the emitter derives `//sys/BZL:kernel` -- `_label_bare()` normalizes.
    Without it: 1 missing_target error + 10 extra_target from spellings alone.
  - emit_build.py `_render_link_rule`: the own-TUs piece is a compiler of TUs;
    `_link_deps` had stripped exactly the header libraries its compiles need,
    so the emitted force-dynamic-hack cc_library had no deps and its compile
    failed (`opt_global.h not found`). The piece now carries the unstripped
    deps; the link rule itself keeps the stripped list. Test
    test_link_rule_target_with_own_sources_keeps_the_include_surface (fails
    without the fix: the piece renders with no deps at all).
- Experiment tree re-emitted with the fixed tool: `bazel build //sys/...`
  GREEN (537 targets, zero hand patches); fdh piece now
  `deps = [":BZL_headers", "//:kernel_headers", ":pkg_generated"]`.
- Suites: emit 119/120 (the one failure the pre-existing meson environmental
  import), engine 150/150, all others green.

## 2026-10-16 ~05:25 — gates (item 6)
- PARITY: build=GREEN, diff=converged, errors=0, warnings=105,
  artifacts=converged, IDIOM score=0.0 (rules=403, tus=1425,
  genrules=3, dirs=167). The diff ran on the emitted config. Gate exit 0.
- HERMETIC: running.

## 2026-10-16 ~05:30 — emitter-reproducibility proven byte-for-byte
- Fresh emit from the committed tool (b567fe1) into emit-verify/:
  the emitted config is byte-identical to models/kernel/any2bazel.json
  (CONFIG-IDENTICAL) and every emitted BUILD.bazel is byte-identical to
  the experiment tree's (the tree diff's 2796 lines are all "Only in
  emit-tree" — the staged source files; no differing BUILD file).
  The pipeline emit → BUILD tree + diff config is now fully
  deterministic end to end.
- HERMETIC: OK — //bazel/image:image builds in a clean container (exit 0).
- IMAGE: building (build-image.sh), then BOOT-SSH.
- IMAGE: GREEN — kernel 15,326,536 B + root.img rebuilt in /scratch/bluecmd/freebsd-bzl/image (gate exit 0).
- BOOT-SSH: running.
- BOOT-SSH: OK after 4s — "FreeBSD 15.1-RELEASE" over SSH, KVM.
  (First invocation failed twice for non-boot reasons: the shared script
  wants an explicit key+port — invoked bare, `${1:?ssh private key}` fired;
  on the second try port 2222 was already held by something outside this
  session's view — 2223 binds and the gate passed there. Shared-script
  observation, not a tool change: nothing to edit in bin/ per the rules.)
- IMAGE + BOOT-SSH gates: green. All four gates green.
- check-invariants.sh: running against wt-freebsd.
- INVARIANTS: OK (suites green in wt-freebsd, vocabulary clean) — exit 0.
- Layer tree untouched: clean at 262f6aa42. Run ended 06:16 CEST.

## 2026-10-16 ~06:30 — item 5 re-measurement (analysis only, no tool change)
- Adapted cmp_pieces.py to the link-rule render (cmp_pieces2.py): parses
  the `freebsd_kernel_link(name = "kernel")` deps in sys/BZL/BUILD.bazel
  and compares per-package piece names against the 2026-10-14 rename
  manifest (the layer's names).
- Fresh emit with the committed tool: **136 packages with kernel.full
  pieces; 119 identical, 17 differ — the same 17-package set as conv-run4**
  (diff of the two measurements: empty). No naming regression from this
  run's include-surface/step/link work; classes unchanged (merged plain
  regimes, global-namespace alternate leaves, sys/BZL codegen-aware split).
- Two of the 17 now have cleaner explanations than last run: sys/kern's
  `genoffset` is claimed by the bootstrap target (no plain piece emitted),
  and sys/BZL's `*_if_c` layer pieces are claimed by the step rules
  (step_outputs) — both are conventions-level regime choices, not bugs.
- Item 5 stays deferred by design: exact name parity with the layer is not
  a tool goal (the layer's names come from its rename manifest; the diff
  normalizes names). The classes are documented in the 2026-10-14 report.
