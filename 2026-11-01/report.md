# report — 2026-11-01

*(updated as the run proceeds; verdict at the end)*

## State at run start

PARITY build=GREEN diff=converged errors=0 warnings=105 artifacts=converged,
IDIOM 0.0 (threshold 0.0) — the 2026-10-30 release numbers, re-measured by
the harness. Layer tree clean (0 changed/untracked); tool worktree 1864082,
the exact SHA proven reproducing this layer on 2026-10-30. Feedback file
empty. IDIOM is at the floor with no detector firing; no lever exists below
0. This run is therefore a full gate re-proof — unless the run finds a
failure to work on.

## Obstacle found

/scratch is 100% full (3.9G/500G free; 115G free at the end of the last
run). See journal for triage.

## Journal

journal.md in this directory.

## Results

- **PARITY** (fresh, parity.sh.out): build=GREEN diff=converged errors=0
  warnings=105 artifacts=converged 0 errors; **IDIOM 0.0** (rules=404
  tus=1425 genrules=2 dirs=167) — byte-identical to parity-before.txt and
  to the 2026-10-30 release line.
- **IMAGE**: kernel 15,328,296 B (the release number exactly), root.img
  268,435,456 B; //bazel/image:image cached green, cd.iso staged fresh at
  16,695,296 B (release size).
- **BOOT-SSH OK after 4s: FreeBSD 15.1-RELEASE** (KVM PVH direct, port
  2271) — identical to the release proof.
- **TCG-CDBOOT OK after 5s: FreeBSD 15.1-RELEASE**, TSC(-100) timecounter
  present (port 2272; run-local helper tcg-cdboot.sh carried from the
  10-30 run — shared script still has no --cdrom form).
- **HERMETIC OK** (fresh, hermetic/last.txt rewritten 2026-11-01 00:25):
  //bazel/image:image builds in the clean ubuntu-24.04 container —
  Elapsed 51.2s, 1732 action cache hits + 1 internal action, Critical
  Path 15.4s, nothing compiled from host state. (The one wait task
  watching it was killed at its background time limit; the verdict had
  already landed in last.txt — nothing lost.)
- Emit reproduction stands from 2026-10-30 without a re-run: the (layer,
  tool) pair is byte-identical to what fb31 + the sentinel test proved
  (layer 0 changed files, tool same SHA 1864082).
- Cheap honesty checks: loop `config/BZL` == layer's committed
  `sys/amd64/conf/BZL` (byte-identical); conventions.json keep_files =
  the root BUILD.bazel alone, as amended.

## Environmental note

/scratch is 100% full (3.9G/500G free at run start; ~110G consumed since
the 2026-10-30 run left 115G free). Triage: /scratch/bluecmd holds 197G
(this project 46G: hermetic cache 28G, llvm 8.2G, inputs; bazel-cache 36G
shared output bases; linux-bzl 30G = the sibling loop); ~299G belongs to
other tenants — none of it deletable by this run. The only real space I
could free is the hermetic cache (28G), deliberately kept warm so the
re-proof stays cheap; the stale hardlink emit copies (emit28/emit29)
freed ~0 on removal (cp -al). If a release's gates need more room, the
hermetic cache is the lever: delete it first, the run refills it.

## What changed

Nothing in the layer and nothing in the tool: verification run. All
gates were re-measured fresh on the unchanged 2026-10-30 release tree.

## What is next

Nothing load-bearing. Parity is at the release numbers, IDIOM is at 0.0
(threshold 0.0), the image boots both ways, hermeticity is fresh — no
remaining idea moves a measured number, and no lever exists below the
score floor. Standing asks unchanged (shared loop scripts; this run does
not edit them, per the loop's rules — the working qemu line for the
cdboot form is again in this run dir as `tcg-cdboot.sh`):

- **Runner boot gate (owner item, 4th restatement)**: `bin/boot-ssh-test.sh`
  needs a `--cdrom ISO` form (attach as IDE cdrom, `-boot order=d`, when no
  `--kernel` is given), project.env needs `BOOT_ARGS="--cdrom
  $ROOT/image/cd.iso --disk $ROOT/image/root.img"`, and `build-image.sh`
  should copy cd.iso too.
- Free-port retry in `boot-ssh-test.sh` (the linux loop hit the taken-port
  failure again on 2026-10-31; this run picked an explicit port 2271).

## Verdict

**publish: release.** All gates re-proven fresh this run on the unchanged
2026-10-30 release tree: PARITY build=GREEN diff=converged errors=0
warnings=105 artifacts=converged, IDIOM 0.0 (threshold 0.0 held), IMAGE at
release bytes, BOOT-SSH OK (FreeBSD 15.1-RELEASE, KVM PVH 4s), TCG-CDBOOT
OK (5s, TSC present), HERMETIC OK fresh in the clean container. Nothing
changed in the layer and nothing in the tool; every measurement of this
run matches the release numbers. The acceptance test passes with ~15h of
the 15.4h budget unused, and no remaining idea moves a measured number.
