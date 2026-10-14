# report — 2026-10-14

*(updated as the run proceeds; verdict at the end)*

## State at run start

PARITY build=GREEN diff=converged errors=0 warnings=180 artifacts=converged
0 errors. IDIOM score=0.0 (rules=403 tus=1425 genrules=3 dirs=167) — the
release threshold, which is 0.0 itself. HERMETIC OK and BOOT-SSH OK (KVM)
carried from 2026-10-12. Layer tree clean at d7ef77b8; any2bazel worktree
freebsd-intree at 3e56191 (kbuild-intree merged, so the Linux loop's
`package_dirs` conventions and per-package machinery are in the tool now).

## Plan

plan.md in this directory: this run works the owner's feedback list
(2026-10-12) — the TCG release gate first (it has blocked every release),
then warnings accounting, the repeated-copts feature, and the main effort,
making the kernel package layer emitter-reproducible (numbered target
names die there too).

## Journal

`journal.md` beside this report; TCG gate closed with a validated loader
(ISO) recipe.

## The TCG release gate (owner item 1) — findings

Reproduced locally: `qemu-system-x86_64 -accel tcg -kernel image/kernel …`
panics exactly as the runner does — `panic: TSC not initialized`, KDB
backtrace `lapic_init ← mptable_pci_host_res_init`.

