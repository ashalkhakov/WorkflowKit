#!/usr/bin/env python3
"""Write WorkflowKit.xcodeproj from the same source lists the GNUmakefiles use.

    python3 .tools/genxcodeproj.py

Regenerate after adding a source file rather than editing project.pbxproj by
hand; object ids are derived from names, so the output is stable and diffs
stay small. GNUstep does not read any of this -- it builds with make.
"""
import glob
import hashlib
import os
import re

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def oid(*parts):
    return hashlib.md5("/".join(parts).encode()).hexdigest()[:24].upper()


def make_list(path, var):
    text = open(os.path.join(ROOT, path)).read().replace("\\\n", " ")
    m = re.search(r"^%s\s*\+?=\s*(.*)$" % re.escape(var), text, re.M)
    return m.group(1).split()


SOURCES = make_list("GNUmakefile", "WorkflowKit_OBJC_FILES")            # Source/X.m
HEADERS = make_list("GNUmakefile", "WorkflowKit_HEADER_FILES")          # X.h
TESTS = make_list("Tests/GNUmakefile", "WorkflowKitTests_OBJC_FILES")   # X.m
# The areas' tests, which the backends' files include: shown, not compiled.
TEST_BODIES = sorted(os.path.basename(p) for p in glob.glob(os.path.join(ROOT, "Tests", "*.inc")))
DEMO = make_list("Examples/GNUmakefile", "PurchaseRequestDemo_OBJC_FILES")
MODELS = make_list("GNUmakefile", "WorkflowKit_XCDATAMODELD_FILES")     # Model/X.xcdatamodeld
# The OData API, over ODataKit's frameworks, which the workspace builds from
# ../ODataKit/ODataKit.xcodeproj.
ODATA_SOURCES = make_list("GNUmakefile", "WorkflowKitOData_OBJC_FILES")  # OData/X.m
ODATA_HEADERS = make_list("GNUmakefile", "WorkflowKitOData_HEADER_FILES")  # X.h
# wf-serve: HSMain with WorkflowKitOData's application, served by ODataKit's
# HTTPServerKit framework.
SERVE = make_list("Server/GNUmakefile", "wf-serve_OBJC_FILES")             # X.m
ODATAKIT = "../ODataKit"
# What both apps share (Apps/Shared): connecting to a server and its API.
# Their GNUmakefiles name these files as ../Shared/X.
SHARED = "Apps/Shared/"
SHARED_FILES = sorted(os.path.basename(p) for p in glob.glob(os.path.join(ROOT, SHARED, "*.[hm]")))
SHARED_RESOURCES = sorted("Resources/" + os.path.basename(p)
                          for p in glob.glob(os.path.join(ROOT, SHARED, "Resources", "*.xib")))


def shared(path):
    return path.split("Shared/", 1)[1] if "Shared/" in path else None


def own(paths):
    return [p for p in paths if shared(p) is None]


# WorkflowDesk (Apps/WorkflowDesk), over ODataKit's client and XFormsKit's
# form view, whose frameworks the workspace builds from their projects.
DESK = "Apps/WorkflowDesk/"
DESK_SOURCES = make_list(DESK + "GNUmakefile", "WorkflowDesk_OBJC_FILES")             # X.m
DESK_RESOURCES = make_list(DESK + "GNUmakefile", "WorkflowDesk_RESOURCE_FILES")       # Resources/X.xib
DESK_HEADERS = sorted(os.path.basename(p) for p in glob.glob(os.path.join(ROOT, DESK, "*.h")))
DESK_TESTS = [t for t in make_list(DESK + "Tests/GNUmakefile", "WorkflowDeskTests_OBJC_FILES")
              if not t.startswith("../")]                                             # Tests/X.m
DESK_TESTED = [t[3:] for t in make_list(DESK + "Tests/GNUmakefile", "WorkflowDeskTests_OBJC_FILES")
               if t.startswith("../")]                                                # X.m, ../Shared/X.m
# WorkflowDesigner (Apps/WorkflowDesigner), over the engine's framework, whose
# BPMN reader checks what it draws.
DESIGNER = "Apps/WorkflowDesigner/"
DESIGNER_SOURCES = make_list(DESIGNER + "GNUmakefile", "WorkflowDesigner_OBJC_FILES")
DESIGNER_RESOURCES = make_list(DESIGNER + "GNUmakefile", "WorkflowDesigner_RESOURCE_FILES")
DESIGNER_HEADERS = sorted(os.path.basename(p) for p in glob.glob(os.path.join(ROOT, DESIGNER, "*.h")))
DESIGNER_TEST_FILES = make_list(DESIGNER + "Tests/GNUmakefile", "WorkflowDesignerTests_OBJC_FILES")
DESIGNER_TESTS = [t for t in DESIGNER_TEST_FILES if not t.startswith("../")]
DESIGNER_TESTED = [t[3:] for t in DESIGNER_TEST_FILES if t.startswith("../")]
DESIGNER_TEST_HEADERS = sorted(os.path.basename(p) for p in glob.glob(os.path.join(ROOT, DESIGNER, "Tests", "*.h")))
ODATA_OTHERS = sorted(os.path.basename(p) for p in glob.glob(os.path.join(ROOT, "OData", "*.h"))
                      if os.path.basename(p) not in ODATA_HEADERS)
DOCS = ["CLAUDE.md", "WorkflowKit-BPMN-Subset.md", "GNUmakefile"]
CONFIGS = ["Common.xcconfig", "Debug.xcconfig", "Release.xcconfig"]

objects = {}   # id -> (isa, body lines, comment)


def add(ident, comment, fields):
    objects[ident] = (comment, fields)
    return ident


def q(s):
    if re.fullmatch(r"[A-Za-z0-9_./$]+", s) and s != "":
        return s
    return '"' + s.replace('"', '\\"') + '"'


