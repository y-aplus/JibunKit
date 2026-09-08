import SwiftUI
import RecordsFeature

@main
struct RecordsExampleApp: App {
    @State private var store: RecordStore?
    @State private var error: String?

    var body: some Scene {
        WindowGroup {
            Group {
                if let store { NavigationStack { RecordsRootView(store: store) } }
                else if let error { Text(error) }
                else { ProgressView() }
            }
            .task {
                guard store == nil else { return }
                do {
                    // Standalone test fixture only; the Feature and host never
                    // depend on launch arguments or seed the user's records.
                    if ProcessInfo.processInfo.arguments.contains("--attachment-fixture") {
                        let documents = try FileManager.default.url(for: .documentDirectory, in: .userDomainMask,
                            appropriateFor: nil, create: true)
                        try Data("Attachment preview fixture".utf8).write(to: documents.appendingPathComponent("attachment-fixture.txt"), options: .atomic)
                    }
                    let directory = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                                appropriateFor: nil, create: true)
                    store = try RecordStore(directory: directory.appendingPathComponent("Records", isDirectory: true))
                } catch { self.error = "保存先を開けません: \(error.localizedDescription)" }
            }
        }
    }
}