Analysis (probed from the guest's KDB prompt and QEMU source):

- The panic is the INVARIANTS KASSERT at `sys/x86/x86/local_apic.c:670`
  (`cpu_feature & CPUID_TSC != 0 && tsc_freq != 0`): the BSP's
  `lapic_init` runs during MPTable enumeration, *before*
  `start_TSC`/`cpu_initclocks` call `probe_tsc_freq_late()`, so a kernel
  compiled with INVARIANTS panics whenever the *early* probe left
  `tsc_freq == 0`.
- `probe_tsc_freq_early()` needs CPUID leaf 0x15/0x16 or a hypervisor
  frequency leaf. Under QEMU TCG none of them exist:
  - TCG implements no CPUID 0x15/0x16 cases at all (they return zeros; the
    leaves are populated only by KVM/HVF/WHPX from the host CPU).
  - FreeBSD's hypervisor path needs `hv_high >= 0x40000010`; QEMU TCG
    hardcodes the hypervisor leaf level at `0x40000001` (case
    0x40000000: `if (tcg_enabled() && cpu->expose_tcg) *eax = 0x40000001`),
    so `tsc_freq_cpuid_vm()` bails. Probed: guest `vm_guest=1
    (VM_GUEST_VM)`, `hv_high=0x40000001`.
  - The VMware backdoor (`GETHZ`, vmport cmd 45) is reachable — booting
    with `-cpu max,-hypervisor` keeps `vm_guest` at NO so the SMBIOS
    serial path in `identify_hypervisor()` runs, and
    `-append smbios.system.serial=VMware-…` + QEMU's vmport do set
    `vm_guest=VM_GUEST_VMWARE` — but QEMU TCG leaves `env.tsc_khz` and
    `env.apic_bus_freq` at 0 (only KVM/HVF/WHPX set them), so GETHZ
    answers "unsupported" and `tsc_freq` stays 0. `tsc-frequency=…` on the
    CPU sets `env.tsc_khz` but not `env.apic_bus_freq`, so it does not
    change the outcome (probed).
- FIRECRACKER bakes `machdep.disable_tsc_calibration=1` (`sys/amd64/conf/
  FIRECRACKER`), which additionally makes the *late* PIT calibration give
  up on a non-Intel CPU (`tsc_disabled=1`). Under KVM this never matters
  (the early CPUID probe of `-cpu host` wins); under TCG it is fatal even
  for the calibration that would otherwise save the boot *after*
  `lapic_init`.

So no stock-QEMU `-cpu`/`-machine` flag makes the TSC frequency visible
under TCG. The fix is not a CPU flag and not a kernel config change: it is
the **boot path**. See below.

## The TCG release gate — validation, root cause, recipe

Both panic mechanisms of the `-kernel` PVH boot were reproduced locally and
then eliminated by switching the boot path. Everything below was run under
explicit `-accel tcg` (this host *does* have `/dev/kvm`, but every command
here forces TCG; the runner has no KVM).

**Mechanism A (the runner's exact panic, `-kernel` PVH):**
`FreeBSD 15.1-RELEASE` boots PVH via QEMU's `-kernel`; `pv.c:200`
unconditionally adopts `init_ops = xen_pvh_init_ops`. With FIRECRACKER's
baked `machdep.disable_tsc_calibration=1`, `probe_tsc_freq_late()` marks
`tsc_disabled=1` for the non-Intel TCG CPU, `start_TSC()` returns with
`tsc_freq == 0`, and the INVARIANTS KASSERT in `lapic_init()` (SMP block,
`local_apic.c:669`) panics with the runner's exact message
`panic: TSC not initialized`. The string is present in the deliverable
`ref/amd64.amd64/sys/BZL/kernel` and absent from an INVARIANTS-off build —
checked both.

**Mechanism B (with the tunable flipped to 0, `-kernel` PVH):**
the late PIT calibration (`tsc_freq_tc` → `DELAY(100000)`) runs instead,
but under PVH `DELAY` never reaches a working backend: `delay_tc()` needs
`tsc_freq != 0` or a timecounter with `tc_quality > 0` (none exists that
early — the TSC counter registers only `if (tsc_freq != 0)`, i8254 is
quality 0), so `DELAY` falls back to `init_ops.early_delay` =
`xen_delay`, which dereferences `HYPERVISOR_shared_info` — unmapped by
QEMU — and faults. Confirmed by disassembly of a TCGTEST build: the
faulting return address `start_TSC+0xfd` is the `call DELAY` of
`tsc_freq_tc`, entered when `tsc_skip_calibration == 0`; the clean
baked-config boot faulted one DELAY later, in the PCI probe. Under TCG
there is no CPUID 0x15/0x16, the hypervisor leaf is capped at
0x40000001, and vmport GETHZ is unsupported, so the early probe can
never deliver a frequency first.

**The recipe (validated end-to-end, both kernels):** stop using `-kernel`
PVH for the no-KVM boot test and let the BIOS boot chain run instead —
`cdboot → /boot/loader → kernel`. With the native `init_ops`
(`i8254_delay`) `DELAY` works, `probe_tsc_freq_late` calibrates the TSC
against the PIT (`machdep.disable_tsc_calibration=0` must be in effect,
which the loader env provides), and the INVARIANTS KASSERT passes because
`tsc_freq != 0` by the time `lapic_init()` runs (it is called from
`mptable_probe`, after `cpu_startup` → `clock_init()` → `start_TSC()`).

The disk artifacts are ordinary makefs products (no new tools):

- root disk: the same UFS image the release workflow already builds
  (makefs `-t ffs`), attached as a virtio disk → `/dev/vtbd0`.
- boot ISO: `makefs -t cd9660 -o bootimage=i386;boot/cdboot -o
  no-emul-boot -o rockridge cd.iso <stage>` where the stage holds
  `/boot/cdboot` (from base.txz), `/boot/loader` (= `loader_lua`, the
  release loader, hardlinked with `zfsloader`), the loader's support
  files (`loader.rc`, `*.4th`, `lua/*`, `fonts/*`, `defaults/*`,
  `device.hints`), `/boot/loader.conf` with `console=comconsole`,
  `comconsole_speed=115200`, `autoboot_delay=1`,
  `vfs.root.mountfrom=ufs:/dev/vtbd0`,
  `machdep.disable_tsc_calibration=0`, and the kernel at
  `/boot/kernel/kernel`. The bootimage path is resolved against the
  *staging directory* (run makefs with the stage as its working
  directory). Two makefs details cost debugging time and are
  load-bearing: **`-o rockridge` is required** — without it the loader's
  cd9660 driver cannot open any file (plain ISO9660 level-1 names do not
  match; the loader fails with `cannot open /boot/lua/loader.lua`, drops
  to the `OK` prompt, has no working `ls`/`include`, and `boot` ends in
  `can't load 'kernel'`); and the El Torito boot record with
  `bootimage=i386;…;no-emul-boot` is what SeaBIOS chains from
  "Booting from DVD/CD…". The reference legacy makefs and the layer's
  own makefs both support the full option set (verified by building a
  bootable ISO with each; the layer-built makefs is at
  `bazel-out/x86_64_host-opt-exec/bin/usr.sbin/makefs/makefs` in the
  hermetic cache).
- QEMU: `-accel tcg -m 1024 -smp 2 -drive file=root.img,if=none,id=d0
  -device virtio-blk-pci,drive=d0 -drive file=cd.iso,if=ide,media=cdrom
  -boot order=d -serial file:boot.log` (the CD must be on IDE for
  SeaBIOS to El-Torito-boot it; `-boot order=d` makes the order
  explicit), SSH forwarded as usual.

Results, both under explicit `-accel tcg` (scripts and images kept in
`loaderproof/`):

| boot | kernel | outcome |
|---|---|---|
| `-kernel` PVH | BZL (deliverable, INVARIANTS on) | `panic: TSC not initialized` (mechanism A — the runner's gate failure) |
| `-kernel` PVH | BZL + tunable flipped to 0 | fault in the first DELAY (`xen_delay`, mechanism B) |
| cdboot ISO + loader | TCGTEST (INVARIANTS off) | full boot, SSH in; `kern.timecounter.choice`: TSC(-100) i8254(0) ACPI-fast(900) HPET(950) |
| cdboot ISO + loader | **BZL deliverable kernel** | **full boot, SSH in (~10 s TCG)**; `uname -v` = `…BZL`, root `ufs:/dev/vtbd0` mounted, sshd up, getty on ttyu0 |

So the release gate does not need a new kernel configuration at all: the
deliverable kernel boots under TCG as soon as the boot path stops being
`-kernel` PVH. The owner-applied change is to `bin/boot-ssh-test.sh`
(loop script — report only): when `/dev/kvm` is not writable, build the
cdboot ISO from the same staging tree the UFS root disk already comes
from (the recipe above; the two `makefs` details are required), attach it
as an IDE CD with `-boot order=d`, and drop the `-kernel`/`-append` PVH
invocation. The KVM branch can keep `-kernel` PVH unchanged — it is green
today.

Not proven locally (no gpart/makefs GPT path available here): the
hard-disk GPT alternative (`pmbr → gptboot → loader`) was attempted first
and hangs silently in gptboot before its first disk read (a full
virtio-blk read trace shows reads stop after pmbr loads the boot
partition; nothing after). The two suspect causes I found but did not
chase further: the boot partition I synthesized was 64 KB instead of
gpart's 512 KB default (gptldr copies 8×32 KB blocks out of the loaded
image), and some other deviation of my hand-rolled GPT from gpart's
output. The ISO path needs none of this and is the simpler, release-like
shape (it is literally how FreeBSD's bootonly media boots), so I stopped
there.

## What landed

- **Owner item 4 — the repeated copts block folded out of the 190 targets.**
  The block was measured first, not assumed: across all 190 targets that
  request the `kernel_compile_flags` feature (all `cc_per_source_library`
  under `sys/`, 136 BUILD files) the same 7 tokens appear in the same
  relative order, contiguously, every time:
  `-I$(GENDIR)/sys/BZL -Isys -Isys/contrib/ck/include
  -Isys/contrib/libfdt -DHAVE_KERNEL_OPTION_HEADERS -include
  $(GENDIR)/sys/BZL/opt_global.h`. The feedback asked for it in the
  `kernel_compile_flags` toolchain feature — probed with a temporary
  aquery experiment: **make variables do not expand in toolchain feature
  flags** (the literal `$(GENDIR)/sys/BZL` reaches the argv unexpanded;
  `$(GENDIRTEST)` likewise), which is why the block ended up spelled
  per-target in the first place. The toolchain feature's `copts`
  (KERNEL_COPTS) cannot carry it, so the block moved to the next-honest
  place: `KERNEL_DIR_COPTS` in `toolchain/kernel_flags.bzl` (its stale
  `-I$(GENDIR)`/`$(GENDIR)/opt_global.h` spelling — a leftover of the
  cwd-based compile directory — replaced with the real spelling), said
  once and injected by `cc_per_source_library` for every target whose
  `features` requests `kernel_compile_flags` (the same gate the feature
  had; targets that spell their own whole line — realmode, boot — are
  untouched). Targets' `copts` now carry only what distinguishes them
  (`-x assembler-with-cpp -DLOCORE`, `-Werror`, `-fcommon
  -DOFFSET_TEST`, the zstd/libsodium/xz include roots and defines …).
  Guard: aquery before/after — 1652 of 1691 actions keep **byte-identical
  argv and the same action key**; the 39 that differ are exactly the
  `-DLOCORE` targets, where the block moved from after `-DLOCORE` to
  before `-x` (order among `-I` flags, semantically inert: includes are
  presence-compared and sorted/sorted-compared by the differ). Full gate
  after the fold: **PARITY build=GREEN diff=converged errors=0
  warnings=180 artifacts=converged, IDIOM 0.0** — identical numbers to
  the pre-fold state.

- **Owner item 2 — the 190 numbered targets have component names.** The
  feedback named this the first thing to fix; every
  `cc_per_source_library` is now named by a fixed mechanical rule, not an
  index (`cc_003`, `cc_017`, `cc_003_2` → `kern`, `uart_if_c`, `rtsock`
  …). The rule, applied by `rename_targets.py` (run toolbox, in
  runs/2026-10-14), is the rule the emitter is to carry once the
  per-package split convention lands:

  * one source → the source's stem; when the stem is taken by a
    generator of the same name, the stem + extension label
    (`card_if.c` → `card_if_c` beside the `card_if` generator); `_2`,
    `_3` as the last resort
  * several sources → the reason the group exists: its own `-D` defines
    (`-DSUFFIX=_ref` → `suffix_ref`, `ZSTD_HEAPMODE=1` →
    `zstd_heapmode`, a defines slug capped at 24 chars, first define only
    past that), its own `-I` roots (last root's leaf), a shared stem
    prefix (≥ 4 chars), otherwise the directory's own leaf — the
    component
  * the package's only cc target, or its largest plain (`-Werror`-only)
    group, claims the leaf first (`sys/net` → `net` and the second plain
    group `rtsock`)
  * rule labels in `srcs` resolve to their output file first
    (`:newvers` → `vers.c`, so `cc_053` → `vers_c`), and three names the
    rule states poorly are pinned (the emitter will carry them as
    conventions `group_name_map`): `sys/contrib/ck/src` → `ck` (the
    directory's leaf is "src"), `sys/contrib/libb2` → `blake2_ref`
    (defeats the `suffix__ref` slug), `sys/BZL` `cc_053` → `vers_c`

  The complete old→new map is `runs/2026-10-14/rename_manifest.json`
  (190 entries, 136 packages). Label references follow the rename in
  place — `name = "cc_NNN"`, local `":cc_NNN"`, cross-package
  `"//pkg:cc_NNN"`, and prose mentions — so `bazel query //sys/BZL:kernel`
  parses and the kernel closure contains no numbered cc_ label (the
  remaining `cc_` hits in the tree are upstream source files like
  `cc_cubic.c`). Two script bugs were hit and fixed mid-run (references
  resolved before all renames were known; the local-label pass dropped
  the `:`), each restored from the item-4 patch before re-running. The
  renamed layer's doc example (`kernel_steps.bzl`) and one stale
  cross-package comment followed. Full gate after the rename:
  **PARITY build=GREEN diff=converged errors=0 warnings=180
  artifacts=converged, IDIOM 0.0** — the same numbers; a rename of
  target names does not touch argvs, and the differ keys compiles by
  source file, not target name.

## Owner item 3 — the emit path: the split convention is in the tool

The feedback: the layer must be what the tool emits from the capture plus
conventions.json, using the Linux loop's per-directory packages and
kernel-library machinery, with the FreeBSD-specific rules in `bazel/rules/`
kept as the emitter's targets. Two tool bugs were fixed first to make the
probing run at all (`probe_kernel.py --common` still unpacked the module
probe's three-tuple → `ValueError`, commit 10ee78e on freebsd-intree;
`probe_toolchain.py`'s `_compile_view` dropped every non-flag token, so a
feature's `-target <triple>` two-token unit lost the triple and the probed
driver line was unparseable, commit 17fdfc4 — both pre-existing, both now
under tests).

**Conventions** (emit-scratch/conventions.json, next to a fresh
`freebsd-bazel-probe.json`): `per_source_library`
`{"load": "//bazel/rules:cc_per_source_library.bzl"}`, `package_dirs`
(the delivered layer's 136 packages), `toolchain_features`
`["kernel_compile_flags"]`, `toolchain_probe` pointing at the probe. The
probe records exactly what the workspace's cc toolchain supplies with the
feature enabled: the 42 kernel compile flags (`-target
x86_64-unknown-freebsd15.1 -O2 -pipe … -std=gnu17`; 43 flag units, 44
tokens), zero include roots, no injected link dirs — and its flag list
matches `toolchain/kernel_flags.bzl`'s KERNEL_COPTS entry for entry.

**The new tool feature: `package_split`** (commit 7265867 on
freebsd-intree, suites green: emit_build 101/102 — the one failure is the
pre-existing `test_elf_symbols` import-path failure recorded earlier this
run — engine 149/149, idiom 1/1, probe_toolchain 7/7, codegen 21/21,
configure 10/10, build_lint 12/12, build_triage 18/18, triage 6/6,
extract_capture 180/180). Conventions
`package_split = {"targets": ["kernel.full"]}` splits the target's
compiles into one library per (package, flag regime) — the same
(package, flags) split a per-directory build (Kbuild's obj-$(CONFIG) per
directory) gives every target's sources naturally — each rendered as the
layer's `cc_per_source_library` in its own package's BUILD file, the link
keeping the target's name and depending on the pieces whole (`alwayslink`
mirrors the reference's direct-objects link; absolute `//pkg:name` dep
labels, because two packages' cores are both their component's leaf).
The names are the rename rule of owner item 2, applied per package with
the package's plain core claiming the leaf first — so the tool now emits
`sys/kern`: `kern`, `stack_protector`, `subr_ticks`, …, the layer's
names, from the capture.

Three conventions make the naming see what the rules actually see:

* `supply_additive` — a TU argv missing a supply token is not a
  deviation (the differ accepts the toolchain's addition). Measured on
  the model: only 7 of kernel.full's 1149 compiles miss any supply token
  (6 aesni TUs miss `-O2`/`-nostdinc`, `stack_protector.c` misses
  `-fstack-protector`) — all enabled the feature in the layer. Without
  the field, `_deviates` forced every such piece to spell its whole line
  (the kbuild-module safety heuristic mis-aimed at the kernel).
* `rule_supply` — the 7-token block `cc_per_source_library` injects
  (`-I$(GENDIR)/sys/BZL -Isys … -include $(GENDIR)/sys/BZL/opt_global.h`,
  the item-4 fold), invisible to the toolchain probe because a rule adds
  it, not the toolchain. A `$(GENDIR)/`-prefixed token and its
  source-tree twin fold to one unit and a `-include` pair is judged as
  one unit; the naming rule's view of a regime is the argv minus probe
  minus rule_supply — which is why the packages' cores name by their
  leaf (`kern`, `amd64`, `crypto`, `namespace`, `ddb`, `bzl`) exactly as
  the layer does.
* `group_name_map` — the three pinned names (`sys/contrib/ck/src` →
  `ck`, `sys/contrib/libb2` → `blake2_ref`), keyed
  `<package>:<first source>` with the basename fallback.

**Measured name parity** (fresh emit from the committed tool into
emit-scratch/conv-run4; 137 BUILD files; comparison script
emit-scratch/cmp_pieces.py against the layer's rename manifest; conv-run5
from the 94f4c8c tool reproduces the same 119/17): **of
the 136 packages with kernel.full pieces, 119 emit piece names identical
to the delivered layer; 17 differ**, and every difference is classified:

1. **Merged plain regimes** — the emitter groups a package's compiles by
   flag regime, and after subtracting probe + rule_supply some regimes
   the layer keeps separate are argv-identical, so it merges them (the
   compiles are identical, the differ accepts it): `sys/crypto`
   (`sha1` folded into `crypto`), `sys/net` (`rtsock`), `sys/netinet`
   (`raw_ip`), `sys/rpc` (`svc`), `sys/contrib/zstd/lib/decompress`
   (`zstd_heapmode` → its regime names `zstd_d` by the stem), and
   `sys/opencrypto` (the layer's `libsodium`/`opencrypto` pair emits as
   one `xform` regime beside `opencrypto`).
2. **Global-namespace collisions** — the emitter keys targets by name
   globally, so where the layer legally reuses a name in two packages
   (`sys/isa` and `sys/x86/isa` are both `isa`; `acpica` twice; `pci`
   three times) the second claimant takes a fallback candidate (its own
   stem, an alternate leaf): `sys/dev/acpica` emits `acpi`, `sys/dev/virtio/pci`
   emits `virtio_pci`, `sys/dev/zlib` `zcalloc`, `sys/netlink/route`
   `iface`, `sys/nfs` `nfs_diskless`, `sys/x86/acpica` `osdenvironment`,
   `sys/x86/isa` `atrtc`, `sys/x86/pci` `pci_bus`, `sys/xen` `features`.
3. **Codegen-aware split not implemented** — `sys/BZL`: the layer keeps
   single-generated-file pieces (`acpi_if_c`, `acpi_wmi_if_c`, `vers_c`,
   the `*_if` families, and `genassym`/`genoffset` for their separate
   step targets); the emitter folds the generated .c compiles into the
   `bzl` core bucket. The `sys/kern` `genoffset` line is the same fact
   (that target is a separate step target, not a kernel.full piece — a
   comparison artifact).

Honest scope of the measurement: **name parity of the split**, not yet
build parity of the emitted tree. The emitted pieces spell their
regime's copts as `COPTS + [extras]` with the rule-injected block in
`COPTS`, and the include surface (hdrs/deps carriers) is the emitter's
own derivation, not yet the layer's `offset_inc`/`config`/`generated` +
`//:kernel_headers` spelling; the emitted cc_binary still replays the
reference's link line (the link convention, below). The delivered layer
remains the honest build; conv-run4 is the artifact the next run
converges on.

**The emitted tree was then built**, to measure the gap in Bazel's own
words (time-boxed; scratch worktree `emit-tree`, d7ef77b8 + the layer's
diff, with the emitted BUILD files overlaid — recipe in the journal):

* the tree **parses**: `bazel query //:kernel.full` loads all 137
  packages;
* one real emitter bug found and fixed on the way (commit 94f4c8c): the
  hoisted `_RECIPE_ENV` constant was rendered into the root BUILD only,
  while genrules routed into a package (`sys/BZL`'s recipe-replay
  genrules) reference it in their cmd — the package's BUILD died on the
  undefined name. `_package_text` now renders the constant wherever a
  rule's value carries it (test added);
* with that fixed, analysis proceeds until the step rules: the first
  remaining blocker is `//sys/BZL:acpi_wakecode_bin` — the wakecode
  recipe reads `sys/BZL/acpi_wakecode.o`, an object of a compile the
  model does not record (the reference built it in the unrecorded
  bmake bootstrap), and the emitter's own TODO names the missing
  convention (`object_files.load`); the layer implements the same fact
  as the `kernel_steps` rules (`gen_offsets(archive, member)`,
  `acpi_wakecode`). No kernel compile ran yet — analysis aborts before
  any of the ~1100 TUs; that question is answered only after the
  step-rule conventions exist.

So the emitted tree is parse-clean and one bug from the analysis, and
the wall it reaches is exactly the gap the report predicted (step rules,
then the link).

**What is still missing for "the layer is what the tool emits", in order
of size:**

1. ~~**Generators are genrules.**~~ **Landed** (the step-rule
   conventions; the subsection below): the 12 generator steps now emit
   as the layer's `kernel_steps.bzl` / `kernel_generator.bzl` rules —
   39 step rules + 3 bootstrap targets, all in `sys/BZL`, 9 of the 12
   genrules gone, the recorded `*_if` family handled by the committed
   `awk_modes` recipe kind. What remains of this item is the emit-tree
   measurement's residue: the replay genrule's own inputs (the
   `object_files`/`.git` classes named below) and the link.
2. **The kernel link is not reproducible as emitted.** The emitted
   cc_binary's linkopts carry absolute host paths
   (`--ld-path=/scratch/bluecmd/freebsd-bzl/llvm/bin/ld.lld`, a
   `/red/herring` placeholder where the reference's link script path
   was) and TODOs. The layer's answer is the `kernel_link` machinery in
   `bazel/rules/`; the emitter needs a link convention (like Linux's
   `raw_link`) that maps the reference's link line onto that rule.
3. **Per-package name namespaces** (the class-2 collisions) and the
   codegen-aware piece split (class 3), plus a decision on the merged
   regimes of class 1 — accept the merge (compiles identical) or teach
   the naming rule the layer's regime boundaries.
4. **Include-surface fidelity** — the pieces' hdrs/deps carriers spelled
   as the layer's (`offset_inc`/`config`/`generated` + `//:kernel_headers`),
   so the emitted BUILD files are diffable against the layer
   byte-for-byte, not just name-for-name.

**The step rules landed in the tool** (later on the same run date;
commits 5f923b3, 9efe3bb on freebsd-intree; suites emit_build 107/108 —
the one failure is the pre-existing `test_elf_symbols` import-path
failure — build_lint 12/12, artifact_diff 30/30):

* the mapping insight first: the model's 12 Genrule + 211 unrecorded
  ConfigureFile actions map nearly 1:1 onto the layer's `sys/BZL` step
  rules, and the only compiles the capture misses are the bmake
  bootstrap's tool objects (genoffset, genassym, ia32_genassym,
  acpi_wakecode — 4 compiles, not a wall of unknown steps).
* `recipe_kinds` `awk_modes` (5f923b3): the bmake awk step family —
  `awk -f script src [mode]` passes over one (script, input) pair group
  into one `awk_generate` call with `outs` + `modes`. Emitted
  `acpi_quirks` call is byte-identical to the layer's; `vnode_if`
  differs only in list formatting.
* `unrecorded_codegen` entries may carry `attrs` (the rule call's
  spellings) and claim the outs of a RECORDED action: the entry fires
  once at claim-sighting and the action keeps only its unclaimed outs —
  all claimed, the action is not emitted. The 69-output buildkernel
  replay collapses to `kernel.full` alone.
* `bootstrap` convention + entry `pkg` (9efe3bb): the four bootstrap
  tool objects are emitted verbatim from `bootstrap`, pinned to their
  package; a step rule whose outs the rule derives (`makeobjops`)
  names its package because routing cannot see derived outs.
* `rule_supply` is now a real copt drop for the pieces (was only the
  naming rule's view): a per-source piece's copts lose the
  compile-directory block the rule injects (`-Isys/BZL` had no sandbox
  existence under Bazel — `-Wmissing-include-dirs` killed every kernel
  TU), so the emitted kern piece is `copts = ["-Werror",
  "-I$(GENDIR)"]` + the feature, against the layer's `["-Werror"]`.
* conventions (`emit-scratch/conventions.json`, generated by
  `emit-scratch/gen_steps.py` from the model + the layer's own
  spelling): `recipe_kinds`, 39 `unrecorded_codegen` entries with
  attrs, 3 `bootstrap`.

Emit check (conv-run8/conv-run9 in emit-scratch): every step rule +
bootstrap lands in `sys/BZL/BUILD.bazel` — 28 `makeobjops` (name, src)
pairs identical to the layer, `kernel_config` outs/attrs identical, all
outs respelled package-relative; root BUILD TODOs down 227 → 18; only
3 genrules remain in `sys/BZL` (force-dynamic-hack, kernel.debug,
kernel) plus the `kernel_full` replay with `kernel.full` as its only
out.

**The emit-tree question answered** (the emit-tree experiment re-run
with conv-run9; worktree d7ef77b83 + the layer diff + the emitted
BUILDs, plus experiment hand-patches that stand in for the layer's
hand-made surface — the layer's root preamble `exports_files`/filegroup
blocks, a per-package `exports_files(glob(["**/*"]))`, `headers`
filegroups for 91 packages, `kernel_headers`→`pkg_headers` alias + the
three include-tree carriers, the layer's `generated` filegroup list):

* `bazel query //:kernel.full` loads all 137 packages;
* analysis passes ALL step rules — the old wall (`acpi_wakecode_bin`,
  the wakecode recipe reading the unrecorded `acpi_wakecode.o`) is
  gone, the rule extracts its member from the bootstrap archive the
  layer's way;
* real actions run: config(8), rpcgen, the awk steps, newvers execute;
  the bootstrap tool objects compile (genoffset.c, genassym.c,
  acpi_wakecode.S) — once the include-tree carriers are on the -I line,
  which was the include-surface item doing its job;
* the kernel-TU compile sample compiles: the seven packages that
  carry the bulk of the kernel (sys/kern, sys/amd64/amd64, sys/vm,
  sys/netinet, sys/x86/x86, sys/dev/virtio, sys/geom) build green —
  342 actions, 341 compile commands in the sandbox, exit 0. Two walls
  were crossed to get there: the `-Isys/BZL` one (the `rule_supply`
  drop above) and the generated-header surface: `vnode_if.h`
  `#include "vnode_if_typedef.h"` by sibling, so a TU reaching
  `vnode_if.h` needs its sibling outputs too — the per-piece
  `pkg_generated_under_*` filegroups name only the headers the argv
  spells. The layer's answer (every TU can reach the full `generated`
  set) is what the include-surface item converges to; the experiment
  switched the sampled pieces to the full `pkg_generated` carrier.
* the full `//sys/...` tree — every kernel TU the emitter spells,
  ~1170 compile commands across ~135 packages — **builds green, exit
  0** (51s, 1171 actions). To get there the experiment hand-patched the
  two conventions gaps it had already named (experiment-only, standing
  in for the emitter features the next run carries): the full
  `pkg_generated` carrier on every piece, the three clang
  builtin-include pieces of sys/crypto/aesni (the layer's
  `-isystem external/…/resource_include` +
  `@kernel_llvm//:clang_builtins` spelling — the reference's argv never
  spells the resource dir, clang's driver adds it, so only the
  conventions can carry it), and the bootstrap-object duplicates
  deleted. One more conventions gap surfaced by that deletion: the
  emitted `sys/kern` genoffset piece is the PLAIN compile — the
  reference's second genoffset compile (`-DOFFSET_TEST`,
  `-MTgenoffset_test.o`, mirroring the layer's sys/kern:genoffset) is
  nowhere in the emitted tree.
* before those patches the full tree stopped one wall short:
  sys/amd64/acpica compiles `acpi_wakecode.S` a second time — the reference's
  bootstrap tool objects (genoffset, genassym, ia32_genassym,
  acpi_wakecode) come out BOTH as the conventions' `bootstrap` entries
  in `sys/BZL` (the layer's spelling, byte-identical) AND as
  source-package pieces derived from the recorded compiles
  (`sys_amd64_acpica_acpi_wakecode` in sys/amd64/acpica; the genassym
  split back into per-source `sys_*_genassym` cc_libraries — the
  layer merges genassym.c + ia32_genassym.c into one `sys/BZL:genassym`
  target and has no wakecode target in acpica at all). The reference's
  argv backs the layer: two genoffset compiles (plain + `-DOFFSET_TEST`,
  `-MTgenoffset.o` vs `-MTgenoffset_test.o`) mirror the layer's
  sys/BZL:genoffset and sys/kern:genoffset pair exactly. The
  conventions need the `bootstrap` entries to claim their recorded
  compiles — the same suppression the step rules do — so the
  source-package duplicates go away.
* `//sys/BZL:kernel_full` (the replay) analyzes (7058 targets
  configured) and runs to a 13-file missing-input wall, precisely
  named: the 6 `.git` staleness files the reference's in-tree build
  read (Bazel ignores `.git` by default — an input class the emitter
  needs to mark hermetic or drop) and the 7 `object_files.load` `.o`
  files (genoffset, genassym ×2, acpi_wakecode, locore, subr_ticks,
  xen-locore).

## Owner item 5 — the 180 warnings, accounted

The warning count is the same 180 the 2026-10-12 report accounted
(26 + 50 = 76 extra_tu, 9 extra_target, 20 extra_generated, 75
generated_tool_diff — the same four classes, re-verified fresh against
this run's diff.json, which is reproduced with identical numbers by the
post-fold parity gate). None of the four classes is a build defect; all
four are facts of building MORE than the reference's recorded phases
built:

1. **extra_tu ×76** — "source compiled in bazel but not cmake". The
   reference capture records only the kernel phases
   (kernel-toolchain + buildkernel), which consumed the host tools
   prebuilt from the `tmp/legacy` bootstrap. The layer builds those host
   tools from source so the workspace is hermetic, and the differ sees
   their TUs. Where they come from: makefs's own sources (24 —
   cd9660/ffs/msdos/zfs), the flex library behind lex (18), the libc
   pieces host tools share (8: err, setmode, strtofflags, getopt,
   getopt_long, recallocarray, strtonum, flsll), libnetbsd (4),
   tools/build cross-build compat shims (4), mtree (3), libopenbsd (3),
   libc-vis (2), libc-pwcache/mknod/libutil/newfs_msdos/m4 (1 each),
   plus 4 kernel-side bootstrap TUs the reference ran through its bmake
   pipeline instead of recording as compiles (acpi_wakecode.S,
   genassym.c, ia32_genassym.c, genoffset.c) and stand/libsa's nvlist.c.
   Each is a TU the *reference build also compiled* — as part of
   building its bootstrap tools — just not through the recorded phases,
   so the model never saw it.
2. **extra_target ×9** — the executables those TUs serve: `usr.bin/awk
   :awk :maketab`, `usr.bin/file2c:file2c`, `usr.bin/lex:lex`,
   `usr.bin/m4:m4boot`, `usr.bin/rpcgen:rpcgen`, `usr.bin/yacc:yacc`,
   `usr.sbin/config:config`, `usr.sbin/makefs:makefs`.
3. **extra_generated ×20** — generated-outputs the differ sees only on
   the Bazel side, for the same reason (the reference model records the
   kernel phases' outputs only): 9 libc `legacyinc` headers the layer
   materializes with copy_file/write_file where the reference tree
   carries them as checked-in paths, `tools/build/cross-build/sys/
   bitcount.h`, and the parsers' own outputs (awkgram.tab.c/.h,
   lex's parse.h/skel.c, m4's parser.c/.h, rpcgen's rpc/types.h,
   config's config.c/lang.c/y.tab.h).
4. **generated_tool_diff ×75** — all under `sys/BZL`, all "content
   verified" (the differ checked the generated bytes match). 67 are the
   objctools' `*_if.{c,h}` (and their .h twins) whose reference recipe is
   the bmake pipeline (57 recorded `tools/build/make.py` stages) that
   the layer replaces with its one `awk` invocation — the differ asks
   for a `codegen.tool_map` entry to record that intentional swap; 4
   more are the same swap for vnode_if/acpi_quirks; 3 are command
   spellings for the vdso ELF-assembly and newvers scripts (`sh
   sys/tools/amd64_vdso.sh` vs `sh $(pwd)/…`). The 2026-10-12 report
   accounted the same 75 as "compare-phase-only facts, not build facts";
   they are still warnings only because the tool's `codegen.tool_map`
   convention has not been recorded for this project — that is a
   tool-side config edit (`any2bazel.json`), listed in What remains.

The 132 → 180 delta between 2026-10-07 and 2026-10-12 is therefore not a
regression that appeared after the fact: 50 of the 76 extra_tu are the
2026-10-12 host-tool split's moved piece sources (the pre-split tree had
them as prebuilt bootstrap inputs, not compiles), 9 extra_target are its
nine executables, and the 20 extra_generated/75 generated_tool_diff are
the corresponding generator facts. The split was the 2026-10-12 owner
item; the warnings are its honest bookkeeping.

## Results

* **PARITY** build=GREEN diff=converged **errors=0 warnings=180**
  artifacts=converged — the same numbers the run started with,
  re-verified fresh after the item-4 fold and the item-2 rename (a
  rename of target names does not touch argvs; the differ keys compiles
  by source file). The four warning classes are accounted in the item-5
  section; none is a build defect.
* **IDIOM 0.0** (rules=403 tus=1425 genrules=3 dirs=167) — the release
  threshold, which is 0.0 itself.
* **HERMETIC OK** — `//bazel/image:image` builds in a clean container
  with the workflow's apt set (`hermetic-final.txt`).
* **BOOT-SSH OK (KVM)** — re-run at the end of the run against the
  deliverable kernel and UFS root disk, exit 0 (`boot-ssh-final.txt`).
* **TCG release gate — solved** (owner item 1): root cause and the
  validated cdboot-ISO recipe are in the item-1 sections above; the
  deliverable kernel boots and accepts SSH under `-accel tcg` with it.
* **Owner items 2 and 4 landed in the layer** (190 numbered targets
  renamed by rule; the repeated copts block folded), each with a full
  gate re-run showing identical numbers.
* **Owner item 3 advanced from staged to committed in the tool**: the
  `package_split` convention (with `supply_additive`, `rule_supply`,
  `group_name_map`) is in emit_build.py on freebsd-intree, commit
  7265867, suites green, and the fresh emit reproduces the layer's
  split names for 119 of the 136 packages, with all 17 differences
  classified (item-3 section). Later in the run the step-rule
  conventions landed too (commits 5f923b3 `awk_modes`, 9efe3bb the
  claim + package-pin + bootstrap mechanisms, a92a2b0 the
  `rule_supply` drop for the pieces, 5d2ac30 the `builtin_include`
  resource-dir surface for the intrinsics pieces, 22097d6 the
  `generated_header_includes` reach closure — on the real model all 58
  per-piece carriers in sys/BZL now carry the vnode_if trio they were
  missing), and with them the
  emitted tree moved from "parses" to "compiles": analysis passes
  every step rule; config(8), rpcgen, the awk steps, newvers and the
  bootstrap tool objects execute for real; the kernel-TU sample — the
  seven packages carrying the bulk of the kernel — builds green, 342
  actions / 341 compile commands, exit 0; and with the two named
  carrier gaps hand-patched in the experiment tree, the FULL
  `//sys/...` tree builds green: 1171 actions, ~1170 kernel-TU compile
  commands across ~135 packages, exit 0 (item-3 section, "The
  emit-tree question answered").

## What remains

* **The emitted tree compiles all its kernel TUs; what is left is the
  bootstrap objects and the link.** The step rules are closed (item-3
  section, "The step rules landed in the tool") and both carrier
  surfaces the TU compiles needed are committed tool features:
  conventions `builtin_include` (5d2ac30 — the reference argv never
  spells clang's resource dir, its driver adds it, so the conventions
  name the intrinsics sources and the piece gets the layer's
  `-isystem external/…/resource_include` +
  `@kernel_llvm//:clang_builtins`; the emitted aesni package builds
  green with it) and conventions `generated_header_includes`
  (22097d6 — a generated header is not on the emitter's disk, so the
  reach walk cannot follow its own include lines; the conventions
  spell the edges and the reach closes over them; all 58 per-piece
  carriers in sys/BZL now carry the vnode_if trio). With the two hand
  patches that stood in for those features plus the bootstrap-object
  duplicates deleted, the full `//sys/...` tree builds green — 1171
  actions, ~1170 kernel-TU compile commands across ~135 packages, exit
  0, 51s.
* **The next wall: the bootstrap tool objects.** The conventions'
  `bootstrap` entries emit the layer's four `sys/BZL` targets
  verbatim, but the recorded compiles also come out as source-package
  pieces (`sys_amd64_acpica_acpi_wakecode` in sys/amd64/acpica; the
  genassym pair split back into per-source `sys_*_genassym`
  cc_libraries where the layer merges them into one `sys/BZL:genassym`).
  Closing it needs the `bootstrap` entries to claim their recorded
  compiles (the same suppression the step rules do) plus the
  plain/`-DOFFSET_TEST` genoffset pair routed as the layer spells it
  (sys/BZL plain, sys/kern test) — the reference's argv backs both
  spellings (two genoffset compiles, `-MTgenoffset.o` vs
  `-MTgenoffset_test.o`), and the emitted tree has no `-DOFFSET_TEST`
  compile anywhere today.
* The kernel link convention (the emitted cc_binary replays the
  reference's absolute-path link line), `object_files.load` (the replay
  genrule's 7 `.o` inputs; the layer has no `cc_object_files.bzl` — its
  answer is the step rules themselves) and the 6 `.git` staleness
  inputs Bazel ignores, per-package name namespaces + codegen-aware
  piece split, and the merged-regime decision (item-3 section, classes
  1–4) — in that order after the bootstrap claims.
* **`codegen.tool_map`** — the 67 of 75 `generated_tool_diff` warnings
  that are the intentional `*_if` bmake→awk swap wait on that tool-side
  config entry (`any2bazel.json`); the remaining 8 are command spellings
  for the vdso/newvers scripts.
* **The GPT loader path** (`pmbr → gptboot → loader`) stays parked: it
  hangs silently in gptboot before its first disk read here, and the
  validated cdboot-ISO recipe makes it unnecessary for the release gate.
* Nothing further on the delivered layer itself: main is `release/15.1.0`
  + the one Bazel layer commit, all gates green against it.

## Verdict

**publish: release.** The standing goal holds — main is the base tag plus
the one Bazel layer commit; parity converged at 0 errors / 180 accounted
warnings; idiom at the 0.0 floor; hermetic and boot-ssh both green; and
the release gate that has blocked every release so far (TCG) is solved
with a validated recipe the owner can apply to the workflow. Owner items
2 and 4 are landed and gate-verified; owner item 3 is no longer staged —
the split convention is a committed tool feature with measured name
parity (119/136, all differences classified), and this run also landed
the step-rule conventions and the two carrier surfaces — the emitted
tree now passes analysis at every step rule, its kernel-TU sample
builds green (341 compile commands), and with the last carrier gaps
stood in by hand in the experiment tree the FULL `//sys/...` kernel-TU
tree compiles green (1170 commands, exit 0). The honest
remainder (build parity of the emitted tree: bootstrap-object claims,
the link convention + `object_files.load`/`.git` inputs) is the next
run's work, measured to the file.
