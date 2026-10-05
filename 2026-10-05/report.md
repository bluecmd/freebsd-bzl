# report — 2026-10-05

## Verdict

**publish: pre-release** — parity is converged with a green build, the
produced kernel boots and answers SSH under QEMU/KVM, IDIOM 38.6 < 100 —
but the release image target (`//bazel/image:image`, the workflow's
deliverable) does not exist yet, so the hermeticity oracle ran against the
kernel target instead of the image.

```
PARITY build=GREEN diff=converged errors=0 warnings=80 artifacts=converged 0 errors
CONVERGED  errors=0  warnings=80
IDIOM score=38.6 rules=175 tus=1155 genrules=83 dirs=136
LINT .: layering=0 structure=4
HERMETIC OK: //:kernel builds in a clean container
BOOT-SSH OK after 4s: FreeBSD 15.1-RELEASE
```

## What the layer is

One commit on top of upstream `release/15.1.0`
(github.com/bluecmd/freebsd-bzl): 34 BUILD/bzl files (~5,400 lines of
BUILD), no other source touched.

- `MODULE.bazel` pins toolchains_llvm 19.1.7 (the LLVM the tree's own
  cross-build pins), rules_cc, bazel_skylib, platforms; `.bazelrc` selects
  the kernel platform (`//platforms:x86_64_kernel`) for the build and the
  same LLVM for the host tools, so every tool the build runs (awk, yacc,
  lex, file2c, rpcgen, config(8), the kernel's clang/ld.lld/objcopy) is
  built by Bazel from the tree or pinned in the module.
- `sys/BZL` is the compile directory: `config(8)` (built from the tree at
  `//usr.sbin/config`) generates the opt_*.h/config.c/env.c/hints.c world,
  the awk generators (one-true-awk, built from the tree) produce the
  bus-interface method files, vnode_if, assym.inc, the vDSOs, wakecode and
  vers.c; ~1155 kernel TUs compile through the same cc toolchain config the
  reference's compiles carry (mined from the recorded reference build).
- `freebsd_kernel_link` replays the reference's `ld.lld` line over the
  loose objects (KernelLink mnemonic, so the differ compares the link), then
  the objcopy endgame `kernel.full → kernel.debug → kernel`.
- Include architecture: the root package owns the kernel sources; the three
  compile-directory include trees (`machine/`, `x86/`, `i386/` symlinks in
  the reference) are `include_prefix` views in `sys/{amd64,x86,i386}/include`
  (the only packages under sys/ that hold no kernel sources — a BUILD file
  elsewhere takes the whole subtree away from the root's globs), and the
  layout-link evidence the differ extracts from their Symlink actions matches
  the reference's `machine -> sys/amd64/include` tokens.

## Parity history (this run)

| round | build | diff | artifacts |
|---|---|---|---|
| 1 (13:16) | GREEN | 2 errors, 80 warnings | 1 error, 1 warning |
| 2 (13:25) | RED (loading) | 219 errors | skipped |
| 3 (14:00) | GREEN | **0 errors, 80 warnings** | **0 errors, 0 warnings** |

Round 1's two errors: `includes_diff` on force-dynamic-hack.c (the views
were outside the aquery pattern's scope) and `link_flags_diff` on kernel.full
(absolute link inputs — fixed in the tool: an absolute bare token on a link
line is an input; commit 605d45f; the joined toolchain-selection spellings
`--sysroot=`/`-B<abs>`/`--ld-path=` dropped symmetrically, commit 6c1786d).
Round 2 was my own regression (see journal); round 3 converged.

The artifact stage compares the ELF deliverables: `kernel.full` (symbols,
SONAME, DT_NEEDED) and `force-dynamic-hack.pico` — both sides agree fully.

The 80 warnings, all accounted for: 71 `generated_tool_diff` + 5
`generated_args_diff` (the reference's recipes run through bmake, recorded
as 57-stage pipelines whose middle stages the extractor cannot attribute;
the Bazel side runs the same generators directly — every generated file's
**content is verified equal**, which is what downgrades these to warnings),
and 4 `extra_tu` (genoffset.c / genassym.c / ia32_genassym.c /
acpi_wakecode.S — the generator build tools' own sources, folded into the
reference's one composite recipe on the capture side, explicit genrule
inputs on the Bazel side).

## Silencing levers (any2bazel.json) and their rationales

- `target_map { kernel.full → sys/BZL:kernel }` — fact: the kernel image is
  produced in the compile directory, the Bazel target lives there too; still
  verified under the new name (symbols/NEEDED compared in the artifact
  stage).
- `codegen.content_ignore_lines` — silence, three entries:
  - `^ \*   /.+\.m$` — makeobjops.awk's banner carries the input's absolute
    path, which differs by construction between the sandbox trees.
  - `^#define SCCSSTR ".*$` and `^#define VERSTR ".*$` — newvers.sh's
    version/SCCS strings embed the build date and user@host; a hermetic
    build cannot reproduce them. (vers.c's GIT/RELDATE content is verified.)
- Nothing else. In particular the kernel's `DT_NEEDED` difference was fixed
  in the build, not silenced: the reference passes its `-shared` hack object
  by bare basename (its link runs in the object directory), so the layer
  links it as `-L<dir> -l:force-dynamic-hack.pico` — ld.lld records the
  searched name in DT_NEEDED, and both artifacts now carry the identical
  entry (this also removed the earlier `needed_unused` warning).

## Disclosure: what the layer does not reproduce

- **CTF data**: the reference runs ctfconvert on every object and ctfmerge
  at the link. The capture records neither with attributable argv/outputs,
  so parity cannot check them and the layer does not run them. The kernel
  boots and links identically without the CTF sections; flagged for the
  owner in case CTF bytes matter.
- **Modules**: none in the reference (`MODULES_OVERRIDE=`), none in the
  layer — the boot kernel is the deliverable, as in the reference.
- **The release image** (`//bazel/image:image`): the kernel and the link
  endgame are the layer's deliverables; the UFS root disk is currently made
  by `image/make-rootdisk.sh` with the reference build's bootstrapped makefs
  (`ref/*/tmp/legacy/usr/bin/makefs`) over a base.txz subset. For the image
  target to be hermetic, makefs must be built by Bazel from the tree
  (~45 TUs: makefs core + ffs/cd9660/msdos/zfs + mtree + libnetbsd, all
  against the tree's host-compat headers) — not attempted within this run's
  budget. Worse, the reference's own makefs build was not hermetic: its
  compiles took `-I/home/linuxbrew/.../libarchive/include` from the host
  (makefs's tar/mtree support links a host libarchive), so the layer would
  also have to build libarchive from `contrib/libarchive` (~50 more TUs).
  The hermeticity oracle was therefore run against the kernel target
  (result below).

## Structure findings (build_lint) — why they stay

0 layering findings. 4 structure findings, all one shape: `kernel_headers`
(catch-all) and the three whole-`sys` globs (`kernel_headers.hdrs`,
`config_inputs.srcs`, `sys_headers.srcs`). A kernel is one include surface:
its 1155 TUs include across subsystem boundaries freely (the reference's
`-I$(S)` plus the config-generated opt_*.h world), and `sys/conf/files`
selects sources tree-wide, so any partition of the header globs would split
the surface the compiles actually see. `config_inputs`/`sys_headers` stage
the config(8) and generator inputs wholesale for the same reason. No further
change keeps parity.

## Hermetic + boot (acceptance)

- **Hermetic**: `hermetic-build.sh` (clean ubuntu-24.04 container, layer
  mounted read-only, fresh output base, only the runner's base apt set) —
  **HERMETIC OK: `//:kernel` builds in a clean container** (1635 actions,
  all processwrapper-sandboxed, 456 s wall from a cold cache; no host
  tool, no `$ROOT/llvm`, no reference tree reached into). `HERMETIC_TARGET`
  (`//bazel/image:image`) could not run: the target does not exist (above).
- **Boot**: `boot-ssh-test.sh --kernel <layer kernel> --disk <UFS root>
  --append vfs.root.mountfrom=ufs:/dev/vtbd0` — **BOOT-SSH OK after 4s:
  FreeBSD 15.1-RELEASE** (PVH ELF kernel, virtio-blk root, virtio-net + sshd).
- **IDIOM** 38.6 (threshold 100). The score is dominated by recipe_replay
  (76 findings, weight 0.92): the tree's own generators are driven through
  staged-tree genrules (the awk/vdso/wakecode/newvers recipes need a staged
  compile directory), which is inherently the reference's recipe shape; a
  hand-written build cannot express these generators without staging.
- `.bazelignore`: upstream's googletest and libcbor vendored BUILD files use
  rule names Bazel 9 rejects (un-loaded builtins), which broke the
  workspace-wide query `build_lint`/`idiom` run. The layer never builds
  those directories; they are ignored with a comment.

## Verification commands

```sh
PROJECT=freebsd TARGETS='//sys/...' bzl-loop/bin/parity.sh          # the PARITY line above
bzl-loop/bin/hermetic-build.sh freebsd   # TARGET=//:kernel
bzl-loop/projects/freebsd/build-image.sh # kernel + root.img into $ROOT/image
bzl-loop/bin/boot-ssh-test.sh --kernel $ROOT/image/kernel \
  --disk $ROOT/image/root.img --append vfs.root.mountfrom=ufs:/dev/vtbd0 \
  $ROOT/keys/id_ed25519 150
```

## Verdict

publish: pre-release
