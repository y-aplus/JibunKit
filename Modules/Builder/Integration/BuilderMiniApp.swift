#if os(iOS)
import Foundation
import SwiftUI
import UserNotifications
import JibunKitCore
import BuilderFeature

/// Connects Builder to the JibunKit host. JibunKitFeature.json lists this
/// directory, so the host app compiles it; the package itself does not.
@MainActor
enum BuilderMiniApp {
    nonisolated static let id = MiniAppID("builder")
    nonisolated static let context = MiniAppContext(id: id)
    nonisolated static let storage = BuilderHostStorage(context: context)
    nonisolated static let ipaDirectory = FileManager.default.temporaryDirectory
        .appendingPathComponent(id.storageNamespace, isDirectory: true)

    static let notificationPermission = MiniAppPermissionDeclaration(
        id: "notifications.build",
        title: String(localized: "Build notifications", bundle: BuilderResources.bundle),
        purpose: String(localized: "Reminds you to install the IPA a few minutes after you request a build.",
                        bundle: BuilderResources.bundle),
        deniedBehavior: String(localized: "Builds still work; open Build to check them.", bundle: BuilderResources.bundle))

    static let removal = MiniAppRemovalProvider(
        id: id,
        dataDescription: String(localized: "Repository setting, GitHub token and downloaded IPA",
                                bundle: BuilderResources.bundle),
        removeData: {
            try storage.removeAll()
            try? FileManager.default.removeItem(at: ipaDirectory)
            await context.removeAllOwnedNotifications()
        })

    static let definition = MiniAppDefinition(
        id: id,
        title: BuilderText.title,
        systemImage: "hammer",
        removal: removal,
        permissions: [notificationPermission]
    ) { _ in
        BuilderDestination()
    }
}

/// The package's string tables, which also hold the integration's text.
enum BuilderResources {
    static var bundle: Bundle { BuilderText.bundle }
}

private struct BuilderDestination: View {
    @Environment(\.miniAppConsentStore) private var consents

    var body: some View {
        BuilderRootView(environment: BuilderEnvironment(
            storage: BuilderMiniApp.storage,
            transport: URLSessionBuildTransport(),
            ipaDirectory: BuilderMiniApp.ipaDirectory,
            notifications: notifications))
    }

    private var notifications: BuilderNotifications? {
        guard let consents else { return nil }
        let owner = BuilderMiniApp.id
        let permission = BuilderMiniApp.notificationPermission.id
        return BuilderNotifications(
            consent: {
                switch consents.consent(for: owner, permissionID: permission) {
                case .allowed: .allowed
                case .denied: .denied
                default: .notDetermined
                }
            },
            setConsent: { consents.setConsent($0 ? .allowed : .denied, for: owner, permissionID: permission) },
            schedule: { date in try await BuilderNotificationScheduler.schedule(at: date) },
            cancel: { await BuilderMiniApp.context.removeAllOwnedNotifications() })
    }
}

enum BuilderNotificationScheduler {
    static func schedule(at date: Date) async throws {
        let center = UNUserNotificationCenter.current()
        guard try await center.requestAuthorization(options: [.alert, .sound]) else { return }
        let context = BuilderMiniApp.context
        let content = UNMutableNotificationContent()
        content.title = BuilderText.title
        content.body = String(localized: "The build is probably finished. Open Build to install it.",
                              bundle: BuilderResources.bundle)
        content.sound = .default
        content.userInfo = context.notificationUserInfo
        content.filterCriteria = context.notificationFilterCriteria
        let interval = max(1, date.timeIntervalSinceNow)
        try await center.add(UNNotificationRequest(
            identifier: context.notificationRequestIdentifier(for: "build"),
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)))
    }
}

/// Keeps Builder's state in the host's shared defaults under its own key and
/// the token in its own Keychain service.
final class BuilderHostStorage: BuilderStorage {
    private let stateKey: String
    private let keychain: MiniAppKeychain
    private static let tokenAccount = "github"

    init(context: MiniAppContext) {
        stateKey = context.storageKey("state")
        keychain = MiniAppKeychain(context: context, service: "github")
    }

    func loadState() throws -> BuilderState {
        guard let data = try MiniAppStorage.sharedDefaults().data(forKey: stateKey) else { return BuilderState() }
        return try JSONDecoder().decode(BuilderState.self, from: data)
    }

    func saveState(_ state: BuilderState) throws {
        let data = try JSONEncoder().encode(state)
        try MiniAppStorage.sharedDefaults().set(data, forKey: stateKey)
    }

    func token() throws -> String? {
        guard let data = try keychain.data(for: Self.tokenAccount) else { return nil }
        return String(decoding: data, as: UTF8.self)
    }

    func setToken(_ token: String?) throws {
        if let token {
            try keychain.set(Data(token.utf8), for: Self.tokenAccount)
        } else {
            try keychain.remove(account: Self.tokenAccount)
        }
    }

    func removeAll() throws {
        try MiniAppStorage.sharedDefaults().removeObject(forKey: stateKey)
        try keychain.removeAll()
    }
}
#endif