# ---------------------------------------------------------------- files
def fileref(path, name, ftype):
    return add(oid("ref", path), name, [
        ("isa", "PBXFileReference"),
        ("lastKnownFileType", ftype),
        ("path", q(name)),
        ("sourceTree", '"<group>"'),
    ])


def ftype(name):
    return {
        ".m": "sourcecode.c.objc", ".h": "sourcecode.c.h", ".inc": "sourcecode.c.objc",
        ".md": "net.daringfireball.markdown", ".xcconfig": "text.xcconfig",
    }.get(os.path.splitext(name)[1], "text")


src_refs = {s: fileref(s, os.path.basename(s), ftype(s)) for s in SOURCES}
hdr_refs = {h: fileref("Headers/" + h, h, ftype(h)) for h in HEADERS}
test_refs = {t: fileref("Tests/" + t, t, ftype(t)) for t in TESTS + TEST_BODIES}
demo_refs = {d: fileref("Examples/" + d, d, ftype(d)) for d in DEMO}
doc_refs = {d: fileref(d, d, ftype(d)) for d in DOCS}
cfg_refs = {c: fileref("Xcode/Configs/" + c, c, "text.xcconfig") for c in CONFIGS}
odata_refs = {o: fileref(o, os.path.basename(o), ftype(o)) for o in ODATA_SOURCES}
odata_hdr_refs = {h: fileref("OData/" + h, h, ftype(h)) for h in ODATA_HEADERS + ODATA_OTHERS}
serve_refs = {s: fileref("Server/" + s, s, ftype(s)) for s in SERVE}
shared_refs = {f: fileref(SHARED + f, os.path.basename(f), "file.xib" if f.endswith(".xib") else ftype(f))
               for f in SHARED_FILES + SHARED_RESOURCES}


# An app's file by the path its GNUmakefile gives: its own, or a shared one.
def app_file(refs, path):
    return shared_refs[shared(path)] if shared(path) is not None else refs[path]


desk_refs = {f: fileref(DESK + f, f, ftype(f)) for f in own(DESK_SOURCES) + DESK_HEADERS + ["WorkflowDesk-Info.plist"]}
desk_res_refs = {r: fileref(DESK + r, os.path.basename(r), "file.xib") for r in own(DESK_RESOURCES)}
desk_test_refs = {t: fileref(DESK + "Tests/" + t, t, ftype(t)) for t in DESK_TESTS}
designer_refs = {f: fileref(DESIGNER + f, f, ftype(f))
                 for f in own(DESIGNER_SOURCES) + DESIGNER_HEADERS + ["WorkflowDesigner-Info.plist"]}
designer_res_refs = {r: fileref(DESIGNER + r, os.path.basename(r), "file.xib") for r in own(DESIGNER_RESOURCES)}
designer_test_refs = {t: fileref(DESIGNER + "Tests/" + t, t, ftype(t)) for t in DESIGNER_TESTS + DESIGNER_TEST_HEADERS}






def sdk_framework(name):
    return add(oid("sdk", name), name + ".framework", [
        ("isa", "PBXFileReference"),
        ("lastKnownFileType", "wrapper.framework"),
        ("name", name + ".framework"),
        ("path", "System/Library/Frameworks/%s.framework" % name),
        ("sourceTree", "SDKROOT"),
    ])


foundation = sdk_framework("Foundation")
coredata = sdk_framework("CoreData")


# A framework another project in the workspace builds: found by name in the
# build directory, which is what makes Xcode build it first.
def built_framework(name):
    return add(oid("built", name), name + ".framework", [
        ("isa", "PBXFileReference"),
        ("explicitFileType", "wrapper.framework"),
        ("path", name + ".framework"),
        ("sourceTree", "BUILT_PRODUCTS_DIR"),
    ])


odatakit = built_framework("ODataKit")
odataservice = built_framework("ODataService")
odatastore = built_framework("ODataIncrementalStore")
httpserverkit = built_framework("HTTPServerKit")
otelkit = built_framework("OTelKit")
xformskit = built_framework("XFormsKit")
appkit = sdk_framework("AppKit")


# A data model is a version group holding one .xcdatamodel per version; the
# current one is named in the bundle's .xccurrentversion. Xcode compiles it
# in the Sources phase into a .momd inside the framework.
def version_group(path):
    bundle = os.path.join(ROOT, path)
    current = open(os.path.join(bundle, ".xccurrentversion")).read()
    current = re.search(r"<string>([^<]+)</string>", current).group(1)
    versions = sorted(v for v in os.listdir(bundle) if v.endswith(".xcdatamodel"))
    refs = {v: fileref(path + "/" + v, v, "wrapper.xcdatamodel") for v in versions}
    name = os.path.basename(path)
    return add(oid("ref", path), name, [
        ("isa", "XCVersionGroup"),
        ("children", names([refs[v] for v in versions])),
        ("currentVersion", "%s /* %s */" % (refs[current], current)),
        ("path", q(name)),
        ("sourceTree", '"<group>"'),
        ("versionGroupType", "wrapper.xcdatamodel"),
    ])


def product(name, ext, ftype_):
    return add(oid("product", name), name + ext, [
        ("isa", "PBXFileReference"),
        ("explicitFileType", ftype_),
        ("includeInIndex", "0"),
        ("path", q(name + ext)),
        ("sourceTree", "BUILT_PRODUCTS_DIR"),
    ])


