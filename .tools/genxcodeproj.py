#!/usr/bin/env python3
"""Write UDWorkflow.xcodeproj from the same source lists the GNUmakefiles use.

    python3 .tools/genxcodeproj.py

Regenerate after adding a source file rather than editing project.pbxproj by
hand; object ids are derived from names, so the output is stable and diffs
stay small. GNUstep does not read any of this -- it builds with make.
"""
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


SOURCES = make_list("GNUmakefile", "UDWorkflow_OBJC_FILES")            # Source/X.m
HEADERS = make_list("GNUmakefile", "UDWorkflow_HEADER_FILES")          # X.h
TESTS = make_list("Tests/GNUmakefile", "UDWorkflowTests_OBJC_FILES")   # X.m
DEMO = make_list("Examples/GNUmakefile", "PurchaseRequestDemo_OBJC_FILES")
MODELS = make_list("GNUmakefile", "UDWorkflow_XCDATAMODELD_FILES")     # Model/X.xcdatamodeld
DOCS = ["CLAUDE.md", "UDWorkflow-BPMN-Subset.md", "GNUmakefile"]
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
        ".m": "sourcecode.c.objc", ".h": "sourcecode.c.h",
        ".md": "net.daringfireball.markdown", ".xcconfig": "text.xcconfig",
    }.get(os.path.splitext(name)[1], "text")


src_refs = {s: fileref(s, os.path.basename(s), ftype(s)) for s in SOURCES}
hdr_refs = {h: fileref("Headers/" + h, h, ftype(h)) for h in HEADERS}
test_refs = {t: fileref("Tests/" + t, t, ftype(t)) for t in TESTS}
demo_refs = {d: fileref("Examples/" + d, d, ftype(d)) for d in DEMO}
doc_refs = {d: fileref(d, d, ftype(d)) for d in DOCS}
cfg_refs = {c: fileref("Xcode/Configs/" + c, c, "text.xcconfig") for c in CONFIGS}



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


p_fw = product("UDWorkflow", ".framework", "wrapper.framework")
p_tests = product("UDWorkflowTests", ".xctest", "wrapper.cfbundle")
p_demo = product("PurchaseRequestDemo", "", '"compiled.mach-o.executable"')


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


fw_sources = phase("PBXSourcesBuildPhase", "UDWorkflow", "Sources", names(
    [buildfile("UDWorkflow", src_refs[s], os.path.basename(s)) for s in SOURCES] +
    [buildfile("UDWorkflow", model_refs[m], os.path.basename(m)) for m in MODELS]))
fw_headers = phase("PBXHeadersBuildPhase", "UDWorkflow", "Headers", names(
    [buildfile("UDWorkflow", hdr_refs[h], h, "{ATTRIBUTES = (Public, ); }") for h in HEADERS]))
fw_frameworks = phase("PBXFrameworksBuildPhase", "UDWorkflow", "Frameworks", names(
    [buildfile("UDWorkflow", foundation, "Foundation.framework"),
     buildfile("UDWorkflow", coredata, "CoreData.framework")]))

t_sources = phase("PBXSourcesBuildPhase", "UDWorkflowTests", "Sources", names(
    [buildfile("UDWorkflowTests", test_refs[t], t) for t in TESTS]))
t_frameworks = phase("PBXFrameworksBuildPhase", "UDWorkflowTests", "Frameworks", names(
    [buildfile("UDWorkflowTests", p_fw, "UDWorkflow.framework")]))

d_sources = phase("PBXSourcesBuildPhase", "PurchaseRequestDemo", "Sources", names(
    [buildfile("PurchaseRequestDemo", demo_refs[d], d) for d in DEMO]))
d_frameworks = phase("PBXFrameworksBuildPhase", "PurchaseRequestDemo", "Frameworks", names(
    [buildfile("PurchaseRequestDemo", p_fw, "UDWorkflow.framework")]))


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
g_tests = group("Tests", "Tests", [test_refs[t] for t in TESTS], "Tests")
g_examples = group("Examples", "Examples", [demo_refs[d] for d in DEMO], "Examples")
g_model = group("Model", "Model", [model_refs[m] for m in MODELS], "Model")
g_configs = group("Configs", "Configs", [cfg_refs[c] for c in CONFIGS], "Xcode/Configs")
g_products = group("Products", "Products", [p_fw, p_tests, p_demo])
g_frameworks = group("Frameworks", "Frameworks", [foundation, coredata])
g_main = group("main", "UDWorkflow", [doc_refs[d] for d in DOCS] +
               [g_headers, g_source, g_model, g_tests, g_examples, g_configs, g_frameworks, g_products])
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
    "PRODUCT_BUNDLE_IDENTIFIER": "local.udworkflow.UDWorkflow",
    "SKIP_INSTALL": "YES",
    "HEADER_SEARCH_PATHS": '"$(SRCROOT)/Headers"',
}
TESTS_S = {
    "PRODUCT_BUNDLE_IDENTIFIER": "local.udworkflow.UDWorkflowTests",
    "HEADER_SEARCH_PATHS": '"$(SRCROOT)/Headers"',
    "LD_RUNPATH_SEARCH_PATHS": '("$(inherited)", "@executable_path/../Frameworks", "@loader_path/../Frameworks")',
}
DEMO_S = {
    "HEADER_SEARCH_PATHS": '"$(SRCROOT)/Headers"',
    "LD_RUNPATH_SEARCH_PATHS": '("$(inherited)", "@executable_path", "@loader_path")',
}


