# journal — 2026-10-28

## Run setup

- Scratch was 100% full (112M). Freed: emit-tree (1.7G, the 2026-10-24
  emit-verification tree, superseded by the 2026-10-26 measurement),
  probe-obj (642M), tcgtest-obj (631M) — all old-run scratch. Kept:
  hermetic/cache (28G, the hermetic run's warm cache — expensive to
  rebuild), image/, image-parts/ (the root-disk base set), ref/, cap/,
  models/, src-ref/. 2.7G free after.
- emit28 = `cp -a --reflink=auto freebsd emit28` (real copy, never
  hardlink — the 2026-10-26 wipe lesson).

## The re-measurement

emit28's emit (current tool 3eff38e, conventions = the layer's own, probe
copied in): the emitter writes exactly **140 files (root + 139 sys)** and
leaves the other 39 BUILD files (host tools + infra: makefs, awk, config,
lex, ... and bazel/, toolchain/, platforms/) untouched. The earlier
"39 strip-identical" reading of the first diff was an artifact: those 39
are UNTOUCHED copies, not render matches. Honest numbers: **emit-written
set = 140, 0 identical, 140 differ.**

Delta classes, from delta.py + the per-file reading:

1. **Piece include surface** (the big one): the emit's pieces carry
   `-I$(GENDIR)` copts + deps on the `<pkg>_headers` glob cc_library chain
   + an auto-named generated carrier (`//sys/BZL:pkg_generated_under_sys_BZL_6`
   — named by common dir, numbered on collision). The layer's pieces carry
   `hdrs = [//sys/BZL:offset_inc, vdso, vdso_ia32, acpi_wakecode, config,
   generated]` + `additional_compiler_inputs` + `deps = [//:kernel_headers]`.
2. **The layer's hdrs/aci are nearly uniform**: 119 pieces take the
   6-carrier blanket; 33 sys/BZL + 32 other pieces take the narrower
   [offset_inc, config, generated]; 2 are the amd64 vector/exception
   pieces; the aci list is the same 7 cross-package textual-include files
   on 118 pieces (imgact_elf.c, kern_ctf.c, qsort.c, subr_busdma_bounce.c,
   subr_syscall.c, netback_unit_tests.c, chacha.c — verified: they are
   FreeBSD's textual .c includes, needed by only a handful of TUs, declared
   blanket-package-wide by the layer).
3. **Carriers**: the emit renders a `cc_library <pkg>_headers` glob carrier
   per package (196×) + the filegroup headers (package_headers conventions
   key); the layer has the filegroup only, and the ROOT aggregate chains
   the filegroups (`kernel_headers.hdrs = glob + [//pkg:headers ...]`,
   91 entries) instead of deps on cc_library carriers.
4. **Comments/formatting**: the emit's "Derived mechanically..." header +
   piece comments vs the layer's templated package comment; multiline vs
   single-line list styles; attr order.
5. **alwayslink**: the emit spells `alwayslink = True` on 184 pieces; the
   layer's pieces don't (its kernel link pulls the loose objects).
6. **Root deliverable plumbing**: the emit's root render lacks
   `bitcount_header`, `makefs_includes`, `kernel_file`, `//:kernel`
   (the hand-added endgame; the makefs backends' BUILD files — which the
   emit does NOT write — reference `//:makefs_includes`, so the current
   emit render is not even analysis-consistent over the full workspace).
7. **3 emit TODOs** (the /red/herring link flag, the locore/subr_ticks/
   xen-locore object_files ask) — the layer has 0 TODOs; the render must
   resolve them to be installable at IDIOM 0.0.

## The decision (recorded, this run's direction)

**Close B**: teach the emitter the layer's idioms (generic features +
conventions facts), prove the render fully, and install the render as the
layer for the kernel tree — NOT mirror the layer byte-for-byte into
conventions (that direction makes the conventions a shadow copy of the
BUILD files and reproduces the layer's hand pins whose premise the
2026-10-24 measurement already reversed: the emit's link/srcs order IS
the reference's ld order, the layer's alphabetical order was wrong).

