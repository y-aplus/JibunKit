#!/usr/bin/env python3
"""Turn a crash report shared from JibunKit into function names and lines.

  python3 Tools/symbolicate-crash.py REPORT.json [--dsyms DIR] [--repo OWNER/REPO]

REPORT.json is the file shared from Manage Mini Apps > Crash Reports (or a
plain MetricKit diagnostic payload). Its call stacks name each frame only by
binary UUID and offset. This finds the build's symbol files by those UUIDs:
in --dsyms (a directory of .dSYM bundles or JibunKit-dSYMs.zip files), or else
in the JibunKit-dSYMs.zip of the newest `build-RUN_ID` prereleases of the
`origin` repository (or --repo), which the quick build attaches; downloads are
kept under build/dsyms/. Frames are then resolved with `llvm-symbolizer`
(or `atos` on macOS), which a Swift toolchain includes.

Only the five newest build prereleases are kept, so symbolicate a report
before five newer builds replace the one that crashed.
"""
import argparse
import json
import os
from pathlib import Path
import shutil
import struct
import subprocess
import sys
import zipfile

ROOT = Path(__file__).resolve().parents[1]
CACHE = ROOT / "build" / "dsyms"
ZIP_NAME = "JibunKit-dSYMs.zip"
FRAMES = 40

LC_SEGMENT_64 = 0x19
LC_UUID = 0x1B
MH_MAGIC_64 = 0xFEEDFACF
FAT_MAGIC = 0xCAFEBABE
CPU_TYPE_ARM64 = 0x0100000C


class Failure(Exception):
    pass


def macho_slices(data):
    """[(uuid, __TEXT vmaddr)] for each 64-bit slice of a Mach-O or fat file."""
    if len(data) < 8:
        return []
    if struct.unpack(">I", data[:4])[0] == FAT_MAGIC:
        count = struct.unpack(">I", data[4:8])[0]
        slices = []
        for index in range(count):
            cpu, _, offset, size, _ = struct.unpack(">iiIII", data[8 + 20 * index:28 + 20 * index])
            if cpu == CPU_TYPE_ARM64:
                slices += macho_slices(data[offset:offset + size])
        return slices
    if struct.unpack("<I", data[:4])[0] != MH_MAGIC_64:
        return []
    ncmds = struct.unpack("<I", data[16:20])[0]
    offset, uuid, text = 32, None, 0
    for _ in range(ncmds):
        cmd, size = struct.unpack("<II", data[offset:offset + 8])
        if cmd == LC_UUID:
            raw = data[offset + 8:offset + 24].hex().upper()
            uuid = f"{raw[:8]}-{raw[8:12]}-{raw[12:16]}-{raw[16:20]}-{raw[20:]}"
        elif cmd == LC_SEGMENT_64 and data[offset + 8:offset + 24].rstrip(b"\0") == b"__TEXT":
            text = struct.unpack("<Q", data[offset + 24:offset + 32])[0]
        offset += size
    return [(uuid, text)] if uuid else []


def dwarf_files(directory):
    """{uuid: (DWARF file, __TEXT vmaddr)} for the .dSYM bundles under `directory`."""
    found = {}
    for path in Path(directory).glob("**/*.dSYM/Contents/Resources/DWARF/*"):
        for uuid, text in macho_slices(path.read_bytes()):
            found[uuid] = (path, text)
    return found


def unpack(zip_path, into):
    into.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(zip_path) as archive:
        for member in archive.namelist():
            target = (into / member).resolve()
            if not str(target).startswith(str(into.resolve())):
                raise Failure(f"{zip_path} has an unsafe path: {member}")
        archive.extractall(into)


def payload_of(report):
    """The MetricKit payload inside a shared report, or the report itself."""
    return report.get("payload", report)


def stacks(payload):
    """[(kind, metadata, [frames from the top])] for every diagnostic with a call stack."""
    found = []
    for key, kind in (("crashDiagnostics", "Crash"), ("hangDiagnostics", "Hang")):
        for diagnostic in payload.get(key) or []:
            tree = diagnostic.get("callStackTree") or {}
            metadata = diagnostic.get("diagnosticMetaData") or {}
            threads = tree.get("callStacks") or []
            # The thread that crashed or hung; otherwise the first.
            chosen = next((thread for thread in threads if thread.get("threadAttributed")), threads[0] if threads else {})
            frames = []
            level = chosen.get("callStackRootFrames") or []
            while level and len(frames) < FRAMES:
                frame = max(level, key=lambda item: item.get("sampleCount", 0))
                frames.append(frame)
                level = frame.get("subFrames") or []
            found.append((kind, metadata, frames))
    return found


def needed_uuids(payload):
    return {frame.get("binaryUUID", "").upper() for _, _, frames in stacks(payload) for frame in frames} - {""}


def symbolizer():
    for name in ("llvm-symbolizer", "atos"):
        if shutil.which(name):
            return name
    raise Failure("No llvm-symbolizer or atos found; install a Swift toolchain or Xcode.")


def symbolicate(tool, dwarf, addresses):
    """{address: [lines]} for addresses in one binary, innermost inlined function first."""
    if tool == "atos":
        output = subprocess.run(["atos", "-o", str(dwarf), *[hex(address) for address in addresses]],
                                capture_output=True, text=True, check=True).stdout.splitlines()
        return {address: [line] for address, line in zip(addresses, output)}
    # Addresses are virtual addresses in the file: __TEXT's vmaddr plus the offset.
    # Names stay mangled here so that `swift demangle --simplified` can shorten them.
    output = subprocess.run([tool, "--obj", str(dwarf), "--no-demangle", *[hex(address) for address in addresses]],
                            capture_output=True, text=True, check=True).stdout
    results = {}
    for address, block in zip(addresses, output.strip().split("\n\n")):
        lines = block.splitlines()
        names = simplify([lines[index] for index in range(0, len(lines) - 1, 2)])
        places = [place(lines[index]) for index in range(1, len(lines), 2)]
        results[address] = [f"{name}{f' ({where})' if where else ''}" for name, where in zip(names, places)] or ["?"]
    return results


