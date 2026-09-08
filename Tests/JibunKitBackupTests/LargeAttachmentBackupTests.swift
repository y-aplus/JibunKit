import Foundation
import XCTest
import JibunKitCore
import JibunKitBackup
import RecordsFeature
import RecordsBackupIntegration
#if os(macOS)
import Darwin
#endif

final class LargeAttachmentBackupTests: XCTestCase, @unchecked Sendable {
    func testLargeAttachmentRoundTripWithoutWholeFileData() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let fixture = root.appendingPathComponent("large.bin")
        XCTAssertTrue(FileManager.default.createFile(atPath: fixture.path, contents: nil))
        let writer = try FileHandle(forWritingTo: fixture)
        let chunkSize = 1024 * 1024
        let chunkCount = 128
        do {
            for index in 0..<chunkCount {
                try autoreleasepool { try writer.write(contentsOf: Data(repeating: UInt8(index), count: chunkSize)) }
            }
            try writer.close()
        } catch { try? writer.close(); throw error }
        let source = try RecordStore(directory: root.appendingPathComponent("source"))
        let target = try RecordStore(directory: root.appendingPathComponent("target"))
        let record = Record(title: "Large attachment")
        try await source.save(record)
        let attachment = try await source.importAttachment(to: record.id, from: fixture)
        let id = MiniAppID("records")
        reportPeak("before-export")
        let started = Date()
        let file = try await MiniAppBackupArchive.export(selected: [id], providers: [],
            fileProviders: [RecordsBackup.provider(store: source, id: id)])
        reportPeak("after-export")
        let imported = try MiniAppBackupArchive.load(from: file.url)
        reportPeak("after-import")
        let plan = try imported.prepareRestore(selected: [id], providers: [],
            fileProviders: [RecordsBackup.provider(store: target, id: id)])
        try await plan.apply()
        reportPeak("after-restore")
        let restored = try await target.copyAttachment(recordID: record.id, attachmentID: attachment.id,
            to: root.appendingPathComponent("verify"))
        let reader = try FileHandle(forReadingFrom: restored)
        defer { try? reader.close() }
        for index in 0..<chunkCount {
            try autoreleasepool {
                let data = try reader.read(upToCount: chunkSize)
                XCTAssertEqual(data, Data(repeating: UInt8(index), count: chunkSize), "Chunk \(index)")
            }
        }
        XCTAssertEqual(try reader.read(upToCount: 1), Data())
        print("LARGE_BACKUP bytes=\(chunkCount * chunkSize) elapsedSeconds=\(Date().timeIntervalSince(started))")
    }

    private func reportPeak(_ phase: String) {
        #if os(macOS)
        var usage = rusage()
        if getrusage(RUSAGE_SELF, &usage) == 0 {
            // Darwin reports bytes. This is a process-wide cumulative maximum,
            // not live allocation size or an iOS memory guarantee.
            print("LARGE_BACKUP phase=\(phase) processPeakRSSBytes=\(usage.ru_maxrss)")
        }
        #endif
    }
}
