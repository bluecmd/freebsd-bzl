#!/usr/bin/env python3
"""Build the bootable CD the TCG boot test loads: cdboot -> /boot/loader ->
/boot/kernel/kernel.

The runner's QEMU has no KVM, and the kernel's PVH entry (the only entry
`qemu -kernel` can use) always adopts xen_pvh_init_ops -- so under TCG the
TSC is never calibrated and the kernel panics "TSC not initialized". The
BIOS boot chain through the loader instead (the 2026-10-14 proof) leaves the
kernel its native init_ops. Same inputs as the root disk: the pinned release
base.txz and the layer's own makefs(8), nothing from the host. The stage
holds /boot from the base system, the layer's kernel at /boot/kernel/kernel,
and a loader.conf with the boot-test settings; makefs(8) lays the El Torito
ISO (the bootimage path resolves against the stage, so the action runs with
the stage as its cwd; rockridge is load-bearing -- without it the loader's
cd9660 driver cannot open any file). Times are zeroed, so the ISO is
byte-stable like the root disk.
"""

import argparse
import os
import subprocess
import sys
import tarfile

# /boot from the base system: the El Torito boot block, the loader and its
# support files. The lua loader is what the release defaults to; the .4th
# files and loader.help ride along because defaults/loader.conf may spell
# them. The loader.conf from the base is NOT staged -- the boot test's own
# settings (below) are the only source.
BOOT_FILES = """boot/cdboot boot/loader boot/loader.rc boot/device.hints
boot/loader.4th boot/loader.help.bios boot/menu.4th boot/menusets.4th
boot/menu-commands.4th boot/screen.4th boot/shortcuts.4th boot/support.4th
boot/version.4th boot/brand.4th boot/brand-fbsd.4th boot/beastie.4th
boot/logo-beastie.4th boot/logo-beastiebw.4th boot/logo-orb.4th
boot/logo-fbsdbw.4th boot/color.4th boot/delay.4th boot/check-password.4th
boot/frames.4th""".split()
BOOT_DIRS = "boot/lua boot/fonts boot/defaults".split()

LOADER_CONF = """# boot test: cdboot -> loader -> kernel; serial console; the root disk
# is the UFS image on vtbd0; keep the TSC calibration the loader env is
# allowed to do (the PVH path cannot -- see the layer's image BUILD).
console="comconsole"
comconsole_speed="115200"
autoboot_delay="1"
vfs.root.mountfrom="ufs:/dev/vtbd0"
machdep.disable_tsc_calibration="0"
"""


class Base:
    """The base.txz's files, looked up by their /-rooted-ish name."""

    def __init__(self, path):
        self.tar = tarfile.open(path, "r:xz")
        self.by_name = {}
        for member in self.tar.getmembers():
            name = member.name.lstrip("./")
            if member.isfile() or member.issym() or member.islnk():
                self.by_name[name] = member

    def find(self, want):
        # the txz lays the real files under usr/ with bin, sbin, lib and
        # libexec as symlinks to their usr siblings; a path that is not a
        # member directly is looked up under usr/. Hardlinks (bin/test ->
        # bin/[, tar type 1) and symlinks (usr/lib/pam_unix.so ->
        # pam_unix.so.6, type 2) resolve through the same aliasing to the
        # regular file behind them.
        for _ in range(8):
            member = self.by_name.get(want) or self.by_name.get("usr/" + want)
            if member is None:
                return None
            if member.islnk() or member.issym():
                link = member.linkname.lstrip("./")
                # hardlinks point through the archive root (bin/test ->
                # ./bin/[), symlinks through the member's own directory
                # (usr/lib/pam_unix.so -> pam_unix.so.6)
                want = link if member.islnk() \
                    else os.path.join(os.path.dirname(want), link)
                continue
            return member
        sys.exit(f"{want}: symlink/hardlink chain does not terminate")

    def write(self, member, dst, mode):
        os.makedirs(os.path.dirname(dst), exist_ok=True)
        with open(dst, "wb") as out:
            out.write(self.tar.extractfile(member).read())
        os.chmod(dst, mode)
        os.utime(dst, (0, 0))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--base-txz", required=True)
    ap.add_argument("--kernel", required=True)
    ap.add_argument("--makefs", required=True)
    ap.add_argument("--out", required=True)
    args = ap.parse_args()

    staging = args.out + ".tree"
    os.makedirs(staging)
    for d in ("dev", "tmp", "var/run", "var/empty", "var/log", "proc"):
        os.makedirs(os.path.join(staging, d), exist_ok=True)

    base = Base(args.base_txz)
    n = 0
    for want in BOOT_FILES:
        member = base.find(want)
        if member is None:
            print(f"cdboot: {want}: not in the base.txz, skipping")
            continue
        mode = member.mode & 0o7777
        if mode & 0o111:
            mode |= 0o111  # a program stays executable even if the tar said 0555
        base.write(member, os.path.join(staging, want), mode)
        n += 1
    # the support directories (boot/lua, boot/fonts, boot/defaults) stage by
    # their members: the tar's regular files whose path sits under one of them
    for want in list(base.by_name):
        if not any(want.startswith(d + "/") for d in BOOT_DIRS):
            continue
        real = base.find(want)
        if real is None:
            continue
        mode = real.mode & 0o7777
        if mode & 0o111:
            mode |= 0o111
        base.write(real, os.path.join(staging, want), mode)
        n += 1
    with open(os.path.join(staging, "boot/loader.conf"), "w") as f:
        f.write(LOADER_CONF)
    os.utime(os.path.join(staging, "boot/loader.conf"), (0, 0))

    # the deliverable kernel, exec bit on, times zero
    kern = os.path.join(staging, "boot/kernel/kernel")
    os.makedirs(os.path.dirname(kern), exist_ok=True)
    with open(kern, "wb") as f:
        f.write(open(args.kernel, "rb").read())
    os.chmod(kern, 0o755)
    os.utime(kern, (0, 0))
    os.utime(os.path.join(staging, "boot"), (0, 0))
    os.utime(os.path.join(staging, "boot/kernel"), (0, 0))

    # makefs resolves the El Torito bootimage path against its cwd, so the
    # action runs from the stage; the ISO lands outside it. The tool's
    # location is relative to the action's cwd (the execroot), so it becomes
    # absolute before the cwd moves.
    r = subprocess.run(
        [os.path.abspath(args.makefs), "-t", "cd9660", "-T", "0",
         "-o", "bootimage=i386;boot/cdboot", "-o", "no-emul-boot",
         "-o", "rockridge",
         os.path.abspath(args.out), "."],
        cwd=staging, capture_output=True, text=True,
    )
    if r.returncode != 0:
        sys.stderr.write(r.stdout + r.stderr)
        sys.exit("makefs failed")
    print(f"cdboot: {n} base files + the kernel, El Torito cd9660")


if __name__ == "__main__":
    main()