p_fw = product("WorkflowKit", ".framework", "wrapper.framework")
p_odata = product("WorkflowKitOData", ".framework", "wrapper.framework")
p_tests = product("WorkflowKitTests", ".xctest", "wrapper.cfbundle")
p_demo = product("PurchaseRequestDemo", "", '"compiled.mach-o.executable"')
p_serve = product("wf-serve", "", '"compiled.mach-o.executable"')
p_desk = product("WorkflowDesk", ".app", "wrapper.application")
p_desk_tests = product("WorkflowDeskTests", ".xctest", "wrapper.cfbundle")
p_designer = product("WorkflowDesigner", ".app", "wrapper.application")
p_designer_tests = product("WorkflowDesignerTests", ".xctest", "wrapper.cfbundle")


# ---------------------------------------------------------------- build files
def buildfile(target, ref, comment, settings=None):
    fields = [("isa", "PBXBuildFile"), ("fileRef", "%s /* %s */" % (ref, comment))]
    if settings:
        fields.append(("settings", settings))
    return add(oid("bf", target, ref), "%s in %s" % (comment, target), fields)


def phase(isa, target, name, files):
    return add(oid("phase", target, name), name, [
        ("isa", isa),
        ("buildActionMask", "2147483647"),
        ("files", files),
        ("runOnlyForDeploymentPostprocessing", "0"),
    ])


def names(ids):
    return ["%s /* %s */" % (i, objects[i][0]) for i in ids]


model_refs = {m: version_group(m) for m in MODELS}


fw_sources = phase("PBXSourcesBuildPhase", "WorkflowKit", "Sources", names(
    [buildfile("WorkflowKit", src_refs[s], os.path.basename(s)) for s in SOURCES] +
    [buildfile("WorkflowKit", model_refs[m], os.path.basename(m)) for m in MODELS]))
fw_headers = phase("PBXHeadersBuildPhase", "WorkflowKit", "Headers", names(
    [buildfile("WorkflowKit", hdr_refs[h], h, "{ATTRIBUTES = (Public, ); }") for h in HEADERS]))
fw_frameworks = phase("PBXFrameworksBuildPhase", "WorkflowKit", "Frameworks", names(
    [buildfile("WorkflowKit", foundation, "Foundation.framework"),
     buildfile("WorkflowKit", coredata, "CoreData.framework")]))

o_sources = phase("PBXSourcesBuildPhase", "WorkflowKitOData", "Sources", names(
    [buildfile("WorkflowKitOData", odata_refs[s], os.path.basename(s)) for s in ODATA_SOURCES]))
o_headers = phase("PBXHeadersBuildPhase", "WorkflowKitOData", "Headers", names(
    [buildfile("WorkflowKitOData", odata_hdr_refs[h], h, "{ATTRIBUTES = (Public, ); }") for h in ODATA_HEADERS]))
o_frameworks = phase("PBXFrameworksBuildPhase", "WorkflowKitOData", "Frameworks", names(
    [buildfile("WorkflowKitOData", p_fw, "WorkflowKit.framework"),
     buildfile("WorkflowKitOData", odatakit, "ODataKit.framework"),
     buildfile("WorkflowKitOData", odataservice, "ODataService.framework"),
     buildfile("WorkflowKitOData", httpserverkit, "HTTPServerKit.framework"),
     buildfile("WorkflowKitOData", otelkit, "OTelKit.framework"),
     buildfile("WorkflowKitOData", foundation, "Foundation.framework"),
     buildfile("WorkflowKitOData", coredata, "CoreData.framework")]))

t_sources = phase("PBXSourcesBuildPhase", "WorkflowKitTests", "Sources", names(
    [buildfile("WorkflowKitTests", test_refs[t], t) for t in TESTS]))
t_frameworks = phase("PBXFrameworksBuildPhase", "WorkflowKitTests", "Frameworks", names(
    [buildfile("WorkflowKitTests", p_fw, "WorkflowKit.framework"),
     buildfile("WorkflowKitTests", p_odata, "WorkflowKitOData.framework"),
     buildfile("WorkflowKitTests", odatakit, "ODataKit.framework"),
     buildfile("WorkflowKitTests", odataservice, "ODataService.framework"),
     buildfile("WorkflowKitTests", httpserverkit, "HTTPServerKit.framework"),
     buildfile("WorkflowKitTests", otelkit, "OTelKit.framework")]))

s_sources = phase("PBXSourcesBuildPhase", "wf-serve", "Sources", names(
    [buildfile("wf-serve", serve_refs[s], s) for s in SERVE]))
s_frameworks = phase("PBXFrameworksBuildPhase", "wf-serve", "Frameworks", names(
    [buildfile("wf-serve", p_fw, "WorkflowKit.framework"),
     buildfile("wf-serve", p_odata, "WorkflowKitOData.framework"),
     buildfile("wf-serve", odatakit, "ODataKit.framework"),
     buildfile("wf-serve", odataservice, "ODataService.framework"),
     buildfile("wf-serve", httpserverkit, "HTTPServerKit.framework"),
     buildfile("wf-serve", otelkit, "OTelKit.framework"),
     buildfile("wf-serve", foundation, "Foundation.framework"),
     buildfile("wf-serve", coredata, "CoreData.framework")]))

d_sources = phase("PBXSourcesBuildPhase", "PurchaseRequestDemo", "Sources", names(
    [buildfile("PurchaseRequestDemo", demo_refs[d], d) for d in DEMO]))
d_frameworks = phase("PBXFrameworksBuildPhase", "PurchaseRequestDemo", "Frameworks", names(
    [buildfile("PurchaseRequestDemo", p_fw, "WorkflowKit.framework")]))

DESK_FRAMEWORKS = [(odatakit, "ODataKit.framework"), (odatastore, "ODataIncrementalStore.framework"),
                   (otelkit, "OTelKit.framework"), (xformskit, "XFormsKit.framework")]
w_sources = phase("PBXSourcesBuildPhase", "WorkflowDesk", "Sources", names(
    [buildfile("WorkflowDesk", app_file(desk_refs, f), os.path.basename(f)) for f in DESK_SOURCES]))
