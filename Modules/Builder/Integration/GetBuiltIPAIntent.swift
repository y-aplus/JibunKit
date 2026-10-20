#if os(iOS)
import AppIntents
import Foundation
import UniformTypeIdentifiers
import JibunKitCore
import BuilderFeature

/// Gives the last build's IPA to a shortcut, which passes it to SideStore's
/// Install action. Build opens that shortcut from its Install with SideStore
/// button. The Shortcuts text stays in English: the host's App Intents text
/// comes from the host's tables, which hold no Feature's strings.
struct GetBuiltIPAIntent: AppIntent {
    static let title: LocalizedStringResource = "Get the Built JibunKit IPA"
    static let description = IntentDescription("Returns the IPA of the last build requested in Build, downloading it if needed. Pass it to SideStore's Install action.")
    static var supportedModes: IntentModes { [.background] }

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<IntentFile> {
        // Shortcuts may cold-launch the app without opening Build.
        guard MiniAppRegistry.management.isEnabled(BuilderMiniApp.id) else { throw BuilderUnavailable() }
        let file = try await MiniAppRestoreCoordinator.shared.withStoreAccess(for: BuilderMiniApp.id) {
            try await BuiltIPA.latest(storage: BuilderMiniApp.storage, transport: URLSessionBuildTransport(),
                                      ipaDirectory: BuilderMiniApp.ipaDirectory)
        }
        // Pass the bytes, so Shortcuts need not read this app's temporary directory.
        return .result(value: IntentFile(data: try Data(contentsOf: file), filename: GitHubBuildClient.ipaName,
                                         type: UTType(filenameExtension: "ipa")))
    }
}

private struct BuilderUnavailable: LocalizedError {
    var errorDescription: String? {
        String(localized: "Build is turned off or removed. Turn it on again in Manage Mini Apps.", bundle: BuilderResources.bundle)
    }
}
#endif
