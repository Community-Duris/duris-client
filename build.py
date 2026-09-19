#!/usr/bin/env python3
"""Assemble `Arjinius Client.mpackage` from the sources under src/.

    python3 build.py            # build to ./Arjinius Client.mpackage
    python3 build.py --check    # syntax-check the Lua only (needs luac)
    python3 build.py -o path    # build somewhere else

Layout:
    VERSION                 single source of truth for the package version
    src/package.xml         Mudlet XML skeleton; each <script> body is a
                            @@SCRIPT:<Name>@@ placeholder
    src/scripts/<Name>.lua  script bodies, one per <Script> element
    src/config.lua          package metadata; `version` is rewritten from VERSION
    src/assets/             everything else that goes in the zip, verbatim

The build injects VERSION into config.lua and into any Lua line of the form
`<Name>.VERSION = "..."`, escapes each script into its placeholder, validates the
XML, and writes a *stored* (uncompressed) zip, which is what Mudlet expects.
"""

import argparse
import os
import re
import subprocess
import sys
import xml.etree.ElementTree as ET
import zipfile
from xml.sax.saxutils import escape

ROOT = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(ROOT, "src")
PACKAGE_NAME = "Arjinius Client"
PLACEHOLDER = re.compile(r"@@SCRIPT:([A-Za-z0-9_]+)@@")


def read(path, mode="r"):
    with open(path, mode, encoding=None if "b" in mode else "utf-8") as fh:
        return fh.read()


def version():
    v = read(os.path.join(ROOT, "VERSION")).strip()
    if not re.fullmatch(r"\d+(\.\d+)*", v):
        sys.exit(f"VERSION must look like 1.2.3, got {v!r}")
    return v


def lua_sources():
    d = os.path.join(SRC, "scripts")
    return {f[:-4]: os.path.join(d, f) for f in sorted(os.listdir(d)) if f.endswith(".lua")}


def check_lua(paths):
    luac = None
    for cand in ("luac5.1", "luac", "luac5.3", "luac5.4"):
        if subprocess.run(["which", cand], capture_output=True).returncode == 0:
            luac = cand
            break
    if not luac:
        print("warning: no luac found, skipping Lua syntax check", file=sys.stderr)
        return True
    ok = True
    for p in paths:
        r = subprocess.run([luac, "-p", p], capture_output=True, text=True)
        if r.returncode != 0:
            ok = False
            print(r.stderr.strip(), file=sys.stderr)
    return ok


def inject_version(lua, name, v):
    pat = re.compile(rf'^({re.escape(name)}\.VERSION\s*=\s*")[^"]*(")', re.M)
    return pat.sub(rf"\g<1>{v}\g<2>", lua)


def build_xml(v):
    skeleton = read(os.path.join(SRC, "package.xml"))
    sources = lua_sources()
    seen = set()

    def fill(m):
        name = m.group(1)
        if name not in sources:
            sys.exit(f"package.xml references script {name!r} but src/scripts/{name}.lua is missing")
        seen.add(name)
        return escape(inject_version(read(sources[name]), name, v))

    xml = PLACEHOLDER.sub(fill, skeleton)
    unused = set(sources) - seen
    if unused:
        sys.exit(f"scripts with no placeholder in package.xml: {sorted(unused)}")
    ET.fromstring(xml.encode("utf-8"))  # must be well-formed
    return xml


def build_config(v):
    cfg = read(os.path.join(SRC, "config.lua"))
    cfg, n = re.subn(r"^version = \[\[[^\]]*\]\]$", f"version = [[{v}]]", cfg, flags=re.M)
    if n != 1:
        sys.exit("config.lua must contain exactly one `version = [[...]]` line")
    return cfg


def asset_files():
    base = os.path.join(SRC, "assets")
    for dirpath, _, files in os.walk(base):
        for f in sorted(files):
            full = os.path.join(dirpath, f)
            yield os.path.relpath(full, base), full


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("-o", "--output", default=os.path.join(ROOT, f"{PACKAGE_NAME}.mpackage"))
    ap.add_argument("--check", action="store_true", help="only syntax-check the Lua")
    args = ap.parse_args()

    v = version()
    if not check_lua(lua_sources().values()):
        sys.exit("Lua syntax check failed")
    if args.check:
        print("Lua OK")
        return

    xml = build_xml(v)
    cfg = build_config(v)

    tmp = args.output + ".tmp"
    with zipfile.ZipFile(tmp, "w", compression=zipfile.ZIP_STORED) as z:
        z.writestr(f"{PACKAGE_NAME}.xml", xml.encode("utf-8"))
        z.writestr("config.lua", cfg.encode("utf-8"))
        for rel, full in asset_files():
            z.write(full, rel.replace(os.sep, "/"))
    os.replace(tmp, args.output)
    print(f"built {args.output} (version {v})")


if __name__ == "__main__":
    main()
