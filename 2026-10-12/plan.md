# plan — 2026-10-12

## Start state

PARITY GREEN/converged/132/0 errors, artifacts converged. IDIOM **0.8** —
exactly the release threshold, so this run must go strictly under it.
HERMETIC OK and BOOT-SSH OK carried from 2026-10-09. any2bazel main
034a03f (kbuild-intree merged). No tool changes queued.

Score anatomy (models/kernel/idiom.json):

- packages_vs_dirs t=0.0719 → **0.719** of the score: 155 packages with
  rules for 167 source dirs.
- genrules_per_tu t=0.0049 → **0.098**: 7 genrules / 1423 TUs.
- Every other detector 0.

The 167 dirs include 5 bazel-out codegen dirs (never packageable), so the
honest ceiling is 162 tree dirs, of which 16 have no package.

## Goal

IDIOM < 0.8 with parity, hermeticity and boot all still green. Every
gate re-run at the end; parity after every transform batch.

## Work list, in order

1. **Split the 4 rules that own the 16 un-packaged dirs** into per-dir
   cc_library pieces in packages at the sources' own directories
   (the 2026-10-09 kernel split, continued for the host tools):
   - `//lib/libc:legacy` → pieces in contrib/libc-pwcache, contrib/libc-vis,
     lib/libc/gen, lib/libc/stdlib, lib/libc/string, lib/libutil;
     `legacy` stays as the umbrella (defines/includes/hdrs/deps kept, srcs
     move out) so the 7 tool consumers keep their labels and their own
     compiles' propagated flags byte-identical.
   - `//usr.sbin/makefs:makefs` → pieces in usr.sbin/makefs/{cd9660,ffs,
     msdos,zfs} plus the borrowed sources: contrib/mknod, contrib/mtree,
     sbin/newfs_msdos, stand/libsa/zfs. The -Iusr.sbin/makefs(-/zfs) pairs
     ride a new parent `headers` carrier dep so the propagated -I order
     (own includes first, then deps) is preserved exactly.
   - `//usr.bin/lex:lex` → contrib/flex/src piece (copts carry the same
     -I$(GENDIR)/usr.bin/lex -Iusr.bin/lex -Icontrib/flex/src set).
   - `//usr.bin/m4:m4boot` → tools/build/bootstrap-m4 piece.
   - `//lib/libopenbsd:openbsd` → re-spell `//lib/libc:stdlib/recallocarray.c`
     to the new stdlib package.
   argv equality is the gate: piece = parent's defines + deps verbatim,
   includes spelled as explicit -I copts (workspace path + $(GENDIR)) in
   the same position the old propagated list had them.
2. **Kill the genrules that a rule already exists for**:
   - `bazel/image:kernel` → `copy_file`.
   - `sys/BZL:force-dynamic-hack.c` (empty TU) → `write_file`.
   - `lib/libc:legacyinc` → copy_file + write_file per file (a filegroup
     keeps the `:legacyinc` label for the umbrella's hdrs).
   - `usr.bin/awk:proctab`, `usr.sbin/config:kernconf`, `usr.bin/lex:skel`
     (tool-driven codegen): a generic `tool_generate` rule next to the
     yacc/lex generators if the first three land clean; otherwise they
     stay (3 genrules ≈ 0.04 of score — acceptable).
   - `bazel/image:rootdisk` stays (the deliverable's one honest glue step).
3. Full gates: parity.sh, idiom, build-image + boot-ssh-test, hermetic.

## Expected end state

- 16 new packages (19 new BUILD files counting the stdlib exports
  reshuffle), 4 owner BUILD files rewritten, 2-5 genrules converted.
- IDIOM ≈ 0.0-0.1 (packages_vs_dirs 0, genrules_per_tu 0.03-0.1).

## Done

`publish: release` requires: PARITY GREEN/converged/errors=0/artifacts
converged, IDIOM < 0.8, HERMETIC OK, BOOT-SSH OK.

## Risks

- argv drift on moved TUs (include order, defines order) — checked per
  batch with a fast aquery diff against the pre-change aquery before a
  full parity cycle.
- link/archive regrouping changing tool binaries' bytes — artifact_diff
  catches; the 2026-10-09 evidence says grouping is tolerated.
- write_file/copy_file byte and executable-bit semantics vs the genrule's
  (legacyinc headers feed compiles; the kernel copy feeds QEMU).
