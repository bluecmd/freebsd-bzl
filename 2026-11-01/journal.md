# journal — 2026-11-01

## Disk triage
/scratch 100% full (3.9G/500G free; last run ended with 115G free).
du of /scratch/bluecmd moved to background (bmzrgv1c1). NOT deleting
anything outside this project; ref/cap/models/src-ref are untouchable.
- du results: /scratch 500G, 496G used, 3.9G free. /scratch/bluecmd = 197G
  (freebsd-bzl 46G of which hermetic 28G, llvm 8.2G, src-ref 2.1G, layer
  2.1G; bazel-cache 36G shared output bases; linux-bzl 30G = sibling loop).
  ~299G belongs to other tenants — untouchable.
- emit28/emit29 (4.2G) removed: they were hardlink copies (cp -al, the
  10-26 lesson), so deleting freed ~0. Stale-scratch cleanup of hardlink
  emit copies is cosmetic only; no real space comes back.
- Real free space I control = hermetic/ 28G (clean-container build cache).
  Keeping it while gates run (build should be cache-hit; nothing changed).
  If HERMETIC must re-run, deleting it first is required anyway (the run
  refills it).
- Proceeding: parity.sh running (bg b4h3a7jqv). No emit-repro re-proof
  this run: the (layer, tool) pair is byte-identical to the pair fb31 +
  sentinel proved on 2026-10-30 (layer 0 changed files, tool same SHA
  1864082) — a re-proof would re-measure identical inputs.

## Gates (fresh this run)

- PARITY: build=GREEN diff=converged errors=0 warnings=105 artifacts=converged
  0 errors; IDIOM 0.0 (rules=404 tus=1425 genrules=2 dirs=167) — byte-identical
  to parity-before.txt and to the 2026-10-30 release line. (parity.sh.out)
- IMAGE: kernel 15,328,296 B (the release number exactly), root.img
  268,435,456 B. //bazel/image:image cached green; cd.iso staged fresh,
  16,695,296 B (release size).
- BOOT-SSH OK after 4s: FreeBSD 15.1-RELEASE (KVM PVH direct, port 2271).
- TCG-CDBOOT OK after 5s: FreeBSD 15.1-RELEASE, TSC(-100) present
  (port 2272; run-local helper tcg-cdboot.sh carried from the 10-30 run).
- Layer and tool trees still clean (0 changed files) — the 2026-10-30 emit
  reproduction (fb31 + sentinel) therefore stands for this exact pair.
- HERMETIC: running in background (b88i06ldw); hermetic/ cache intact from
  the last proof, so it should be mostly cache hits.
- Correction: the earlier hermetic "notification" was the nohup wrapper
  exiting (bash `cmd & echo` returns immediately); the script itself is
  still running — podman conmon alive, apt-get still installing at 00:18.
  Wait for hermetic/last.txt to be rewritten (mtime > Nov 1 00:14).

- HERMETIC OK fresh at 00:25 (last.txt rewritten; container build 51.2s,
  1732 action cache hits + 1 internal, Critical Path 15.4s — everything
  up-to-date, no action had to compile from host state). The earlier
  "completed" notification was the nohup wrapper only; the run finished
  ~21 min after start (apt-get install was the slow part).
- The wait task watching hermetic (bo4l350g0) was killed at its 2h
  background limit; nothing was lost — the verdict had landed before the
  kill and last.txt carries it.
- Cheap checks: loop config/BZL == layer sys/amd64/conf/BZL; keep_files =
  root BUILD.bazel only; layer + tool trees stayed clean all run.

## Final state

All five gates green, all fresh in this run dir. Nothing changed in the
layer or the tool. Verdict: publish: release.
