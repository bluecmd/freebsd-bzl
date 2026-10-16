#!/usr/bin/env python3
"""Populate the test root disk from the release base.txz and build its UFS image.

The loop's make-rootdisk.sh prototype, as a Bazel action: the subset of the
base system a boot test needs (init, sh, the rc's commands, sshd and its
libraries), the /etc the boot needs, the loop's /etc/rc and the test key
authorized for root -- then makefs(8) from the tree lays the FFSv2 image.
Everything in the image is root's (uid/gid 0) without chown(2), which a
sandboxed action cannot do: the metadata rides a makefs -F mtree spec that
covers every entry. -T 0 and zeroed file times keep the image byte-stable.
"""

import argparse
import os
import subprocess
import sys
import tarfile

# the programs: init and the rc's commands, sshd and what it execs
PROGRAMS = """sbin/init bin/sh bin/cat bin/ls bin/mkdir bin/echo bin/hostname bin/uname bin/sleep bin/ps bin/kill bin/test bin/pwd bin/cp bin/mv bin/rm bin/ln bin/chmod
sbin/ifconfig sbin/route sbin/mount sbin/mount_tmpfs sbin/umount sbin/sysctl sbin/reboot sbin/shutdown sbin/mdconfig
usr/sbin/sshd usr/libexec/sshd-session usr/libexec/sshd-auth
usr/bin/uname usr/bin/ssh-keygen usr/bin/true usr/bin/false usr/bin/id usr/bin/env usr/bin/login usr/bin/su usr/bin/passwd usr/bin/head usr/bin/tail usr/bin/grep usr/bin/sed usr/bin/awk usr/bin/vi usr/bin/less usr/bin/top usr/bin/netstat usr/bin/uptime usr/bin/w
usr/libexec/getty libexec/ld-elf.so.1""".split()

# the account database (root, pubkey login only), the ssh server config, terminals
ETC = """etc/master.passwd etc/passwd etc/pwd.db etc/spwd.db etc/group etc/login.conf etc/login.conf.db
etc/gettytab etc/termcap.small etc/ssh/sshd_config etc/ssh/moduli etc/services etc/protocols
etc/hosts etc/resolv.conf etc/shells etc/pam.d/sshd etc/pam.d/login etc/pam.d/system
etc/pam.d/other""".split()

# the pam modules sshd links beside libpam.so, and the termcap file getty prints with
EXTRAS = "usr/lib/libpam.so usr/lib/pam_* usr/share/misc/termcap".split()

BIN_DIRS = ("bin", "sbin", "usr/bin", "usr/sbin", "usr/libexec", "libexec")
LIB_DIRS = ("lib", "usr/lib", "usr/lib/private")

TTYS = "console\tnone\t\t\t\tunknown\toff secure\nttyu0\t\"/usr/libexec/getty std.115200\"\tvt100\tonifconsole secure\n"


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
        # libexec as symlinks to their usr siblings; the image gets real
        # directories at the conventional paths (the prototype booted with
        # this layout), so a path that is not a member directly is looked
        # up under usr/. Hardlinks (bin/test -> bin/[, tar type 1) and
        # symlinks (usr/lib/pam_unix.so -> pam_unix.so.6, type 2) resolve
        # through the same aliasing to the regular file behind them.
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


def needed_libs(readelf, path):
    """llvm-readelf --needed-libs: the DT_NEEDED names of one FreeBSD binary."""
    out = subprocess.run(
        [readelf, "--needed-libs", path], capture_output=True, text=True
    ).stdout
    # llvm-readelf prints a "NeededLibraries [" header, then one bare name
    # per line (GNU readelf brackets each name)
    return [
        line.strip().strip("[]")
        for line in out.splitlines()
        if line.strip() and "NeededLibraries" not in line and line.startswith(" ")
    ]


def lib_closure(base, readelf, staging):
    """Copy every shared library the staged programs load, transitively.

    ldd(1) is a FreeBSD thing; the closure comes from readelf on the staged
    binaries and libraries themselves, walked breadth-first.
    """
    seen = set()
    todo = []
    for d in BIN_DIRS:
        p = os.path.join(staging, d)
        if os.path.isdir(p):
            todo += [os.path.join(p, f) for f in os.listdir(p)]
    while todo:
        f = todo.pop()
        for lib in needed_libs(readelf, f):
            if lib in seen:
                continue
            seen.add(lib)
            found = False
            for d in LIB_DIRS:
                member = base.find(d + "/" + lib)
                if member:
                    base.write(member, os.path.join(staging, d, lib), 0o755)
                    todo.append(os.path.join(staging, d, lib))
                    found = True
                    break
            if not found:
                sys.exit(f"{lib}: needed by {f}, not in the base.txz")
    return len(seen)