def settings(d):
    return "{\n" + "".join("\t\t\t\t%s = %s;\n" % (k, v) for k, v in sorted(d.items())) + "\t\t\t}"


cl_project = configs("project", "{\n\t\t\t}", "{\n\t\t\t}")
cl_fw = configs("UDWorkflow", settings(FW), settings(FW))
cl_tests = configs("UDWorkflowTests", settings(TESTS_S), settings(TESTS_S))
cl_demo = configs("PurchaseRequestDemo", settings(DEMO_S), settings(DEMO_S))

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


t_fw = oid("target", "UDWorkflow")
t_fw = target("UDWorkflow", cl_fw, [fw_headers, fw_sources, fw_frameworks], [],
              p_fw, "com.apple.product-type.framework")
t_tests = target("UDWorkflowTests", cl_tests, [t_sources, t_frameworks],
                 [dependency("UDWorkflowTests", t_fw, "UDWorkflow")],
                 p_tests, "com.apple.product-type.bundle.unit-test")
t_demo = target("PurchaseRequestDemo", cl_demo, [d_sources, d_frameworks],
                [dependency("PurchaseRequestDemo", t_fw, "UDWorkflow")],
                p_demo, "com.apple.product-type.tool")

add(project_id, "Project object", [
    ("isa", "PBXProject"),
    ("attributes", "{\n\t\t\t\tBuildIndependentTargetsInParallel = 1;\n\t\t\t\tLastUpgradeCheck = 1600;\n\t\t\t}"),
    ("buildConfigurationList", '%s /* Build configuration list for PBXProject "UDWorkflow" */' % cl_project),
    ("compatibilityVersion", '"Xcode 14.0"'),
    ("developmentRegion", "en"),
    ("hasScannedForEncodings", "0"),
    ("knownRegions", ["en", "Base"]),
    ("mainGroup", g_main),
    ("productRefGroup", "%s /* Products */" % g_products),
    ("projectDirPath", '""'),
    ("projectRoot", '""'),
    ("targets", names([t_fw, t_tests, t_demo])),
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


proj = os.path.join(ROOT, "UDWorkflow.xcodeproj")
os.makedirs(os.path.join(proj, "xcshareddata", "xcschemes"), exist_ok=True)
with open(os.path.join(proj, "project.pbxproj"), "w") as f:
    f.write(render())


# ---------------------------------------------------------------- schemes
def ref(tid, name, product_name):
    return ('<BuildableReference BuildableIdentifier = "primary" BlueprintIdentifier = "%s" '
            'BuildableName = "%s" BlueprintName = "%s" '
            'ReferencedContainer = "container:UDWorkflow.xcodeproj"></BuildableReference>'
            % (tid, product_name, name))


def scheme(name, build, test=None, run=None):
    entries = "".join(
        '<BuildActionEntry buildForTesting = "YES" buildForRunning = "YES" buildForProfiling = "YES" '
        'buildForArchiving = "YES" buildForAnalyzing = "YES">%s</BuildActionEntry>' % r for r in build)
    testables = ('<TestableReference skipped = "NO">%s</TestableReference>' % test) if test else ""
    runnable = ('<BuildableProductRunnable runnableDebuggingMode = "0">%s</BuildableProductRunnable>' % run) if run else ""
    xml = ('<?xml version="1.0" encoding="UTF-8"?>\n'
           '<Scheme LastUpgradeVersion = "1600" version = "1.7">'
           '<BuildAction parallelizeBuildables = "YES" buildImplicitDependencies = "YES">'
           '<BuildActionEntries>%s</BuildActionEntries></BuildAction>'
           '<TestAction buildConfiguration = "Debug" selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB" '
           'selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv = "YES">'
           '<Testables>%s</Testables></TestAction>'
           '<LaunchAction buildConfiguration = "Debug" selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB" '
           'selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB" launchStyle = "0" useCustomWorkingDirectory = "NO" '
           'ignoresPersistentStateOnLaunch = "NO" debugDocumentVersioning = "YES" debugServiceExtension = "internal" '
           'allowLocationSimulation = "YES">%s</LaunchAction>'
           '<ProfileAction buildConfiguration = "Release" shouldUseLaunchSchemeArgsEnv = "YES" savedToolIdentifier = "" '
           'useCustomWorkingDirectory = "NO" debugDocumentVersioning = "YES"></ProfileAction>'
           '<AnalyzeAction buildConfiguration = "Debug"></AnalyzeAction>'
           '<ArchiveAction buildConfiguration = "Release" revealArchiveInOrganizer = "YES"></ArchiveAction>'
           '</Scheme>\n') % (entries, testables, runnable)
    with open(os.path.join(proj, "xcshareddata", "xcschemes", name + ".xcscheme"), "w") as f:
        f.write(xml)


fw_ref = ref(t_fw, "UDWorkflow", "UDWorkflow.framework")
tests_ref = ref(t_tests, "UDWorkflowTests", "UDWorkflowTests.xctest")
demo_ref = ref(t_demo, "PurchaseRequestDemo", "PurchaseRequestDemo")
scheme("UDWorkflow", [fw_ref], test=tests_ref)
scheme("PurchaseRequestDemo", [demo_ref], run=demo_ref)
print("wrote", proj)
