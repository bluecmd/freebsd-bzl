# plan — 2026-10-14

State at start: PARITY GREEN converged (errors=0, warnings=180, artifacts
converged), IDIOM 0.0 (floor, threshold 0.0), HERMETIC OK, boot OK (KVM).
So the score is exhausted as a guide; this run works the owner's feedback
list (2026-10-12), which is about the shape a person reads and the release
gate, not the score.

## The feedback list, in this run's order

1. **The release gate: TCG boot panic** (`panic: TSC not initialized` on
   the GitHub runner, `-accel tcg`). Investigated first (it has blocked
   every release so far), because it is small and unblocks publishing.
   Findings from the local repro (see journal): the panic is the
   INVARIANTS KASSERT at `lapic_init` (local_apic.c:670) firing while
   `tsc_freq == 0`; under TCG nothing can supply the frequency before
   `lapic_init` — QEMU TCG implements no CPUID 0x15/0x16, hardcodes the
   hypervisor leaf level at 0x40000001 (< 0x40000010, so FreeBSD's
   `tsc_freq_cpuid_vm` never reads the frequency leaf), and vmport's GETHZ
   always reports unsupported because TCG sets neither `env.tsc_khz` nor
   `env.apic_bus_freq` (only KVM/HVF/WHPX do). FIRECRACKER also bakes
   `machdep.disable_tsc_calibration=1`, which would even kill the *late*
   PIT calibration on a non-Intel CPU. No QEMU flag fixes it; the
   FIRECRACKER-baked tunable is overridden by KVM's CPUID path under KVM,
   which is why local boots work.
   Candidate fix, "kernel option that boots" in the owner's phrase: a
   TCG-bootable kernel configuration for the runner's boot test (BZL minus
   INVARIANTS/INVARIANT_SUPPORT — the KASSERT is the only blocker; with it
   gone the kernel takes the same path a release kernel takes, late PIT
   calibration... with the baked tunable even that is skipped: the variant
   must also override `machdep.disable_tsc_calibration=0` — verify).
   Validate the hypothesis on the reference build tree first (cheap, no
   Bazel), then build the variant as a Bazel target and boot it under
   `-accel tcg` locally. Report the recipe; the workflow is the owner's.
2. **Warnings 132 → 180** (owner item: explain every class or fix).
   Full accounting in the report.
3. **Repeated copts** (191 targets carry the kernel's compile line): move
   the `-I$(GENDIR)/sys/BZL … -include opt_global.h` block into the
   `kernel_compile_flags` toolchain feature (as Linux did); targets carry
   only their own flags. Parity is the guard (same argv).
4. **Numbered targets** (`cc_001`… × 190): name them after their
   component, variant after its reason. This is emitter work: the names
   must come from the emitter, not a one-off rename, or the next re-emit
   wipes them.
5. **Emitter-reproducibility of the split** (the big item, owner items 1+2
   together): the 2026-10-09 package split was done by a one-off script;
   the layer must be what the tool emits from the capture +
   conventions. Linux's `package_dirs` conventions (now on any2bazel
   main via 034a03f/3e56191) are the template; generalise to FreeBSD's
   shape. This is the run's main effort; items 3 and 4 land inside the
   same emitter pass so the emitted layer is the delivered layer.

## Done means

- Boot under `-accel tcg` locally proven for the boot-test kernel; recipe
  in the report.
- All gates still green: PARITY converged errors=0 (warnings accounted),
  IDIOM ≤ 0.0 threshold, HERMETIC OK, boot-ssh OK (KVM) and now also
  (tcg) for the variant.
- The kernel package BUILD files are emitter output (re-emitting with the
  same conventions reproduces the tree's shape); numbered names gone.
- Tool commits small and suites-green; invariants pass on tool changes.
- Report written early and kept current; verdict at the end.

## Order and budget

15.5 h available. 1 (morning), 2+3, then 4+5 with parity re-runs between
each verified step; hermetic run once the layer settles; boot + tcg boot
at the end.
