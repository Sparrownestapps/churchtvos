#!/usr/bin/env python3
"""Adds new Swift files to ChurchTVRemote.xcodeproj without XcodeGen.

XcodeGen (project.yml) is the source of truth: `sources: - path: App` includes every file under App/ and Tests/ automatically.
When XcodeGen is not installed, run this script after adding or deleting Swift files:

    cd apple/ChurchTVRemote && python3 sync_xcodeproj.py

It makes project.pbxproj contain exactly the .swift files that exist under App/ (app target) and Tests/ (test target), with groups that
mirror the folders. It is idempotent and keeps existing object ids. Running `xcodegen generate` later gives an equivalent project.
"""
import hashlib, os, re, sys

HERE = os.path.dirname(os.path.abspath(__file__))
PBX = os.path.join(HERE, "ChurchTVRemote.xcodeproj", "project.pbxproj")
text = open(PBX).read()


def oid(seed):
    return hashlib.md5(("churchtvremote:" + seed).encode()).hexdigest()[:24].upper()


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
    # Files deleted from disk are not removed automatically: delete their lines in project.pbxproj by hand (or regenerate with XcodeGen).


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


sync("App", "ChurchTVRemote")
sync("Tests", "ChurchTVRemoteTests")
open(PBX, "w").write(text)
print("project.pbxproj is in sync with App/ and Tests/")
