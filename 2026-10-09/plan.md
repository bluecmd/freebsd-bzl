# plan — 2026-10-09

## Start state

PARITY build=GREEN diff=converged errors=0 warnings=132 artifacts=converged
0 errors. IDIOM **8.9** = packages_vs_dirs **8.8** (20 packages / 167
source dirs) + genrules_per_tu 0.1 (7 genrules / 1423 TUs). Every other
detector is 0. HERMETIC OK (2026-10-07), BOOT-SSH OK (2026-10-07).

## What the remaining 8.8 actually is

The kernel is ONE package, `sys/BZL` (3,421 lines), holding ~1,150 kernel
TUs in 57 `cc_per_source_library` groups. The 167 source dirs sit under it.
The 2026-10-07 run rejected a per-directory split because "the cc_NNN
compile-product archives are load-bearing in the verified link". Re-examined
this run: **the link consumes loose objects, not archives** —
`freebsd_kernel_link` walks each dep's `OutputGroupInfo(objects)` and
appends them in `deps` order; the `deps` list is spelled in the reference's
link-line order. And the skill/differ is explicitly grouping-agnostic for
libraries (TUs keyed by source path project-wide). So the load-bearing thing
is the **object sequence on the link line**, not the grouping. Regrouping or
relocating groups preserves parity iff that sequence is preserved. The
prior runs' conclusion was too conservative; this run re-tests it properly.

## The attack: one package per kernel source directory (the split)

The generic `package_dirs` machinery that the linux loop built and proved
(2,322 packages, IDIOM 19.9 → 5.2, whole-tree parity green) sits on
`kbuild-intree` (56b90e5, 8b08627, 21a3c8c, 8049f8f) — **not merged into
main** (`freebsd-intree` is at cec8b97). Merge it, then apply to freebsd.

The freebsd shape differs from kbuild's and needs emitter work that must stay
generic:

1. **Designation.** Kbuild derives packages from per-directory Makefiles;
   FreeBSD's kernel build has no per-directory Makefiles (one generated
   Makefile drives everything). The honest evidence is the model itself:
   designate the directories that own compiled sources (135 distinct dirs
   own the 57 groups' srcs; idiom counts 167 incl. host tools).
2. **Routing by source, not by output.** The emitter's routing routes a
   rule to the nearest designated dir containing its *declared outputs*
   (Kbuild's objects mirror their source paths). A FreeBSD
   `cc_per_source_library` declares no outs attr (objects come from
   `cc_common.compile` at runtime) — routing must key on the **read
   sources**, which the emitter already has as the fallback ("or, with
   none, their read sources").
3. **Multi-dir groups split.** 49 of the 57 groups are single-dir; 8 span
   dirs — `cc_003` is a 1,027-source blob over 103 dirs. Splitting it per
   directory is exactly what a person would write (one kernel library per
   directory). The pieces must be spelled in the link's `deps` in reference
   object order (pieces ordered by their first source's index). The
   differ's compile comparison is grouping-agnostic, so compile parity is
   unaffected; link parity sees the same object set in the same order.
4. **The kernel package's non-compile residents stay in `sys/BZL`**:
   the codegen targets (kernel_config's ~500 outs, the *\_if generators,
   vnode_if, newvers, vdso, wakecode), the `filegroup("generated")`, the
   `kernel_link`, `force-dynamic-hack`. Their deps re-spell to the moved
   groups' labels — the emitter's cross-package machinery (label re-spell,
   exports, header carriers) does this, proven on linux.
5. **Carriers/layering.** Every TU compiles with the toolchain feature's
   `-I` supply and `//:kernel_headers` — headers reached must be declared.
   The linux machinery builds a carrier per designated dir holding headers,
   chained from the root carrier; freebsd needs the same (generic).
6. **Root package's `sys/**` filegroups** (`kernel_headers`,
   `config_inputs`, DEFAULTS…) stop seeing past the new package boundaries —
   the emitter's glob-boundary handling (linux W2b fix) covers it.

## Order of work

1. **Setup** (~1 h): merge `kbuild-intree` into `freebsd-intree`; suites
   green; commit. Report stub + this plan + journal started.
2. **Fact-check the load-bearing claim** (~1 h): confirm nothing consumes a
   group's `.a` (the link takes `OutputGroupInfo(objects)`); confirm the
   differ's link-line comparison keys objects by canonicalized name, not by
   the producer's path, so object paths moving packages stay comparable.
   Read `diff.py`/`canonicalize.py` link handling. This is the go/no-go.
3. **The split** (bulk): designate dirs from the model; emitter extension
   for source-routed per-source groups + multi-dir group splitting; re-emit;
   `bazel build //...`; parity.sh; iterate. Commit tool work in small steps
   with suites green.
4. **Cleanup wins** if time allows: the 7 remaining genrules
   (force-dynamic-hack et al.) → genrules_per_tu 0.1.
5. **Gates**: hermetic-build.sh, build-image.sh + boot-ssh-test.sh on the
   final tree; final report.

## Definition of done

- PARITY converged (errors=0), artifacts converged, HERMETIC OK,
  BOOT-SSH OK — with IDIOM **< 8.9** (the split landing: expect ~1).
- If the split cannot converge, revert to the committed layer (idiom 8.9,
  already release-clean) and spend the remainder on the genrules + any
  safe cleanup: still `publish: release` at 8.9, honestly reported as
  "split attempted, why it stopped".

## Risk register

- The link-line object canonicalization may key on the producer path →
  regrouping changes nothing about paths if objects keep their names;
  verify in step 2 before moving anything.
- `sys/BZL` is also where Bazel puts the codegen outs and where `-include
  $(GENDIR)/sys/BZL/opt_global.h` points — that package must not move.
- cc group flags: several single-dir groups exist BECAUSE of per-source
  flags (`-Wno-unused-but-set-variable` etc.); splitting by dir must keep
  the per-source/per-flag grouping (a dir with two flag regimes becomes two
  groups — grouping is free, but only if the object order argument holds).
- 1,150 TUs re-routed means a full rebuild (~40 min/round, cache-cold for
  moved packages); budget rounds accordingly.
