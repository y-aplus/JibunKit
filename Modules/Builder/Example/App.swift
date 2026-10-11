import Foundation
import SwiftUI
import BuilderFeature

@main
struct BuilderExampleApp: App {
    var body: some Scene {
        WindowGroup {
            NavigationStack {
                BuilderRootView(environment: BuilderEnvironment(
                    storage: ExampleStorage(),
                    transport: URLSessionBuildTransport(),
                    ipaDirectory: FileManager.default.temporaryDirectory.appendingPathComponent("BuilderExample")))
            }
        }
    }
}

/// Keeps the settings in memory only, so the example never stores a token.
final class ExampleStorage: BuilderStorage, @unchecked Sendable {
    private let lock = NSLock()
    private var state = BuilderState()
    private var savedToken: String?

    func loadState() throws -> BuilderState { lock.withLock { state } }
    func saveState(_ state: BuilderState) throws { lock.withLock { self.state = state } }
    func token() throws -> String? { lock.withLock { savedToken } }
    func setToken(_ token: String?) throws { lock.withLock { savedToken = token } }
}
