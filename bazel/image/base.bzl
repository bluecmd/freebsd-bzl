# The FreeBSD base system the root disk is populated from: the release's
# base.txz (the set the reference's release build installs), pinned by sha256.
# A repository (not a target input) because 165 MB of release tarball has no
# business in the action graph more than once; the rootdisk rule reads it.
def _freebsd_base_impl(repository_ctx):
    repository_ctx.download(
        url = "https://download.freebsd.org/releases/amd64/15.1-RELEASE/base.txz",
        sha256 = "3768988b151c20f965679062b065c63a977d6bbb9f47fd83695ec2c40790c18f",
        output = "base.txz",
    )
    repository_ctx.file("BUILD.bazel", "exports_files([\"base.txz\"])\n")

freebsd_base = repository_rule(
    implementation = _freebsd_base_impl,
)
