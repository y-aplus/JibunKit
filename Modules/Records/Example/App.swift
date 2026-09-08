import SwiftUI
import RecordsFeature
import UniformTypeIdentifiers

@main
struct RecordsExampleApp: App {
    @State private var store: RecordStore?
    @State private var error: String?
    @State private var exportingFixture = false
    @State private var fixtureSaved = false
    @State private var importingFixture = false
    @State private var fixtureImportResult = ""

    var body: some Scene {
        WindowGroup {
            Group {
                if let store {
                    NavigationStack {
                        RecordsRootView(store: store)
                            .toolbar {
                                if ProcessInfo.processInfo.arguments.contains("--attachment-fixture") {
                                    Button(fixtureSaved ? "Fixture saved" : "Export fixture") { exportingFixture = true }
                                        .accessibilityIdentifier(fixtureSaved ? "records.fixture.saved" : "records.fixture.export")
                                    Button("Import control") { importingFixture = true }
                                        .accessibilityIdentifier("records.fixture.import")
                                }
                            }
                    }
                }
                else if let error { Text(error) }
                else { ProgressView() }
            }
            .overlay(alignment: .bottom) {
                if !fixtureImportResult.isEmpty {
                    Text(fixtureImportResult).accessibilityIdentifier("records.fixture.result")
                }
            }
            .background {
                Color.clear.fileImporter(isPresented: $importingFixture, allowedContentTypes: [.data]) { result in
                    do {
                        let url = try result.get()
                        let access = url.startAccessingSecurityScopedResource()
                        defer { if access { url.stopAccessingSecurityScopedResource() } }
                        let data = try Data(contentsOf: url)
                        fixtureImportResult = data == Data("Attachment preview fixture".utf8) ? "Fixture imported" : "Fixture content mismatch"
                    } catch { fixtureImportResult = "Control import failed: \(error)" }
                }
            }
            .fileExporter(isPresented: $exportingFixture, document: AttachmentFixtureDocument(),
                          contentType: .plainText, defaultFilename: "attachment-fixture") { result in
                switch result {
                case .success: fixtureSaved = true
                case .failure(let failure): error = failure.localizedDescription
                }
            }
            .task {
                guard store == nil else { return }
                do {
                    let directory = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                                appropriateFor: nil, create: true)
                    store = try RecordStore(directory: directory.appendingPathComponent("Records", isDirectory: true))
                } catch { self.error = "保存先を開けません: \(error.localizedDescription)" }
            }
        }
    }
}

// A Files-managed fixture for standalone UI tests, not a Feature export API.
private struct AttachmentFixtureDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.plainText] }
    init() {}
    init(configuration: ReadConfiguration) throws {}
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data("Attachment preview fixture".utf8))
    }
}
