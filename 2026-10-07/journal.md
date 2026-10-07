# journal — 2026-10-07

## Round 0: reading the state (00:02-00:30)

- Last run: parity green under `TARGETS='//sys/...'`, boot proven, hermetic
  OK for `//:kernel`, image target missing (verdict pre-release). Feedback
  echoes that.
- This run's pre-flight parity ran the default `//...` and the build is RED:
  80 "absolute path inclusion(s) found" errors across usr.sbin/config,
  usr.bin/yacc, usr.bin/rpcgen, contrib/byacc, lib/libopenbsd, lib/libc,
  tools/build/cross-build. Bazel version is unchanged (9.2.0, installed Oct
  5 — the last run's own install), the layer tree is unchanged except the
  harness's release.yml tweak, so the regression is *target-set*, not tree:
  last run built `//sys/...`, this run builds `//...`.
- Root cause: `.bazelrc` sets `build --platforms=//platforms:x86_64_kernel`.
  Host tools as genrule tools build in the exec config (host platform, LLVM
  toolchain) and are fine; built as *targets* under `//...` they get the
  kernel toolchain (freebsd triple), clang falls back to /usr/include, and
  Bazel's include validation rejects the absolute inclusions.
  `bazel aquery` does not apply `build`-scoped .bazelrc options (only
  `common`/`aquery`), so the aquery side analyzed //usr.sbin/config:config
  as x86_64_host-opt-exec — that's why the diff still converged while the
  build is red. Fix: declare the host tools linux-only
  (target_compatible_with), so the kernel-platform `//...` build skips them;
  they still build in the exec config as genrule tools.
- Model scope confirmed: model.capture.json has 3 targets (<unlinked>,
  force-dynamic-hack, kernel.full) — the bootstrap tools are NOT in parity
  scope; they exist in the layer only to build the kernel generators.
- makefs facts mined from the capture: the reference builds makefs in the
  obj-tools stage, 38 objects, no libarchive at all (its link line:
  `-lnetbsd -lutil -lsbuf -legacy -lresolv -pthread`; the 1357 "linuxbrew"
  execs in the capture are bmake/mandoc/libdwarf — the 2026-10-05 report's
  "makefs links host libarchive" was wrong). Recipe in plan.md §2.
- base.txz: image-parts/base.txz sha256
  3768988b151c20f965679062b065c63a977d6bbb9f47fd83695ec2c40790c18f,
  164,624,792 bytes, FreeBSD 15.1-RELEASE amd64 (dl.log just says DL-OK).
  Plan: pinned http repository + python3 (lzma/tarfile) extraction, uid/gid
  forced to 0 via a makefs `-F` mtree spec (no unshare inside the sandbox).
- conventions.json missing from the layer (idiom.py's --conventions path);
  must restore.

Plan written to runs/2026-10-07/plan.md; report.md stubbed.

## Round 1: parity green at //... (host tools declared linux-only) (00:40-01:00)

- Added `target_compatible_with = ["@platforms//os:linux", "@platforms//cpu:x86_64"]`
  to the 13 cc targets of the host-tool packages (lib/libc:legacy,
  lib/libopenbsd:openbsd, tools/build/cross-build {nbtool,bitcount,progname},
  usr.bin/awk x2, file2c, lex, m4, rpcgen, yacc, usr.sbin/config:config),
  each with a one-line comment: a host tool is only really built in the exec
  configuration, as a genrule tool.
- Behavior check first: an explicit `bazel build //usr.sbin/config:config`
  (or package wildcard `//usr.sbin/config`) still hard-errors with
  "incompatible and cannot be built, but was explicitly requested"; the
  recursive wildcard `//usr.sbin/...` and `//...` skip incompatible targets
  silently (4 targets analyzed for //usr.sbin/...). parity.sh's default
  TARGETS is `//...`, so it is unaffected.
- Result: **PARITY build=GREEN diff=converged errors=0 warnings=118
  artifacts=converged 0 errors** (artifact stage: kernel.full 13701/13701
  symbols, force-dynamic-hack.pico OK). IDIOM 38.5 (tus 1315, dirs 152 — the
  host tools no longer ride the kernel platform, so 80 kernel-side TU
  ghosts are gone from the //... aquery).

## Round 2: the makefs stack (01:00-01:40)

- Goal 2's first half: get `//usr.sbin/makefs:makefs` building as a host
  cc_binary. The hard part was include topology, mined from the reference's
  capture (ref.capture.ndjson Exec records for ffs_subr.c / subr_sbuf.c):
  the reference's makefs and libsbuf compiles have **no blanket -Isys** —
  each kernel-tree backend got its own directory (-Isys/fs/msdosfs,
  -Isys/fs/cd9660, -Isys/cddl/boot, -Istand/libsa, -Isbin/newfs_msdos,
  -Icontrib/{mtree,mknod}), and the shim order is legacy, linux, common
  (order matters: the param/types shim chain include_next's through it and
  with -Isys on the path it falls into the *kernel's* sys/param.h).
- So: `//:makefs_includes` in the root BUILD (an include-surface cc_library,
  include paths may only be set by the owning package — no BUILD files may
  appear under sys/, contrib/, stand/, sbin/ without un-globbing the root
  package's kernel sources); libsbuf compiles the two kern sources against
  the shims alone (no kernel_headers dep); makefs deps the interface lib
  first, shims last.
- `cross-build:nbtool` grew an include/legacy/ dir: the reference's
  tmp/legacy/usr/include stand-in for the curated kernel headers the
  bootstrap installs there — sys/* (sbuf, tree, queue, bitstring, ... 34
  entries incl. disk/), ufs/{ufs/{dinode,dir},ffs/fs}.h, fs/msdosfs/*.h,
  vis.h, err.h, bitstring.h, getopt.h (the getopt shim's include_next
  targets it so the __freebsd_getopt renames get declared). Copied from the
  tree's own headers, which is what the reference's legacy tree contains.
- makefs's link filled in the rest of the reference's tools-build
  liblegacy.a in lib/libc:legacy (err/setmode/strtofflags/flsll, vis+unvis,
  pwcache, fparseln; -D__DBINTERFACE_PRIVATE, HAVE_VIS=0/HAVE_SVIS=0) and
  two cross-build compat libs (progname; new fgetln = fgetln+fgetwln
  fallbacks). Two genrule-stub fixes: legacyinc/sys/_types.h now carries
  __va_list and __sbintime_t (the shim's _types.h is what the reference
  resolved, but the stub shadows it).
- **makefs builds and works**: smoke test produced a valid FFSv2 image
  (`file` says "Unix Fast File system [v2] ... volume name root").
- Regression gate re-run after the host-tool BUILD churn:
  **PARITY build=GREEN diff=converged errors=0 warnings=128
  artifacts=converged 0 errors, IDIOM 38.4** (38.5→38.4, noise-level).
- Round 2b: //bazel/image (:kernel copy genrule, :rootdisk genrule running
  the checked-in bazel/image/make-rootdisk.py, :image filegroup) + @freebsd_base
  repo rule (pinned base.txz URL+sha256, use_repo_rule in MODULE.bazel).
  authorized_keys = the loop's throwaway test key (its private half is the
  repo secret TEST_SSH_KEY release.yml boots with); rc = the loop's /etc/rc.

## Round 3: image GREEN, boot proven (01:40-02:30)

- rootdisk's remaining failure was mtree spec syntax, two of them: the root
  entry was missing ("missing directory in specification ... failed at line
  2" → added ". type=dir ..."), then python's `oct()` renders `0o555` and
  makefs rejects it ("cannot set file mode `0o555'") → `format(m, "04o")`.
- **//bazel/image:image GREEN** (kernel copy genrule + rootdisk genrule:
  70 base files + 38 shared libraries from the pinned base.txz, FFSv2 256MB,
  "Unix Fast File system [v2] ... volume name root"). Bazel-built makefs
  populates the disk end to end.
- **boot-ssh-test.sh: BOOT-SSH OK after 3s: FreeBSD 15.1-RELEASE** with
  vfs.root.mountfrom=ufs:/dev/vtbd0 — the Bazel kernel + Bazel root disk
  boot and accept SSH. (One false alarm: I passed the ssh key by the wrong
  path the first two times — `keys/id_ed25519` relative to the loop dir
  instead of $ROOT/keys — so the probe failed with a perfectly good image.
  Confirmed by booting a debug image with `sshd -d` on the console: it came
  up instantly, and the real image passed immediately after.)
- Hermetic run launched (TARGET defaults to //bazel/image:image from
  project.env).  Idiom conventions.json still missing; next.


## Round 4: genrule replay -> awk_generate rule (02:35-)

- IDIOM 38.4 was dominated by replay-y detectors on the 61 kernel codegen
  genrules (56 makeobjops pairs + vnode_if + acpi_quirks). Replaced all of
  them with `bazel/rules/kernel_generator.bzl`: `awk_generate` (rule class
  AwkGenerate, one action per output, tool = //usr.bin/awk:awk built by the
  layer) + the `makeobjops` macro. sys/BZL/BUILD.bazel: 28 makeobjops calls,
  2 explicit awk_generate (vnode_if 4 outputs, acpi_quirks), 11 genrules left
  (config, newvers, assym/offset, acpi_wakecode, vdso, rpctlss*).
- Two content traps on the way:
  1. `attr.output()`/file-label addressing failed ("missing input
     //sys/BZL:acpi_if.c") -> declare_file outputs are not label-addressable;
     switched to `attr.output_list` predeclared outputs + a `modes` dict.
  2. Provenance line: awk stamps the source path it was GIVEN into
     ` *   <path>.m`. makefiles passed absolute; content_ignore_lines drops
     the absolute form, so the rule names the source `$PWD/<path>` like the
     genrule it replaced. First version passed it relative -> 61-line content
     mismatch ("stale" on-disk outputs from the pre-fix build had the
     relative line; the rebuilt ones verify).
- Models/env wiring for the new rule class: `codegen.mnemonics` += AwkGenerate
  in models/kernel/any2bazel.json (config.py reads it, "not a code change"),
  `EXTRA_MNEMONICS` in projects/freebsd/project.env now also carries
  AwkGenerate so parity.sh's aquery filter captures it. Note: parity.sh's
  fixed filter is narrower than extract_bazel.py's design (its consumption
  rule catches unknown codegen mnemonics from the config) — recommend the
  shared script read the mnemonic set from the project's any2bazel.json.
- Full rebuild //... rc=0; full parity gate re-running.
- Diff converged after widening the provenance ignore-line: the bazel-side
  line gets rewritten by _key_argv_echoes to the input's logical key
  (`sys/kern/bus_if.m`), which `^ \*   /.+\.m$` (absolute-only) missed while
  the cmake side's absolute line was dropped -> 1-line asymmetry, 56 content
  errors + 56 tool errors. `content_ignore_lines` entry widened to
  `^ \*   .+\.m$` (any spelling of the provenance path) in
  models/kernel/any2bazel.json -> **errors=0, 128 warnings** (identical
  warning set to the pre-refactor baseline; the 71 tool/pipeline diffs
  downgraded to warnings exactly as G3's rule promises once content
  verifies).
- **HERMETIC OK: //bazel/image:image builds in a clean container** (40.6s,
  283 actions after cache warmup) — over the post-refactor tree.
- IDIOM work, second wave: the 15 recipe-replay genrules became domain rules.
  `bazel/rules/kernel_steps.bzl`: gen_offsets (genassym/genoffset over the
  compile-products archive), rpcgen_xdr (one action per .x output), newvers
  (newvers.sh + the make -V shim), vdso_image (the *_vdso.sh drivers),
  acpi_wakecode (objcopy/nm/file2c pipeline), kernel_config (config(8) over
  sys/amd64/conf/BZL). `bazel/rules/yacc_lex.bzl`: yacc_generate (m4_parser,
  awkgram, config's grammar), lex_generate (config's scanner). Each rule runs
  the tree's own drivers with the tree's env; the rule is the build step, not
  a copied recipe. force-dynamic-hack.c became write_file(content=[]);
  proctab stays a genrule but its pointless $$PWD env staging is gone.
- Remaining genrules after this: 9 (legacyinc, parse_h, skel, rpc_types,
  bitcount_copy, kernconf, proctab, image kernel+rootdisk) -- all marker-free
  simple steps.
- **PARITY converged with the domain rules: errors=0, warnings=132,
  artifacts=converged; IDIOM 27.4 -> 10.3** (recipe_replay 15 hits -> 0;
  env_replayed 36 names -> 2 (SRCDIR/V, flex skel); shape_duplicates 4 -> 1
  (the two mkdir+cp copies)). packages_vs_dirs (8.8/10) now dominates: 20
  packages for 167 source directories -- one kernel package (sys/BZL) is the
  layout; splitting it per-directory means 100+ BUILD files and re-labeling
  every source reference. Assessed as a trade-off, not the next move.
- Copy-shaped genrules became copy_file (bazel_skylib, already a dep):
  lex parse_h, rpcgen rpc_types, cross-build bitcount_copy. flex's skel
  genrule: env staging inlined away (command substitution), like proctab.
- **PARITY round 7: errors=0 warnings=132 artifacts=converged; IDIOM 10.3 ->
  8.9** (genrules 24 -> 7; the only detector left above noise is
  packages_vs_dirs 8.8: 20 packages for 167 source dirs, which is the
  one-package-kernel layout).
- **HERMETIC OK** re-run over the final tree (all domain rules in place).
- Boot-gate clarification: projects/freebsd/build-image.sh is the pre-image
  acceptance path (KERNEL_TARGET + the prototype make-rootdisk.sh recipe
  with the reference's bootstrapped makefs) -- it refreshed $ROOT/image but
  its root.img is NOT the deliverable's. Booted the //bazel/image outputs
  directly instead (kernel + root.img from bazel-bin/bazel/image).
- Final state (04:45): PARITY converged (errors=0, warnings=132,
  artifacts=converged), HERMETIC OK, BOOT-SSH OK after 4s over the
  //bazel/image outputs, IDIOM 8.9. Verdict in report.md: publish: release.
- The kernel-package split was evaluated and rejected with a reason: the
  cc_NNN compile-product archives are load-bearing in the verified link
  (composition + order are pinned by the artifact evidence), so a per-dir
  regrouping would break artifact parity -- the guard rail outranks the
  8.8-point packages_vs_dirs term.