w_resources = phase("PBXResourcesBuildPhase", "WorkflowDesk", "Resources", names(
    [buildfile("WorkflowDesk", app_file(desk_res_refs, r), os.path.basename(r)) for r in DESK_RESOURCES]))
w_frameworks = phase("PBXFrameworksBuildPhase", "WorkflowDesk", "Frameworks", names(
    [buildfile("WorkflowDesk", ref, name) for ref, name in DESK_FRAMEWORKS] +
    [buildfile("WorkflowDesk", appkit, "AppKit.framework"),
     buildfile("WorkflowDesk", coredata, "CoreData.framework")]))
w_embed = add(oid("phase", "WorkflowDesk", "Embed Frameworks"), "Embed Frameworks", [
    ("isa", "PBXCopyFilesBuildPhase"),
    ("buildActionMask", "2147483647"),
    ("dstPath", '""'),
    ("dstSubfolderSpec", "10"),
    ("files", names([buildfile("WorkflowDesk.embed", ref, name,
                               "{ATTRIBUTES = (CodeSignOnCopy, RemoveHeadersOnCopy, ); }")
                     for ref, name in DESK_FRAMEWORKS])),
    ("name", q("Embed Frameworks")),
    ("runOnlyForDeploymentPostprocessing", "0"),
])
# The engine's model, compiled into the app without the engine's classes:
# in the Sources phase Xcode would generate them too.
def model_phase(target):
    return add(oid("phase", target, "Compile Model"), "Compile Model", [
    ("isa", "PBXShellScriptBuildPhase"),
    ("buildActionMask", "2147483647"),
    ("files", []),
    ("inputPaths", ['"$(SRCROOT)/Model/WorkflowKit.xcdatamodeld"']),
    ("name", q("Compile Model")),
    ("outputPaths", ['"$(TARGET_BUILD_DIR)/$(UNLOCALIZED_RESOURCES_FOLDER_PATH)/WorkflowKit.momd"']),
    ("runOnlyForDeploymentPostprocessing", "0"),
    ("shellPath", "/bin/sh"),
    ("shellScript", q('xcrun momc --macosx-deployment-target "$MACOSX_DEPLOYMENT_TARGET" '
                      '"$SRCROOT/Model/WorkflowKit.xcdatamodeld" '
                      '"$TARGET_BUILD_DIR/$UNLOCALIZED_RESOURCES_FOLDER_PATH/WorkflowKit.momd"\n')),
    ])


w_model = model_phase("WorkflowDesk")

wt_sources = phase("PBXSourcesBuildPhase", "WorkflowDeskTests", "Sources", names(
    [buildfile("WorkflowDeskTests", desk_test_refs[t], t) for t in DESK_TESTS] +
    [buildfile("WorkflowDeskTests", app_file(desk_refs, f), os.path.basename(f)) for f in DESK_TESTED]))
wt_frameworks = phase("PBXFrameworksBuildPhase", "WorkflowDeskTests", "Frameworks", names(
    [buildfile("WorkflowDeskTests", odatakit, "ODataKit.framework")]))

# Vendored code (ThirdParty/) is compiled as it came, its warnings unheard.
wg_sources = phase("PBXSourcesBuildPhase", "WorkflowDesigner", "Sources", names(
    [buildfile("WorkflowDesigner", app_file(designer_refs, f), os.path.basename(f),
               '{COMPILER_FLAGS = "-w"; }' if f.startswith("ThirdParty/") else None)
     for f in DESIGNER_SOURCES]))
wg_resources = phase("PBXResourcesBuildPhase", "WorkflowDesigner", "Resources", names(
    [buildfile("WorkflowDesigner", app_file(designer_res_refs, r), os.path.basename(r))
     for r in DESIGNER_RESOURCES]))
# The server's API, as WorkflowDesk opens it.
DESIGNER_FRAMEWORKS = [(p_fw, "WorkflowKit.framework"), (odatakit, "ODataKit.framework"),
                       (odatastore, "ODataIncrementalStore.framework"), (otelkit, "OTelKit.framework")]
wg_model = model_phase("WorkflowDesigner")
wg_frameworks = phase("PBXFrameworksBuildPhase", "WorkflowDesigner", "Frameworks", names(
    [buildfile("WorkflowDesigner", ref, name) for ref, name in DESIGNER_FRAMEWORKS] +
    [buildfile("WorkflowDesigner", appkit, "AppKit.framework"),
     buildfile("WorkflowDesigner", coredata, "CoreData.framework")]))
wg_embed = add(oid("phase", "WorkflowDesigner", "Embed Frameworks"), "Embed Frameworks", [
    ("isa", "PBXCopyFilesBuildPhase"),
    ("buildActionMask", "2147483647"),
    ("dstPath", '""'),
    ("dstSubfolderSpec", "10"),
    ("files", names([buildfile("WorkflowDesigner.embed", ref, name,
                               "{ATTRIBUTES = (CodeSignOnCopy, RemoveHeadersOnCopy, ); }")
                     for ref, name in DESIGNER_FRAMEWORKS])),
    ("name", q("Embed Frameworks")),
    ("runOnlyForDeploymentPostprocessing", "0"),
])
gt_sources = phase("PBXSourcesBuildPhase", "WorkflowDesignerTests", "Sources", names(
    [buildfile("WorkflowDesignerTests", designer_test_refs[t], t) for t in DESIGNER_TESTS] +
    [buildfile("WorkflowDesignerTests", app_file(designer_refs, f), os.path.basename(f)) for f in DESIGNER_TESTED]))
gt_frameworks = phase("PBXFrameworksBuildPhase", "WorkflowDesignerTests", "Frameworks", names(
    [buildfile("WorkflowDesignerTests", p_fw, "WorkflowKit.framework")]))


