#!/usr/bin/env python3
"""Adds new Swift files to ChurchTVMac.xcodeproj without XcodeGen (Mac copy of the Remote script).

XcodeGen (project.yml) is the source of truth: `sources: - path: App` includes every file under App/ and Tests/ automatically.
When XcodeGen is not installed, run this script after adding or deleting Swift files:

    cd apple/ChurchTVMac && python3 sync_xcodeproj.py

It makes project.pbxproj contain exactly the .swift files that exist under App/ (app target) and Tests/ (test target), with groups that
mirror the folders (files deleted or moved away, for example into a package, are removed). It also makes sure the app target links the
local ChurchTVEditors package. It is idempotent and keeps existing object ids. Running `xcodegen generate` later gives an equivalent project.
"""
import hashlib, os, re, sys

HERE = os.path.dirname(os.path.abspath(__file__))
PBX = os.path.join(HERE, "ChurchTVMac.xcodeproj", "project.pbxproj")
text = open(PBX).read()


def oid(seed):
    return hashlib.md5(("churchtvmac:" + seed).encode()).hexdigest()[:24].upper()


def section_end(name):
    return text.index("/* End %s section */" % name)


def find_group(path_name):
    """Returns (start, end) of the PBXGroup block whose `path = <path_name>;` (top level App or Tests)."""
    for m in re.finditer(r"\t\t([0-9A-F]{24}) /\* [^*]+ \*/ = \{\n\t\t\tisa = PBXGroup;\n.*?\n\t\t\};\n", text, re.S):
        if re.search(r"\n\t\t\tpath = %s;\n" % re.escape(path_name), m.group(0)):
            return m
    raise SystemExit("group %s not found" % path_name)


def target_sources_phase(target_name):
    m = re.search(r"/\* %s \*/ = \{\n\t\t\tisa = PBXNativeTarget;.*?buildPhases = \(\n(.*?)\t\t\t\);" % re.escape(target_name), text, re.S)
    for line in m.group(1).splitlines():
        mm = re.search(r"([0-9A-F]{24}) /\* Sources \*/", line)
        if mm:
            return mm.group(1)
    raise SystemExit("no Sources phase for " + target_name)


def swift_files(root):
    out = []
    for d, _, files in os.walk(os.path.join(HERE, root)):
        for f in files:
            if f.endswith(".swift"):
                out.append(os.path.relpath(os.path.join(d, f), os.path.join(HERE, root)))
    return sorted(out)


def sync(root, target):
    global text
    wanted = swift_files(root)
    phase = target_sources_phase(target)
    # file references that already exist: (parent group chain unknown) -> by id lookup through name
    for rel in wanted:
        parts = rel.split(os.sep)
        name = parts[-1]
        # ensure group chain
        parent = find_group(root)
        parent_id = parent.group(1)
        chain_seed = root
        for sub in parts[:-1]:
            chain_seed += "/" + sub
            gid = oid("group:" + chain_seed)
            if gid not in text:
                block = "\t\t%s /* %s */ = {\n\t\t\tisa = PBXGroup;\n\t\t\tchildren = (\n\t\t\t);\n\t\t\tpath = %s;\n\t\t\tsourceTree = \"<group>\";\n\t\t};\n" % (gid, sub, sub)
                i = section_end("PBXGroup")
                text = text[:i] + block + text[i:]
                add_child(parent_id, gid, sub)
            parent_id = gid
        file_seed = root + "/" + rel
        # an older ref by plain name (top-level files made by XcodeGen) keeps its id
        existing = re.search(r"\t\t([0-9A-F]{24}) /\* %s \*/ = \{isa = PBXFileReference;[^\n]*path = %s;" % (re.escape(name), re.escape(name)), text)
        if existing and len(parts) == 1:
            continue
        fid = oid("file:" + file_seed)
        if fid in text:
            continue
        ref = "\t\t%s /* %s */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = %s; sourceTree = \"<group>\"; };\n" % (fid, name, name)
        i = section_end("PBXFileReference")
        text = text[:i] + ref + text[i:]
        bid = oid("build:" + file_seed)
        bf = "\t\t%s /* %s in Sources */ = {isa = PBXBuildFile; fileRef = %s /* %s */; };\n" % (bid, name, fid, name)
        i = section_end("PBXBuildFile")
        text = text[:i] + bf + text[i:]
        add_child(parent_id, fid, name)
        add_to_phase(phase, bid, name)
    


def add_child(group_id, child_id, name):
    global text
    m = re.search(r"\t\t%s /\* [^*]+ \*/ = \{\n\t\t\tisa = PBXGroup;\n\t\t\tchildren = \(\n(.*?)\t\t\t\);" % group_id, text, re.S)
    children = m.group(1)
    line = "\t\t\t\t%s /* %s */,\n" % (child_id, name)
    if child_id in children:
        return
    lines = sorted(children.splitlines(keepends=True) + [line], key=lambda l: re.search(r"/\* (.*) \*/", l).group(1).lower())
    text = text[:m.start(1)] + "".join(lines) + text[m.end(1):]


def add_to_phase(phase_id, build_id, name):
    global text
    m = re.search(r"\t\t%s /\* Sources \*/ = \{\n\t\t\tisa = PBXSourcesBuildPhase;\n\t\t\tbuildActionMask = \d+;\n\t\t\tfiles = \(\n(.*?)\t\t\t\);" % phase_id, text, re.S)
    line = "\t\t\t\t%s /* %s in Sources */,\n" % (build_id, name)
    if build_id in m.group(1):
        return
    text = text[:m.end(1)] + line + text[m.end(1):]