def place(location):
    """`file:line` relative to the repository the build ran in, or "" when the compiler recorded none."""
    path, _, rest = location.partition(":")
    line = rest.split(":")[0]
    if line in ("", "0") or path.startswith("<"):
        return ""
    marker = "/work/"
    if marker in path:
        # GitHub checks the repository out at /Users/runner/work/REPO/REPO/.
        parts = path.split(marker, 1)[1].split("/")
        path = "/".join(parts[2:]) or path
    return f"{path}:{line}"


def simplify(names):
    """Short Swift names (`closure #2 in CounterRootView.body.getter`) through `swift demangle`."""
    tool = shutil.which("swift-demangle") or shutil.which("swift")
    if not tool or not names:
        return names
    command = [tool] if Path(tool).stem == "swift-demangle" else [tool, "demangle"]
    result = subprocess.run([*command, "--simplified"], input="\n".join(names), capture_output=True, text=True)
    simplified = result.stdout.splitlines()
    return simplified if result.returncode == 0 and len(simplified) == len(names) else names


def describe(report, symbols, resolve):
    """The report as text. `resolve(dwarf, addresses)` returns {address: [lines]}."""
    payload = payload_of(report)
    out = []
    for key in ("receivedAt", "appVersion", "miniApp"):
        if report.get(key):
            out.append(f"{key}: {report[key]}")
    for line in report.get("summary", []):
        out.append(line)
    for kind, metadata, frames in stacks(payload):
        out.append("")
        details = ", ".join(f"{key} {metadata[key]}" for key in ("exceptionType", "signal", "terminationReason",
                                                                  "osVersion", "deviceType") if key in metadata)
        out.append(f"{kind}" + (f" ({details})" if details else ""))
        resolved = {}
        by_binary = {}
        for frame in frames:
            uuid = frame.get("binaryUUID", "").upper()
            if uuid in symbols:
                by_binary.setdefault(uuid, []).append(frame)
        for uuid, owned in by_binary.items():
            dwarf, text = symbols[uuid]
            addresses = [text + frame.get("offsetIntoBinaryTextSegment", 0) for frame in owned]
            names = resolve(dwarf, addresses)
            for frame, address in zip(owned, addresses):
                resolved[id(frame)] = names.get(address, ["?"])
        for index, frame in enumerate(frames):
            binary = frame.get("binaryName", "?")
            names = resolved.get(id(frame))
            if names:
                out.append(f"{index:>3}  {binary}  {names[0]}")
                out += [f"     {binary}  inlined into the above: {name}" for name in names[1:]]
            else:
                out.append(f"{index:>3}  {binary}  +0x{frame.get('offsetIntoBinaryTextSegment', 0):x}")
    return "\n".join(out)


def fetch_dsyms(repo, needed):
    """Download JibunKit-dSYMs.zip from the newest build prereleases until every needed UUID is found."""
    if not shutil.which("gh"):
        raise Failure("Pass --dsyms, or install the GitHub CLI `gh` to download the symbol files.")
    command = ["gh", "release", "list", "--limit", "50", "--json", "tagName,isPrerelease,createdAt"]
    if repo:
        command += ["--repo", repo]
    releases = json.loads(subprocess.run(command, cwd=ROOT, capture_output=True, text=True, check=True).stdout)
    tags = [release["tagName"] for release in sorted(releases, key=lambda release: release["createdAt"], reverse=True)
            if release["isPrerelease"] and release["tagName"].startswith("build-")]
    found = {}
    for tag in tags:
        directory = CACHE / tag
        if not directory.is_dir():
            download = ["gh", "release", "download", tag, "--pattern", ZIP_NAME, "--dir", str(directory)]
            if repo:
                download += ["--repo", repo]
            if subprocess.run(download, cwd=ROOT, capture_output=True, text=True).returncode != 0:
                continue
            unpack(directory / ZIP_NAME, directory)
        found.update(dwarf_files(directory))
        if needed & found.keys():
            break
    return found


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("report", type=Path, help="The shared crash report (JSON)")
    parser.add_argument("--dsyms", type=Path, help="A directory of .dSYM bundles or JibunKit-dSYMs.zip files")
    parser.add_argument("--repo", help="OWNER/REPO whose build prereleases hold the symbol files (default: origin)")
    args = parser.parse_args(argv)

    report = json.loads(args.report.read_text(encoding="utf-8"))
    needed = needed_uuids(payload_of(report))
    if args.dsyms:
        for archive in args.dsyms.glob("*.zip"):
            unpack(archive, args.dsyms / archive.stem)
        symbols = dwarf_files(args.dsyms)
    else:
        symbols = fetch_dsyms(args.repo, needed)
    tool = symbolizer()

    print(describe(report, symbols, lambda dwarf, addresses: symbolicate(tool, dwarf, addresses)))
    if needed and not needed & symbols.keys():
        print("\nNo symbol files matched this report; it may come from a build whose prerelease was already "
              "deleted, or from a build made elsewhere.", file=sys.stderr)
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Failure as error:
        print(f"error: {error}", file=sys.stderr)
        sys.exit(1)