# ---------------------------------------------------------------- groups
def group(key, name, children, path=None):
    fields = [("isa", "PBXGroup"), ("children", names(children))]
    if path:
        fields.append(("path", q(path)))
    else:
        fields.append(("name", q(name)))
    fields.append(("sourceTree", '"<group>"'))
    return add(oid("group", key), name, fields)


g_headers = group("Headers", "Headers", [hdr_refs[h] for h in HEADERS], "Headers")
g_source = group("Source", "Source", [src_refs[s] for s in SOURCES], "Source")
g_odata = group("OData", "OData", [odata_hdr_refs[h] for h in ODATA_HEADERS + ODATA_OTHERS] +
                [odata_refs[s] for s in ODATA_SOURCES], "OData")
g_tests = group("Tests", "Tests", [test_refs[t] for t in TESTS + TEST_BODIES], "Tests")
g_examples = group("Examples", "Examples", [demo_refs[d] for d in DEMO], "Examples")
g_server = group("Server", "Server", [serve_refs[s] for s in SERVE], "Server")
g_model = group("Model", "Model", [model_refs[m] for m in MODELS], "Model")
g_shared_res = group("SharedResources", "Resources", [shared_refs[r] for r in SHARED_RESOURCES], "Resources")
g_shared = group("Shared", "Shared",
                 [shared_refs[f] for f in sorted(SHARED_FILES, key=lambda n: (n[:-2], n[-1:]))] + [g_shared_res],
                 "Shared")
g_desk_res = group("WorkflowDeskResources", "Resources", [desk_res_refs[r] for r in own(DESK_RESOURCES)], "Resources")
g_desk_tests = group("WorkflowDeskTests", "Tests", [desk_test_refs[t] for t in DESK_TESTS], "Tests")
g_desk = group("WorkflowDesk", "WorkflowDesk",
               [desk_refs[f] for f in sorted(DESK_HEADERS + own(DESK_SOURCES), key=lambda n: (n[:-2], n[-1:]))] +
               [desk_refs["WorkflowDesk-Info.plist"], g_desk_res, g_desk_tests], "WorkflowDesk")
g_designer_res = group("WorkflowDesignerResources", "Resources",
                       [designer_res_refs[r] for r in own(DESIGNER_RESOURCES)], "Resources")
g_designer_tests = group("WorkflowDesignerTests", "Tests",
                         [designer_test_refs[t] for t in DESIGNER_TEST_HEADERS + DESIGNER_TESTS], "Tests")
g_designer = group("WorkflowDesigner", "WorkflowDesigner",
                   [designer_refs[f] for f in sorted(DESIGNER_HEADERS + own(DESIGNER_SOURCES),
                                                     key=lambda n: (n[:-2], n[-1:]))] +
                   [designer_refs["WorkflowDesigner-Info.plist"], g_designer_res, g_designer_tests],
                   "WorkflowDesigner")
g_apps = group("Apps", "Apps", [g_shared, g_desk, g_designer], "Apps")
g_configs = group("Configs", "Configs", [cfg_refs[c] for c in CONFIGS], "Xcode/Configs")
g_products = group("Products", "Products", [p_fw, p_odata, p_tests, p_demo, p_serve, p_desk, p_desk_tests,
                                            p_designer, p_designer_tests])
g_frameworks = group("Frameworks", "Frameworks", [foundation, coredata, appkit, odatakit, odataservice, odatastore,
                                                  httpserverkit, otelkit, xformskit])
g_main = group("main", "WorkflowKit", [doc_refs[d] for d in DOCS] +
               [g_headers, g_source, g_odata, g_model, g_tests, g_examples, g_server, g_apps, g_configs,
                g_frameworks, g_products])
# The main group has no name or path of its own.
objects[g_main] = ("", [(k, v) for k, v in objects[g_main][1] if k != "name"])


# ---------------------------------------------------------------- configurations
def configs(key, settings_debug, settings_release, base=True):
    ids = []
    for cfg, extra in (("Debug", settings_debug), ("Release", settings_release)):
        fields = [("isa", "XCBuildConfiguration")]
        if base:
            fields.append(("baseConfigurationReference",
                           "%s /* %s.xcconfig */" % (cfg_refs[cfg + ".xcconfig"], cfg)))
        fields.append(("buildSettings", extra))
        fields.append(("name", cfg))
        ids.append(add(oid("cfg", key, cfg), cfg, fields))
    return add(oid("cfglist", key), "Build configuration list for " + key, [
        ("isa", "XCConfigurationList"),
        ("buildConfigurations", names(ids)),
        ("defaultConfigurationIsVisible", "0"),
        ("defaultConfigurationName", "Release"),
    ])


FW = {
    "DEFINES_MODULE": "YES",
    "DYLIB_COMPATIBILITY_VERSION": "1",
    "DYLIB_CURRENT_VERSION": "1",
    "DYLIB_INSTALL_NAME_BASE": '"@rpath"',
    "INSTALL_PATH": '"$(LOCAL_LIBRARY_DIR)/Frameworks"',
    "LD_RUNPATH_SEARCH_PATHS": '("$(inherited)", "@executable_path/../Frameworks", "@loader_path/Frameworks")',
    "PRODUCT_BUNDLE_IDENTIFIER": "local.workflowkit.WorkflowKit",
    "SKIP_INSTALL": "YES",
    # Source/ too: the generated WFExecutionEntity+CoreDataProperties.h
    # imports its class's header, WFExecutionEntity.h, from there.
    "HEADER_SEARCH_PATHS": '("$(SRCROOT)/Headers", "$(SRCROOT)/Source")',
}
# Where Xcode generates the WorkflowKit target's entity classes, which the
# other targets that read the engine's rows import (Source/WFEntities.h).
GENERATED = ('"$(PROJECT_TEMP_DIR)/$(CONFIGURATION)$(EFFECTIVE_PLATFORM_NAME)/WorkflowKit.build/'
             'DerivedSources/CoreDataGenerated/WorkflowKit"')