def prune(root):
    """Removes file references (and their build files, group entries and empty groups) for .swift files that no longer exist under root."""
    global text
    wanted = set(swift_files(root))
    top = find_group(root)
    removed = 0

    def walk(group_id, prefix):
        nonlocal removed
        global text
        m = re.search(r"\t\t%s /\* [^*]+ \*/ = \{\n\t\t\tisa = PBXGroup;\n\t\t\tchildren = \(\n(.*?)\t\t\t\);" % group_id, text, re.S)
        for line in m.group(1).splitlines():
            cm = re.search(r"([0-9A-F]{24}) /\* ([^*]+) \*/", line)
            if not cm:
                continue
            cid, cname = cm.group(1), cm.group(2)
            if re.search(r"\t\t%s /\* [^*]+ \*/ = \{\n\t\t\tisa = PBXGroup;" % cid, text):
                walk(cid, prefix + cname + "/")
            elif cname.endswith(".swift") and (prefix + cname) not in wanted:
                drop_file(group_id, cid)
                removed += 1
        # drop the group when it became empty
        m2 = re.search(r"\t\t%s /\* [^*]+ \*/ = \{\n\t\t\tisa = PBXGroup;\n\t\t\tchildren = \(\n(.*?)\t\t\t\);" % group_id, text, re.S)
        if not m2.group(1).strip() and group_id != top.group(1):
            gm = re.search(r"\t\t%s /\* [^*]+ \*/ = \{\n\t\t\tisa = PBXGroup;.*?\n\t\t\};\n" % group_id, text, re.S)
            text = text[:gm.start()] + text[gm.end():]
            text = re.sub(r"\t\t\t\t%s /\* [^*]+ \*/,\n" % group_id, "", text)

    walk(top.group(1), "")
    return removed


def drop_file(group_id, file_id):
    global text
    text = re.sub(r"\t\t\t\t%s /\* [^*]+ \*/,\n" % file_id, "", text)
    text = re.sub(r"\t\t%s /\* [^*]+ \*/ = \{isa = PBXFileReference;[^\n]*\n" % file_id, "", text)
    for bm in re.finditer(r"\t\t([0-9A-F]{24}) /\* [^*]+ in Sources \*/ = \{isa = PBXBuildFile; fileRef = %s [^\n]*\n" % file_id, text):
        bid = bm.group(1)
        text = text.replace(bm.group(0), "")
        text = re.sub(r"\t\t\t\t%s /\* [^*]+ in Sources \*/,\n" % bid, "", text)
        break


def sync_package(rel_path, product):
    """Makes the app target depend on the local Swift package at rel_path (relative to this folder) with the given library product."""
    global text
    ref_id = oid("pkgref:" + rel_path)
    if ref_id in text:
        return
    dep_id = oid("pkgdep:" + product)
    build_id = oid("pkgbuild:" + product)
    file_id = oid("pkgfolder:" + product)
    text = text.replace("/* End XCLocalSwiftPackageReference section */",
        "\t\t%s /* XCLocalSwiftPackageReference \"%s\" */ = {\n\t\t\tisa = XCLocalSwiftPackageReference;\n\t\t\trelativePath = %s;\n\t\t};\n/* End XCLocalSwiftPackageReference section */" % (ref_id, rel_path, rel_path))
    text = text.replace("/* End XCSwiftPackageProductDependency section */",
        "\t\t%s /* %s */ = {\n\t\t\tisa = XCSwiftPackageProductDependency;\n\t\t\tproductName = %s;\n\t\t};\n/* End XCSwiftPackageProductDependency section */" % (dep_id, product, product))
    text = text.replace("/* End PBXBuildFile section */",
        "\t\t%s /* %s in Frameworks */ = {isa = PBXBuildFile; productRef = %s /* %s */; };\n/* End PBXBuildFile section */" % (build_id, product, dep_id, product))
    name = os.path.basename(rel_path)
    text = text.replace("/* End PBXFileReference section */",
        "\t\t%s /* %s */ = {isa = PBXFileReference; lastKnownFileType = folder; name = %s; path = %s; sourceTree = SOURCE_ROOT; };\n/* End PBXFileReference section */" % (file_id, name, name, rel_path))
    # Packages group, Frameworks phase, target dependencies, project package references (all belong to the app target)
    text = re.sub(r"(/\* Packages \*/ = \{\n\t\t\tisa = PBXGroup;\n\t\t\tchildren = \(\n)", r"\g<1>\t\t\t\t%s /* %s */,\n" % (file_id, name), text, count=1)
    text = re.sub(r"(isa = PBXFrameworksBuildPhase;\n\t\t\tbuildActionMask = \d+;\n\t\t\tfiles = \(\n)", r"\g<1>\t\t\t\t%s /* %s in Frameworks */,\n" % (build_id, product), text, count=1)
    text = re.sub(r"(name = ChurchTVMac;\n\t\t\tpackageProductDependencies = \(\n)", r"\g<1>\t\t\t\t%s /* %s */,\n" % (dep_id, product), text, count=1)
    text = re.sub(r"(packageReferences = \(\n)", (lambda m: m.group(1) + '\t\t\t\t%s /* XCLocalSwiftPackageReference "%s" */,\n' % (ref_id, rel_path)), text, count=1)


sync_package("../ChurchTVEditors", "ChurchTVEditors")
sync_package("../ChurchTVCalendar", "ChurchTVCalendar")
sync("App", "ChurchTVMac")
pruned = prune("App")
if pruned:
    print("removed %d stale file references" % pruned)
open(PBX, "w").write(text)
print("project.pbxproj is in sync with App/")