Shape of the endgame:
- the emit renders the 139 sys packages; the workspace root's hand-curated
  endgame (kernel_file, //:kernel copy_file, makefs_includes,
  bitcount_header, the curated exports_files) stays hand-written — a
  conventions `keep` key tells the emitter not to write it (this is also
  the wipe-proof: the one file the 2026-10-26 accident destroyed first is
  then never touched);
- the 39 host-tool/infra files stay untouched (the 933efe3 host-tool
  exclusion already does this);
- install = replacing the 139 sys renders (+ whatever of the root's
  kernel_headers shape the sys renders must match — resolved when the
  keep-root decision is wired);
- gates re-proven in full on the installed tree: parity.sh (the full
  build + aquery + diff + artifacts), IDIOM ≤ 0.0, image, boot (KVM + TCG
  cdboot), hermetic.

Intermediates all proven before moving on: every emitter change committed
with suites green; the emit render strip-diff shrinks class by class;
parity sys-scoped re-run on emit28 whenever the render changes shape.

*(next: read the emitter's piece/plan code, design the features)*

## The features, designed then implemented

Census of the layer (fresh, per piece, 189 pieces, 13 spellings → 3
semantics): 115 blanket (6 carriers + the 7-file aci list), 64 narrow
([offset_inc, config, generated], no aci; 33 spell it from inside sys/BZL,
31 from outside), 3 narrow + debug.c (zstd), 6 specials (locore,
xen_locore, genoffset, acpi_wakecode_s, aeskeys_amd64, subr_ticks — the
amd64 vector/exception .S files as hdrs). The aci entries pointing into
the piece's own package are spelled locally by the layer
(chacha.c, netback_unit_tests.c, kern's four) — a label-localization rule,
not different facts.

Hypothesis tested and REJECTED: the emit's auto-carrier reach sets do not
route blanket vs narrow (sys/fs/nfs reaches MORE than zlib yet the layer
made nfs narrow; namespace and zlib share one carrier but the layer made
namespace narrow+config-only). And no carrier the emit computed contains a
vdso/wakecode output at all — the blanket's extra three carriers are pure
over-declaration, the layer author's safety net, keyed by nothing the model
carries. **The routing is a conventions fact table** (the model records a
compile's primary input only; the read sets live in the reference's .depend
files, which the model does not carry).

Implemented in wt-freebsd (emit_build.py), all generic:

1. **conventions `piece_shape`** — `hdrs`/`additional_compiler_inputs` as
   {default, except keyed "<pkg>:<piece>" or "<pkg>"} + `deps`
   (["//:kernel_headers"]). The emitter renders shaped pieces with the
   layer's attr order (features, copts, srcs, hdrs, deps, uci), no
   alwayslink, no comment, labels into the piece's own package localized
   (`:name`, matching the layer's chacha.c / kern spellings). Real derived
   deps survive (aesni's `@kernel_llvm//:clang_builtins`); only the surface
   noise (the aggregate, the generated-files library, its `_under_`
   carriers) is filtered out (`_is_surface_label`).
2. The gendir blanket `-I$(GENDIR)` extra copt and the gen_label dep are
   suppressed for shaped pieces (the rule's KERNEL_DIR_COPTS carries them).
3. **conventions `keep_files`** — the emitter does not write a kept BUILD
   (the workspace root; also the wipe-proof).
4. The routing-time respelling (insert `:<leaf>_headers` into deps) skips
   shaped rules (`Rule.shaped`).
5. `_prune_unreferenced_carriers` — the blanket carriers nothing references
   do not render (the `<pkg>_headers` cc_library, `pkg_generated`, its
   `_under_` family); same rule `_loads_text` already applies to loads.
   Gated on piece_shape being non-empty.
6. The link's own piece (the split target's residual TU, the layer's
   force_dynamic_hack) shapes like the pieces (`_piece_shape_named`).
7. TODO cleanups: `_linkopts` is skipped for conventions `link_rule`
   targets (the /red/herring chase was noise — the attrs are verbatim);
   a consumed object whose readers are all claimed codegen actions (the
   replay the step/link rules replace) registers no cc_object_files
   (consumers are tracked in `object_file_consumers`, filtered by
   `_codegen_claimed` at render time — the claim tables exist only after
   plan_codegen, so the filter is there, not in the planner).

conventions.json: piece_shape merged (69 hdrs excepts: 33 sys/BZL pieces,
28 narrow packages, 8 specials/mixed; 4 uci excepts: the 4 zstd pieces),
keep_files ["BUILD.bazel"], group_name_map + "sys/opencrypto:
xform_chacha20_poly1305.c": "libsodium" (the layer's piece name; the emit's
regime naming said "xform").

Known follow-ups discovered while reading the layer: the layer's sys/BZL
pieces take STEP RULES as srcs (bzl = [":config", ":vnode_if.c"], vers_c =
[":newvers"], rpctls = [":rpctlscd_gen", ":rpctlssd_gen"]) where the emit
spawns separate pieces per argv regime (bzl/bzl_2/bzl_3/vnode_if_c) —
both spellings compile the same TUs (census: only 2 packages differ, and
those differ only in spelling); the emit's partition is mechanical, the
layer's is convergence. The force_dynamic_hack TU's recorded argv is the
-pico DRIVER line (extra --ld-path/-I tokens the layer's hand-cleaned
piece drops) — extra Bazel flags are tolerated by the asymmetric diff, so
this should pass parity; watched at the proof.

## The per-package piece render (post-compaction work)

The duplicate-libsodium bug: `per_target` plans keyed globally by
`et.name` — two same-named pieces in different packages (sys/opencrypto's
`libsodium` regime and sys/crypto/libsodium's own piece) clobbered one
plan: sys/opencrypto rendered the piece twice, sys/crypto/libsodium lost
its TUs entirely (a parity bug, not cosmetic). Fixed by keying every
piece-scoped table on `(name, package)` (`_plan_key`): `per_target`,
`_gen_quote_dirs`, `_split_piece_of`, `_split_comment`; and the piece
NAMING is per package too (`_split_used_global` → per-package used sets
— a Bazel name is one package's; the layer's sys/isa and sys/x86/isa are
both `isa`). One pinned-name guard: a pinned name another regime of the
same package already took falls through to the component rule. All
generic; committed fdccd6a (131/131 suites, check-invariants OK, corpus
37/37 converged).

piece_shape v5: the generator now records `[]` for pieces with NO
additional_compiler_inputs (the absence is a fact, not a fallback to the
ACI7 default — the v4 generator skipped uci-None pieces and their
renders fell back to ACI7). 190 pieces / 136 packages, 71 hdr excepts
(narrow 32), 75 uci excepts.

Conventions `style` feature landed earlier in the session (the emit's
attr order / list style / comment template match the layer's templated
package comment). conventions.json now: piece_shape v5, keep_files
["BUILD.bazel"], style, group_name_map, supply/rule_supply (the
supply-flag drop: `-Isys/contrib/ck/include` etc. are the layer
toolchain's own KERNEL_DIR_COPTS), conv.supply from the probe
(freebsd-bazel-probe.json — which is NOT committed in the layer; the
install copy needs it — report finding).

## The delta taxonomy (canonical rule-set census, 168 identical / 11)

Strip census now 136 identical / 43 differing (the differing residue is
attr/list ORDER and comment placement — the canon census is the real
measure). 11 substantive files:

1. **sys/BZL** — the 2459-line structural (link rule + step rules +
   bzl/bzl_2/bzl_3 per-argv-regime pieces vs the layer's step-rule srcs).
   Biggest remaining; untouched this session.
2. **hand piece splits** (sys/net rtsock, sys/netinet raw_ip, sys/rpc
   svc, sys/crypto sha1) — argvs identical, link positions contiguous;
   mechanically unjustified, accepted (install re-partitions to regimes).
3. **redundant layer flags dropped by emit** (class B, parity must
   confirm): `-x assembler-with-cpp` on .S pieces (amd64 locore/
   xen_locore, aesni aeskeys_amd64, kern subr_ticks — Bazel infers it);
   `-Isys/contrib/ck/include` (ck — the toolchain's KERNEL_DIR_COPTS
   carries it); the xz -I trailing slashes; aesni's
   `@kernel_llvm//:clang_builtins` deps (the -isystem resource copt
   covers the headers).
4. **sys/kern kern_headers mechanism** (emit-only): a `kern_headers`
   cc_library with the four textual-include files as textual_hdrs +
   `:kern_headers` deps on some sys/kern pieces (genoffset's among
   them). Pre-existing (in the 2026-10-26 proven emit floor), the
   emit's cross-package textual-include delivery; the layer relies on
   `//:kernel_headers`. Accepted as part of the structural floor.
5. **srcs order** (31 files, class A): emit = reference ld order, layer
   = alphabetical; emit is MORE faithful (the 2026-10-24 measurement);
   self-resolves at install.

## The genoffset demotion chase (a non-bug in the tool)

The new `_respell` in-package file-label demotion did NOT fire for
sys/kern's genoffset piece — instrumented both `_respell` and
`_respell_rule` (A2B_DEBUG_RESP): the label never reaches either.
Cause: **both genoffset pieces are conventions `bootstrap` entries**
(`_pkg_local`, emitted verbatim) — the sys/kern -DOFFSET_TEST piece's
srcs were recorded VERBATIM from the old hand render as
`//sys/kern:genoffset.c`. The fix was a conventions fix, not a tool
fix: the bootstrap entry's srcs now spell `genoffset.c` bare (the
sys/BZL tool piece keeps the cross-package label — correct). Re-emit:
sys/kern spells bare; instrumentation removed; 131/131 suites green.

## The install (05:25)

- Full `//...` build in emit28: GREEN (exit 0, zero errors) — the emit's
  sys tree coheres with the kept hand-written root and the untouched
  non-sys files through `//:kernel` and `//bazel/image:image` (the last
  action, MakefsImage root.img, ~6 min).
- Install by /tmp/install-emit.sh: 139 sys BUILD files compared, 96
  already byte-identical, **43 written**; `freebsd-bazel-probe.json`
  added (the conventions' toolchain_probe is no longer dangling — it is
  now committed as part of the layer). Rollback held open the whole
  time: `git -C $WS checkout -- sys` (not needed).
- Reproducibility check running: emit29 = fresh `cp -a --reflink=auto`
  of the INSTALLED layer, re-emit, then byte-compare the 140 written
  files against the layer — the claim the conventions header will make
  ("the delivered sys BUILD files are the emitter's render") is only as
  good as this check.

## Gates on the installed layer (06:55+)

- Reproducibility check GREEN first: emit29 re-emit = all 139 sys
  BUILD files byte-identical, 0 TODOs; root diverges only in the known
  keep_files surface (501 diff lines, the hand-curated deliverable
  plumbing). Conventions header rewritten to the new truth (the sys
  BUILD files ARE the emitter's render) and JSON-validated.
- PARITY build=GREEN diff=converged errors=0 warnings=105
  artifacts=converged 0 errors, IDIOM 0.0 (rules=404 tus=1425
  genrules=2 dirs=167) — byte-for-byte the released numbers.
- IMAGE outputs staged: kernel 15,328,296 B, root.img 268,435,456 B,
  cd.iso 16,695,296 B (kernel grew ~1.7 KB vs 2026-10-26's 15,326,536 —
  the emit's mechanical piece partition changes object order/size
  slightly; the diff stage and link stage both converged, so the
  bytes moved only where the linker was already free to move them).
- Boot tests running (KVM PVH port 2260, TCG cdboot port 2261);
  HERMETIC queued after (image inputs changed).
- Both boots GREEN on the fresh image (07:00): KVM PVH BOOT-SSH OK 4s
  (FreeBSD 15.1-RELEASE); TCG cdboot BOOT-SSH OK 9s (FreeBSD
  15.1-RELEASE BZL, TSC timecounter present). HERMETIC running.
- Final census: **139/139 sys BUILD files byte-identical** between the
  emit render and the delivered layer. The run's goal — the layer's sys
  tree IS the emitter's render — is achieved; the remaining delta is
  only the keep_files root.

## Run close (07:20)

- HERMETIC OK. All gates green on the delivered tree. Any2bazel worktree
  clean at 1d6c916; layer working tree = exactly the squash set (43 sys
  BUILD files + conventions.json + freebsd-bazel-probe.json, 44 files,
  +3776/−2592). ~8h of budget unused — acceptance passed and no
  remaining idea moves a measured number.
- Verdict: publish: release.