ODATA_FW = dict(FW, **{
    "PRODUCT_BUNDLE_IDENTIFIER": "local.workflowkit.WorkflowKitOData",
    # The engine's own headers too: the API reads its rows.
    "HEADER_SEARCH_PATHS": '("$(SRCROOT)/Headers", "$(SRCROOT)/Source", "$(SRCROOT)/OData", %s)' % GENERATED,
})
TESTS_S = {
    "PRODUCT_BUNDLE_IDENTIFIER": "local.workflowkit.WorkflowKitTests",
    "GCC_PREPROCESSOR_DEFINITIONS": '("$(inherited)", "WORKFLOWKIT_ODATA=1")',
    "HEADER_SEARCH_PATHS": '("$(SRCROOT)/Headers", "$(SRCROOT)/OData")',
    "LD_RUNPATH_SEARCH_PATHS": '("$(inherited)", "@executable_path/../Frameworks", "@loader_path/../Frameworks")',
}
SERVE_S = {
    "HEADER_SEARCH_PATHS": '("$(SRCROOT)/Headers", "$(SRCROOT)/OData")',
    "LD_RUNPATH_SEARCH_PATHS": '("$(inherited)", "@executable_path", "@loader_path")',
}
DEMO_S = {
    "HEADER_SEARCH_PATHS": '"$(SRCROOT)/Headers"',
    "LD_RUNPATH_SEARCH_PATHS": '("$(inherited)", "@executable_path", "@loader_path")',
}
DESK_S = {
    "INFOPLIST_FILE": '"Apps/WorkflowDesk/WorkflowDesk-Info.plist"',
    "GENERATE_INFOPLIST_FILE": "NO",
    "PRODUCT_BUNDLE_IDENTIFIER": "local.workflowkit.WorkflowDesk",
    # XFormsKit's.
    "MACOSX_DEPLOYMENT_TARGET": "11.0",
    "LD_RUNPATH_SEARCH_PATHS": '("$(inherited)", "@executable_path/../Frameworks")',
    # The model's compiling script writes into the app.
    "ENABLE_USER_SCRIPT_SANDBOXING": "NO",
    # XFormsKit's framework carries no headers: its apps, like this one on
    # GNUstep, include them from its tree.
    "HEADER_SEARCH_PATHS": '("$(SRCROOT)/../XFormsKit/Sources", "$(SRCROOT)/../XFormsKit/Sources/XFormsKit")',
}
DESK_TESTS_S = {
    "PRODUCT_BUNDLE_IDENTIFIER": "local.workflowkit.WorkflowDeskTests",
    "GENERATE_INFOPLIST_FILE": "YES",
    "MACOSX_DEPLOYMENT_TARGET": "11.0",
    "HEADER_SEARCH_PATHS": '("$(SRCROOT)/Apps/WorkflowDesk", "$(SRCROOT)/Apps/Shared")',
    "LD_RUNPATH_SEARCH_PATHS": '("$(inherited)", "@executable_path/../Frameworks", "@loader_path/../Frameworks")',
}
DESIGNER_S = {
    "INFOPLIST_FILE": '"Apps/WorkflowDesigner/WorkflowDesigner-Info.plist"',
    "GENERATE_INFOPLIST_FILE": "NO",
    "PRODUCT_BUNDLE_IDENTIFIER": "local.workflowkit.WorkflowDesigner",
    "MACOSX_DEPLOYMENT_TARGET": "11.0",
    "LD_RUNPATH_SEARCH_PATHS": '("$(inherited)", "@executable_path/../Frameworks")',
    # The model's compiling script writes into the app.
    "ENABLE_USER_SCRIPT_SANDBOXING": "NO",
}
DESIGNER_TESTS_S = {
    "PRODUCT_BUNDLE_IDENTIFIER": "local.workflowkit.WorkflowDesignerTests",
    "GENERATE_INFOPLIST_FILE": "YES",
    "MACOSX_DEPLOYMENT_TARGET": "11.0",
    "HEADER_SEARCH_PATHS": '"$(SRCROOT)/Apps/WorkflowDesigner"',
    "LD_RUNPATH_SEARCH_PATHS": '("$(inherited)", "@executable_path/../Frameworks", "@loader_path/../Frameworks")',
}


def settings(d):
    return "{\n" + "".join("\t\t\t\t%s = %s;\n" % (k, v) for k, v in sorted(d.items())) + "\t\t\t}"


cl_project = configs("project", "{\n\t\t\t}", "{\n\t\t\t}")
cl_fw = configs("WorkflowKit", settings(FW), settings(FW))
cl_odata = configs("WorkflowKitOData", settings(ODATA_FW), settings(ODATA_FW))
cl_tests = configs("WorkflowKitTests", settings(TESTS_S), settings(TESTS_S))
cl_demo = configs("PurchaseRequestDemo", settings(DEMO_S), settings(DEMO_S))
cl_serve = configs("wf-serve", settings(SERVE_S), settings(SERVE_S))
cl_desk = configs("WorkflowDesk", settings(DESK_S), settings(DESK_S))
cl_desk_tests = configs("WorkflowDeskTests", settings(DESK_TESTS_S), settings(DESK_TESTS_S))
cl_designer = configs("WorkflowDesigner", settings(DESIGNER_S), settings(DESIGNER_S))
cl_designer_tests = configs("WorkflowDesignerTests", settings(DESIGNER_TESTS_S), settings(DESIGNER_TESTS_S))

project_id = oid("project")