def mtree_spec(staging):
    """The makefs -F spec: every entry as root's, so no chown(2) is needed."""
    spec = ["/set type=file uid=0 gid=0 mode=0644",
            ". type=dir uid=0 gid=0 mode=0755"]
    for root, dirs, files in os.walk(staging):
        dirs.sort()
        for name in dirs:
            rel = os.path.relpath(os.path.join(root, name), staging)
            spec.append("./" + rel + " type=dir uid=0 gid=0 mode=0755")
        files.sort()
        for name in files:
            p = os.path.join(root, name)
            rel = os.path.relpath(p, staging)
            # mtree wants a bare octal (0644), not python's 0o644
            mode = format(os.stat(p).st_mode & 0o7777, "04o")
            spec.append("./" + rel + " type=file uid=0 gid=0 mode=" + mode)
    return "\n".join(spec) + "\n"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--base-txz", required=True)
    ap.add_argument("--rc", required=True)
    ap.add_argument("--authorized-keys", required=True)
    ap.add_argument("--makefs", required=True)
    ap.add_argument("--readelf", required=True)
    ap.add_argument("--out", required=True)
    args = ap.parse_args()

    staging = args.out + ".tree"
    os.makedirs(staging)
    for d in ("dev", "tmp", "var/run", "var/empty", "var/log", "root/.ssh", "proc"):
        os.makedirs(os.path.join(staging, d), exist_ok=True)
    os.chmod(os.path.join(staging, "root/.ssh"), 0o700)
    os.chmod(os.path.join(staging, "tmp"), 0o1777)
    os.chmod(os.path.join(staging, "var/empty"), 0o755)
    for d in ("dev", "tmp", "var", "var/run", "var/empty", "var/log", "root",
              "root/.ssh", "proc"):
        os.utime(os.path.join(staging, d), (0, 0))

    base = Base(args.base_txz)
    n = 0
    for want in PROGRAMS + ETC:
        member = base.find(want)
        if member is None:
            print(f"rootdisk: {want}: not in the base.txz, skipping")
            continue
        mode = member.mode & 0o7777
        if mode & 0o111:
            mode |= 0o111  # a program stays executable even if the tar said 0555
        base.write(member, os.path.join(staging, want), mode)
        n += 1
    libs = lib_closure(base, args.readelf, staging)

    for pattern in EXTRAS:
        for name in base.by_name:
            if name.startswith(pattern.rstrip("*")) and (
                pattern.endswith("*") or name == pattern
            ):
                member = base.find(name)
                if member is None:
                    continue
                mode = 0o644 if name.endswith("termcap") else 0o755
                base.write(member, os.path.join(staging, name), mode)

    # /etc: the sshd appends, the ttys (serial console getty), the rc, the key
    sshd_config = os.path.join(staging, "etc/ssh/sshd_config")
    with open(sshd_config, "a") as f:
        f.write("PermitRootLogin yes\nUseDNS no\nUsePAM no\nPasswordAuthentication no\n")
    os.utime(sshd_config, (0, 0))
    with open(os.path.join(staging, "etc/ttys"), "w") as f:
        f.write(TTYS)
    keys = os.path.join(staging, "root/.ssh/authorized_keys")
    with open(keys, "wb") as f:
        f.write(open(args.authorized_keys, "rb").read())
    os.chmod(keys, 0o600)
    os.utime(keys, (0, 0))
    rc = os.path.join(staging, "etc/rc")
    with open(rc, "wb") as f:
        f.write(open(args.rc, "rb").read())
    os.chmod(rc, 0o755)
    os.utime(rc, (0, 0))

    spec = args.out + ".mtree"
    with open(spec, "w") as f:
        f.write(mtree_spec(staging))

    r = subprocess.run(
        [args.makefs, "-t", "ffs", "-T", "0", "-F", spec,
         "-s", "256m", "-o", "version=2,label=root", "-o", "optimization=space",
         args.out, staging],
        capture_output=True, text=True,
    )
    if r.returncode != 0:
        sys.stderr.write(r.stdout + r.stderr)
        sys.exit("makefs failed")
    print(f"rootdisk: {n} base files, {libs} shared libraries")


if __name__ == "__main__":
    main()
