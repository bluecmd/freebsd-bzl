# plan — 2026-10-16

State at start: PARITY build=GREEN diff=converged errors=0 warnings=180
artifacts=converged; IDIOM 0.0 (threshold 0.0); HERMETIC OK; BOOT-SSH OK
(KVM) — all carried from 2026-10-14, layer clean at 262f6aa42, tool at
802d47c.

Parity is green and the image boots, so this run's work is the last
piece of owner item 3 (2026-10-12): **making the layer emitter-
reproducible end to end** — last run left the emitted tree compiling
all ~1170 kernel TUs (with two conventions gaps hand-patched in the
experiment tree); the walls to the link are precisely named.

## Attack order

1. **Bootstrap-object claims** (tool). The conventions' `bootstrap`
   entries emit the layer's four `sys/BZL` tool-object targets verbatim,
   but the recorded compiles ALSO come out as source-package pieces
   (`sys_amd64_acpica_acpi_wakecode` in sys/amd64/acpica; per-source
   `sys_*_genassym` cc_libraries). The step rules already have claim
   machinery — give `bootstrap` entries the same suppression, plus
   route the two recorded genoffset compiles as the layer spells them
   (sys/BZL plain, sys/kern `-DOFFSET_TEST`/`-MTgenoffset_test.o`).
   Done = fresh emit has NO source-package duplicate of the four
   bootstrap objects and DOES have the `-DOFFSET_TEST` compile.
2. **Re-emit + build `//sys/...` with zero hand patches** (the
   experiment tree again; recipe in last run's journal). This
   verifies items 1 + last run's committed carrier features
   (builtin_include, generated_header_includes) as pure tool output.
3. **The link convention** (tool): map the reference's link line onto
   the layer's `kernel_link` machinery; `object_files.load` for the
   replay's 7 `.o` inputs; a decision for the 6 `.git` staleness
   inputs (mark/drop — the layer's answer first). Done = the emitted
   `sys/BZL` builds `kernel.full` (or the layer's link shape) end to
   end: the deliverable kernel comes from emitted BUILD files.
4. **Warnings**: record `codegen.tool_map` for the 67 `*_if`
   bmake→awk swap warnings (tool-side config, the owner named the
   convention); then look at the 8 script-spelling ones. Target:
   warnings ≤ 180 and ideally well under (the 2026-10-12→14 flatness
   was called out by the owner).
5. **Naming/namespace residue** if time: per-package name namespaces
   (class-2 collisions), codegen-aware piece split (class 3), the
   merged-regime decision (class 1).
6. **Gates**: parity.sh (build+diff+artifacts, IDIOM ≤ 0.0),
   hermetic-build.sh, boot-ssh-test.sh (KVM). Expect all green — the
   layer is untouched by this work except through tool re-emit
   experiments; the delivered layer changes only if the tool's output
   is proven better and wired through conventions.json.

## Done

- emitted tree (fresh tool emit, conventions.json from the committed
  tool) builds `//sys/...` and the kernel link with no hand patching;
- parity/idiom/hermetic/boot gates all green at run end;
- the four warning classes are accounted with any changes explained;
- report.md + journal.md current.

## Progress 05:20

- Items 1–4 are done (see journal/report): bootstrap claims, include
  surface, link_rule, and the warning classes collapsed 180 → 105
  (0 errors). The diff-time config is now an emit product
  (`--config-out`); the experiment tree builds `//sys/...` end to end
  with zero hand patches.
- Item 5 (naming residue): deferred unless gates leave time — the
  collisions are accounted, none are errors.
- Item 6 gates: parity.sh running now; hermetic, boot-ssh, image after.