# ---------------------------------------------------------------- targets
def dependency(target, on_id, on_name):
    proxy = add(oid("proxy", target, on_name), "PBXContainerItemProxy", [
        ("isa", "PBXContainerItemProxy"),
        ("containerPortal", "%s /* Project object */" % project_id),
        ("proxyType", "1"),
        ("remoteGlobalIDString", on_id),
        ("remoteInfo", on_name),
    ])
    return add(oid("dep", target, on_name), "PBXTargetDependency", [
        ("isa", "PBXTargetDependency"),
        ("target", "%s /* %s */" % (on_id, on_name)),
        ("targetProxy", "%s /* PBXContainerItemProxy */" % proxy),
    ])


def target(name, cfglist, phases, deps, prod, ptype):
    return add(oid("target", name), name, [
        ("isa", "PBXNativeTarget"),
        ("buildConfigurationList", '%s /* Build configuration list for PBXNativeTarget "%s" */' % (cfglist, name)),
        ("buildPhases", names(phases)),
        ("buildRules", []),
        ("dependencies", names(deps)),
        ("name", q(name)),
        ("productName", q(name)),
        ("productReference", "%s /* %s */" % (prod, objects[prod][0])),
        ("productType", '"%s"' % ptype),
    ])


t_fw = oid("target", "WorkflowKit")
t_fw = target("WorkflowKit", cl_fw, [fw_headers, fw_sources, fw_frameworks], [],
              p_fw, "com.apple.product-type.framework")
t_odata = target("WorkflowKitOData", cl_odata, [o_headers, o_sources, o_frameworks],
                 [dependency("WorkflowKitOData", t_fw, "WorkflowKit")],
                 p_odata, "com.apple.product-type.framework")
t_tests = target("WorkflowKitTests", cl_tests, [t_sources, t_frameworks],
                 [dependency("WorkflowKitTests", t_fw, "WorkflowKit"),
                  dependency("WorkflowKitTests", t_odata, "WorkflowKitOData")],
                 p_tests, "com.apple.product-type.bundle.unit-test")
t_demo = target("PurchaseRequestDemo", cl_demo, [d_sources, d_frameworks],
                [dependency("PurchaseRequestDemo", t_fw, "WorkflowKit")],
                p_demo, "com.apple.product-type.tool")
t_serve = target("wf-serve", cl_serve, [s_sources, s_frameworks],
                 [dependency("wf-serve", t_fw, "WorkflowKit"), dependency("wf-serve", t_odata, "WorkflowKitOData")],
                 p_serve, "com.apple.product-type.tool")
t_desk = target("WorkflowDesk", cl_desk, [w_model, w_sources, w_resources, w_frameworks, w_embed], [],
                p_desk, "com.apple.product-type.application")
t_desk_tests = target("WorkflowDeskTests", cl_desk_tests, [wt_sources, wt_frameworks], [],
                      p_desk_tests, "com.apple.product-type.bundle.unit-test")
t_designer = target("WorkflowDesigner", cl_designer, [wg_model, wg_sources, wg_resources, wg_frameworks, wg_embed],
                    [dependency("WorkflowDesigner", t_fw, "WorkflowKit")],
                    p_designer, "com.apple.product-type.application")
t_designer_tests = target("WorkflowDesignerTests", cl_designer_tests, [gt_sources, gt_frameworks],
                          [dependency("WorkflowDesignerTests", t_fw, "WorkflowKit")],
                          p_designer_tests, "com.apple.product-type.bundle.unit-test")

add(project_id, "Project object", [
    ("isa", "PBXProject"),
    ("attributes", "{\n\t\t\t\tBuildIndependentTargetsInParallel = 1;\n\t\t\t\tLastUpgradeCheck = 1600;\n\t\t\t}"),
    ("buildConfigurationList", '%s /* Build configuration list for PBXProject "WorkflowKit" */' % cl_project),
    ("compatibilityVersion", '"Xcode 14.0"'),
    ("developmentRegion", "en"),
    ("hasScannedForEncodings", "0"),
    ("knownRegions", ["en", "Base"]),
    ("mainGroup", g_main),
    ("productRefGroup", "%s /* Products */" % g_products),
    ("projectDirPath", '""'),
    ("projectRoot", '""'),
    ("targets", names([t_fw, t_odata, t_tests, t_demo, t_serve, t_desk, t_desk_tests, t_designer,
                       t_designer_tests])),
])


# ---------------------------------------------------------------- serialise
def value(v, indent):
    if isinstance(v, list):
        if not v:
            return "(\n%s)" % ("\t" * indent)
        inner = "".join("%s%s,\n" % ("\t" * (indent + 1), x) for x in v)
        return "(\n%s%s)" % (inner, "\t" * indent)
    return v


def render():
    by_isa = {}
    for ident, (comment, fields) in objects.items():
        by_isa.setdefault(dict(fields)["isa"], []).append((ident, comment, fields))
    out = ["// !$*UTF8*$!", "{", "\tarchiveVersion = 1;", "\tclasses = {", "\t};",
           "\tobjectVersion = 56;", "\tobjects = {", ""]
    for isa in sorted(by_isa):
        out.append("/* Begin %s section */" % isa)
        for ident, comment, fields in sorted(by_isa[isa]):
            head = "\t\t%s%s = {" % (ident, " /* %s */" % comment if comment else "")
            if isa in ("PBXBuildFile", "PBXFileReference"):
                out.append(head + " " + " ".join("%s = %s;" % (k, value(v, 0)) for k, v in fields) + " };")
            else:
                out.append(head)
                for k, v in fields:
                    out.append("\t\t\t%s = %s;" % (k, value(v, 3)))
                out.append("\t\t};")
        out.append("/* End %s section */" % isa)
        out.append("")
    out += ["\t};", "\trootObject = %s /* Project object */;" % project_id, "}", ""]
    return "\n".join(out)


