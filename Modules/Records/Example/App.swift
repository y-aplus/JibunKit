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
                    let directory = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                                appropriateFor: nil, create: true)
                    store = try RecordStore(directory: directory.appendingPathComponent("Records", isDirectory: true))
                } catch { self.error = "保存先を開けません: \(error.localizedDescription)" }
            }
        }
    }
}
