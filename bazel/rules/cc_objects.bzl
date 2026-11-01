"""Files that are objects of a cc link, carried as a cc target's CcInfo.

A reference build's archive sometimes holds objects no cc target compiled:
the kernel's startup `pi`-objects (an `objcopy --prefix-symbols=__pi_` of
objects another target compiled, archived by the parent `built-in.a`), a
partial link's `-r` output. A plain cc_library cannot carry them (its
objects come from its own sources); this rule declares files as the
objects of a cc target, so the aggregate that merges its deps' objects
(cc_static_library) keeps them and a link's `$(location)` names them:

    cc_objects(
        name = "built_in",
        objects = ["arch/x86/boot/startup/gdt_idt.pi.o"],
    )

The provider is built from rules_cc's private modules: the public
cc_common's `create_library_to_link` insists on a static-library artifact
alongside the objects, and a bare object has none (the parent aggregate
archives them).
"""

load("@rules_cc//cc/private:cc_info.bzl", "CcInfo", "create_linking_context")
load("@rules_cc//cc/private:cc_internal.bzl", "cc_internal")
load("@rules_cc//cc/private/link:create_library_to_link.bzl", "LibraryToLinkInfo")
load("@rules_cc//cc/private/link:create_linker_input.bzl", "create_linker_input")

def _impl(ctx):
    # the objects have to be frozen for the provider to go into a depset
    objs = cc_internal.freeze(list(ctx.files.objects))
    if not objs:
        return [CcInfo(), DefaultInfo(files = depset())]
    link = create_linking_context(linker_inputs = depset([
        create_linker_input(
            owner = ctx.label,
            libraries = depset([LibraryToLinkInfo(
                objects = objs,
                pic_objects = cc_internal.freeze([]),
                _contains_objects = True,
                _library_identifier = objs[0].short_path,
            )]),
        ),
    ]))
    return [CcInfo(linking_context = link), DefaultInfo(files = depset(objs))]

cc_objects = rule(
    implementation = _impl,
    attrs = {
        "objects": attr.label_list(allow_files = True,
                                   doc = "the object files, as a recipe names them"),
    },
    doc = "Files that are objects of a cc link, carried as a cc target's CcInfo (see the module docstring).",
)