proj = os.path.join(ROOT, "WorkflowKit.xcodeproj")
os.makedirs(os.path.join(proj, "xcshareddata", "xcschemes"), exist_ok=True)
with open(os.path.join(proj, "project.pbxproj"), "w") as f:
    f.write(render())


# ---------------------------------------------------------------- schemes
def ref(tid, name, product_name, container="WorkflowKit.xcodeproj"):
    return ('<BuildableReference BuildableIdentifier = "primary" BlueprintIdentifier = "%s" '
            'BuildableName = "%s" BlueprintName = "%s" '
            'ReferencedContainer = "container:%s"></BuildableReference>'
            % (tid, product_name, name, container))


def scheme(name, build, test=None, run=None, directory=None, arguments=None):
    entries = "".join(
        '<BuildActionEntry buildForTesting = "YES" buildForRunning = "YES" buildForProfiling = "YES" '
        'buildForArchiving = "YES" buildForAnalyzing = "YES">%s</BuildActionEntry>' % r for r in build)
    testables = ('<TestableReference skipped = "NO">%s</TestableReference>' % test) if test else ""
    runnable = ('<BuildableProductRunnable runnableDebuggingMode = "0">%s</BuildableProductRunnable>' % run) if run else ""
    if arguments:
        runnable += '<CommandLineArguments>%s</CommandLineArguments>' % "".join(
            '<CommandLineArgument argument = "%s" isEnabled = "YES"></CommandLineArgument>' % a for a in arguments)
    workdir = ('useCustomWorkingDirectory = "YES" customWorkingDirectory = "%s"' % directory) if directory \
        else 'useCustomWorkingDirectory = "NO"'

    xml = ('<?xml version="1.0" encoding="UTF-8"?>\n'
           '<Scheme LastUpgradeVersion = "1600" version = "1.7">'
           # One target after another: Xcode would start the targets that
           # read the engine's rows before WorkflowKit has generated its
           # entities' classes, which it does in its Sources step.
           '<BuildAction parallelizeBuildables = "NO" buildImplicitDependencies = "YES">'
           '<BuildActionEntries>%s</BuildActionEntries></BuildAction>'
           '<TestAction buildConfiguration = "Debug" selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB" '
           'selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv = "YES">'
           '<Testables>%s</Testables></TestAction>'
           '<LaunchAction buildConfiguration = "Debug" selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB" '
           'selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB" launchStyle = "0" %s '
           'ignoresPersistentStateOnLaunch = "NO" debugDocumentVersioning = "YES" debugServiceExtension = "internal" '
           'allowLocationSimulation = "YES">%s</LaunchAction>'
           '<ProfileAction buildConfiguration = "Release" shouldUseLaunchSchemeArgsEnv = "YES" savedToolIdentifier = "" '
           'useCustomWorkingDirectory = "NO" debugDocumentVersioning = "YES"></ProfileAction>'
           '<AnalyzeAction buildConfiguration = "Debug"></AnalyzeAction>'
           '<ArchiveAction buildConfiguration = "Release" revealArchiveInOrganizer = "YES"></ArchiveAction>'
           '</Scheme>\n') % (entries, testables, workdir, runnable)
    with open(os.path.join(proj, "xcshareddata", "xcschemes", name + ".xcscheme"), "w") as f:
        f.write(xml)


fw_ref = ref(t_fw, "WorkflowKit", "WorkflowKit.framework")
odata_ref = ref(t_odata, "WorkflowKitOData", "WorkflowKitOData.framework")
tests_ref = ref(t_tests, "WorkflowKitTests", "WorkflowKitTests.xctest")
demo_ref = ref(t_demo, "PurchaseRequestDemo", "PurchaseRequestDemo")
serve_ref = ref(t_serve, "wf-serve", "wf-serve")
scheme("WorkflowKit", [fw_ref, odata_ref], test=tests_ref)
scheme("PurchaseRequestDemo", [demo_ref], run=demo_ref)
# Run from Server/, on the example deployment, as `make -C Server run` does.
scheme("wf-serve", [serve_ref], run=serve_ref, directory="$(PROJECT_DIR)/Server",
       arguments=["-Config Examples/server.plist"])
desk_ref = ref(t_desk, "WorkflowDesk", "WorkflowDesk.app")
desk_tests_ref = ref(t_desk_tests, "WorkflowDeskTests", "WorkflowDeskTests.xctest")
# The frameworks of the projects beside this one that the app embeds, built
# first by name: the IDE does not always find them as implicit dependencies,
# and then compiles the app before their headers are there. Their targets'
# ids are fixed in those projects.
DESK_EXTERNAL = [
    ref("AA0000000000000000000006", "ODataKit", "ODataKit.framework", ODATAKIT + "/ODataKit.xcodeproj"),
    ref("AA0000000000000000000002", "ODataIncrementalStore", "ODataIncrementalStore.framework",
        ODATAKIT + "/ODataKit.xcodeproj"),
    ref("4CBB61F9CEEAF8A9C5A1F7CF", "OTelKit", "OTelKit.framework", ODATAKIT + "/ODataKit.xcodeproj"),
    ref("EE0000010000000000000001", "XFormsKit", "XFormsKit.framework", "../XFormsKit/XFormsKit.xcodeproj"),
]
scheme("WorkflowDesk", DESK_EXTERNAL + [desk_ref], test=desk_tests_ref, run=desk_ref)
designer_ref = ref(t_designer, "WorkflowDesigner", "WorkflowDesigner.app")
designer_tests_ref = ref(t_designer_tests, "WorkflowDesignerTests", "WorkflowDesignerTests.xctest")
scheme("WorkflowDesigner", DESK_EXTERNAL[:3] + [fw_ref, designer_ref], test=designer_tests_ref, run=designer_ref)
print("wrote", proj)
