import importlib.util
from pathlib import Path
import struct
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("symbolicate_crash", ROOT / "Tools/symbolicate-crash.py")
symbolicate_crash = importlib.util.module_from_spec(spec)
spec.loader.exec_module(symbolicate_crash)

UUID = "0123456789ABCDEF0123456789ABCDEF"
UUID_TEXT = "01234567-89AB-CDEF-0123-456789ABCDEF"


def macho(uuid=UUID, text=0x100000000):
    """A minimal arm64 Mach-O with a __TEXT segment and an LC_UUID."""
    segment = struct.pack("<II16sQQQQiiII", 0x19, 72, b"__TEXT", text, 0x4000, 0, 0x4000, 5, 5, 0, 0)
    uuid_command = struct.pack("<II", 0x1B, 24) + bytes.fromhex(uuid)
    header = struct.pack("<IiiIIIII", 0xFEEDFACF, 0x0100000C, 0, 0xA, 2, len(segment) + len(uuid_command), 0, 0)
    return header + segment + uuid_command


def fat(slice_data):
    offset = 4096
    header = struct.pack(">II", 0xCAFEBABE, 1) + struct.pack(">iiIII", 0x0100000C, 0, offset, len(slice_data), 12)
    return header + b"\0" * (offset - len(header)) + slice_data


REPORT = {
    "receivedAt": "2026-10-12T10:00:00Z",
    "appVersion": "1.2.0 (5)",
    "miniApp": "notes",
    "summary": ["EXC_BREAKPOINT / SIGTRAP"],
    "payload": {"crashDiagnostics": [{
        "diagnosticMetaData": {"exceptionType": 6, "signal": 5, "osVersion": "iPhone OS 26.0"},
        "callStackTree": {"callStackPerThread": True, "callStacks": [
            {"threadAttributed": False, "callStackRootFrames": [
                {"binaryUUID": "AAAA", "binaryName": "libsystem_kernel.dylib", "offsetIntoBinaryTextSegment": 4}]},
            {"threadAttributed": True, "callStackRootFrames": [
                {"binaryUUID": "FFFF", "binaryName": "libswiftCore.dylib", "offsetIntoBinaryTextSegment": 0x10,
                 "sampleCount": 1, "subFrames": [
                     {"binaryUUID": UUID_TEXT.lower(), "binaryName": "JibunKit_App", "offsetIntoBinaryTextSegment": 0x200,
                      "sampleCount": 1, "subFrames": [
                          {"binaryUUID": UUID_TEXT, "binaryName": "JibunKit_App", "offsetIntoBinaryTextSegment": 0x300,
                           "sampleCount": 1}]}]}]},
        ]},
    }]},
}


class MachOTests(unittest.TestCase):
    def test_reads_uuid_and_text_address(self):
        self.assertEqual(symbolicate_crash.macho_slices(macho()), [(UUID_TEXT, 0x100000000)])
        self.assertEqual(symbolicate_crash.macho_slices(fat(macho(text=0))), [(UUID_TEXT, 0)])
        self.assertEqual(symbolicate_crash.macho_slices(b"not a binary"), [])

    def test_finds_dwarf_files_in_dsym_bundles(self):
        with tempfile.TemporaryDirectory() as temporary:
            dwarf = Path(temporary) / "JibunKit_App.app.dSYM/Contents/Resources/DWARF/JibunKit_App"
            dwarf.parent.mkdir(parents=True)
            dwarf.write_bytes(macho())
            self.assertEqual(symbolicate_crash.dwarf_files(temporary), {UUID_TEXT: (dwarf, 0x100000000)})


class ReportTests(unittest.TestCase):
    def test_follows_the_attributed_thread_from_the_top(self):
        [(kind, metadata, frames)] = symbolicate_crash.stacks(REPORT["payload"])
        self.assertEqual(kind, "Crash")
        self.assertEqual(metadata["signal"], 5)
        self.assertEqual([frame["offsetIntoBinaryTextSegment"] for frame in frames], [0x10, 0x200, 0x300])
        self.assertEqual(symbolicate_crash.needed_uuids(REPORT["payload"]), {"FFFF", UUID_TEXT})

    def test_resolves_own_frames_and_leaves_system_frames_as_offsets(self):
        calls = []

        def resolve(dwarf, addresses):
            calls.append((dwarf, addresses))
            return {0x100000200: ["NotesStore.load() (NotesStore.swift:42:7)", "NotesView.body.getter (NotesView.swift:9:1)"],
                    0x100000300: ["NotesView.body.getter (NotesView.swift:12:5)"]}

        text = symbolicate_crash.describe(REPORT, {UUID_TEXT: ("dwarf", 0x100000000)}, resolve)
        self.assertEqual(calls, [("dwarf", [0x100000200, 0x100000300])])
        self.assertEqual(text.splitlines(), [
            "receivedAt: 2026-10-12T10:00:00Z",
            "appVersion: 1.2.0 (5)",
            "miniApp: notes",
            "EXC_BREAKPOINT / SIGTRAP",
            "",
            "Crash (exceptionType 6, signal 5, osVersion iPhone OS 26.0)",
            "  0  libswiftCore.dylib  +0x10",
            "  1  JibunKit_App  NotesStore.load() (NotesStore.swift:42:7)",
            "     JibunKit_App  inlined into the above: NotesView.body.getter (NotesView.swift:9:1)",
            "  2  JibunKit_App  NotesView.body.getter (NotesView.swift:12:5)",
        ])

    def test_places_are_relative_to_the_checkout(self):
        self.assertEqual(symbolicate_crash.place("/Users/runner/work/JibunKit/JibunKit/Sources/A/B.swift:39:12"),
                         "Sources/A/B.swift:39")
        self.assertEqual(symbolicate_crash.place("/Users/me/Host/Sources/A/B.swift:7:1"), "/Users/me/Host/Sources/A/B.swift:7")
        self.assertEqual(symbolicate_crash.place("/Users/runner/work/JibunKit/JibunKit/<stdin>:0:0"), "")
        self.assertEqual(symbolicate_crash.place("??:0:0"), "")

    def test_a_plain_payload_works_too(self):
        text = symbolicate_crash.describe(REPORT["payload"], {}, lambda dwarf, addresses: {})
        self.assertIn("  1  JibunKit_App  +0x200", text.splitlines())


if __name__ == "__main__":
    unittest.main()
