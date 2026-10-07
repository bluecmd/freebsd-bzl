# plan — 2026-10-07

## Starting state

- PARITY (harness default, TARGETS=//...) build=RED, diff=converged (0 errors,
  118 warnings), artifacts skipped. Last run's report was green only under
  `TARGETS='//sys/...'` (the run explicitly passed it); this run's pre-flight
  ran the default `//...` and the build went red.
- Root cause of the red build (found before writing this plan): `.bazelrc`
  sets `build --platforms=//platforms:x86_64_kernel` blanket. When `//...`
  builds the *host tools* (usr.sbin/config, usr.bin/yacc, usr.bin/rpcgen,
  contrib/byacc, lib/libopenbsd, lib/libc:legacy, tools/build/cross-build)
  as **targets**, they are compiled under the **kernel** toolchain (freebsd
  target triple, no host libc) and clang falls back to /usr/include; Bazel's
  include validation then fails with "absolute path inclusion(s) found"
  (80 compile errors). aquery does *not* apply `build --platforms`
  (only `common`/`aquery` bazelrc lines), so the aquery side analyzes the
  same targets as host compiles and the diff still converges — the build
  and the diff are looking at different configurations of the same targets.
- The other standing gap: `//bazel/image:image` does not exist, so the
  release workflow cannot run and the hermeticity oracle has no release
  target (last run's HERMETIC FAILED line).
- `conventions.json` is missing from the layer (the run description and
  idiom.py's `--conventions` expect it). idiom.py tolerates absence, but a
  re-emit would need it; check what should live there and restore it.

## Goals, in order

1. **Parity green at `//...`** (the harness's default): make the host-tool
   targets express what they are — host tools. Add
   `target_compatible_with = ["@platforms//os:linux", "@platforms//cpu:x86_64"]`
   to the cc targets of the bootstrap-tool packages so the `//...` build
   (which runs in the kernel platform) skips them instead of compiling them
   with the kernel toolchain; they keep building in the exec configuration
   as genrule tools exactly as before. Hand-written layer files, editable.
   Verify: `parity.sh` (default) → build=GREEN, diff=converged, artifacts
   stage runs and converges; also `TARGETS='//sys/...'` must stay green
   (regression check).
2. **`//bazel/image:image`** — the release deliverable:
   - makefs built by Bazel from the tree, following the reference's own
     obj-tools recipe mined from the capture (38 objects: usr.sbin/makefs +
     its ffs/cd9660/msdos/zfs subdirs, sys/ufs/ffs/ffs_tables.c,
     sbin/newfs_msdos/mkfs_msdos.c, contrib/mtree getid/misc/spec,
     contrib/mknod/pack_dev.c, stand/libsa/zfs/nvlist.c; includes
     stand/libsa, sys/cddl/boot, sys/fs/{cd9660,msdosfs}, sbin/newfs_msdos,
     contrib/{mtree,mknod}, lib/libnetbsd; links libnetbsd, libutil,
     libsbuf, legacy, -lresolv -pthread). **No libarchive** — the reference
     makefs links none (its 1357 "linuxbrew" execs are bmake/mandoc/libdwarf
     etc., not makefs); the 2026-10-05 report's libarchive fear was wrong.
   - base.txz fetched as a pinned Bazel repository (sha256
     3768988b151c20f965679062b065c63a977d6bbb9f47fd83695ec2c40790c18f,
     FreeBSD 15.1-RELEASE amd64 base.txz, 164,624,792 bytes) — the one the
     host's image-parts/base was unpacked from.
   - a `freebsd_rootdisk` rule (bazel/rules or bazel/image-local) that
     extracts the needed subset (the ~90 paths the loop's make-rootdisk.sh
     selects, plus its etc edits: rc, ttys, sshd_config additions, the
     committed test_authorized_keys) and runs makefs into a UFS image.
     Extraction tool: python3 (the hermetic oracle's BASE_APT and the GitHub
     runner both have it; its lzma+tarfile read .txz natively) — no PATH tar,
     no host bsdtar. Ownership: makefs `-F` mtree spec with uid=0/gid=0 (no
     `unshare -r` inside a sandbox), spec generated from the staged tree.
   - `image` target = kernel (//:kernel) + root.img; workflow copies
     `bazel-bin/bazel/image/kernel`.
   - Verify: build-image.sh, boot-ssh-test.sh (boot must pass), then
     `hermetic-build.sh freebsd` with TARGET=//bazel/image:image.
3. **Restore conventions.json** (workspace facts the emitter/idiom expect).
4. **IDIOM** with the remaining budget: 38.5, dominated by recipe_replay in
   sys/BZL's staged-tree genrules; attack whatever the detectors list as
   cheap wins without touching parity (which is now the regression test for
   every step).

## Done

- `parity.sh` (no TARGETS) prints build=GREEN, diff=converged, artifacts
  converged, IDIOM < 100; boot-ssh-test passes on the image built by
  build-image.sh; hermetic-build.sh passes on //bazel/image:image.
- report.md current from early on; verdict `publish: release` if boot passes.

## Risks

- base.txz fetch inside the hermetic container needs network (it has
  --network=host; the oracle uses the repository cache mount — first fetch
  must succeed there, 165 MB).
- python3 in the container is 3.12 on ubuntu-24.04; tarfile's `filter=`
  kwarg (3.12 defaults to 'data' which strips ownership) — must pass
  `filter='tar'` explicitly to preserve modes, and uid/gid come from the
  spec anyway.
- The subset list must match what the booted system actually needs; the
  existing host-made root.img (boot proven) is the reference — diff the
  staged trees if boot fails.
