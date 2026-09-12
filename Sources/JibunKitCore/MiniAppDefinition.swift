#if os(iOS)
import Foundation
import SwiftUI
import UserNotifications

/// A Feature-owned mini-app definition: identity, display info, and Root View
/// factory in one place. The host only enumerates definitions in
/// `MiniAppRegistry` and never edits per-Feature fields.
public struct MiniAppDefinition: Identifiable {
    public let id: MiniAppID
    public let title: String
    public let systemImage: String
    public let backup: MiniAppBackupProvider?
    public let fileBackup: MiniAppFileBackupProvider?
    public let lifetime: MiniAppFeatureLifetime?
    public let presentations: MiniAppPresentationOwner?
    public let removal: MiniAppRemovalProvider?
    public let permissions: [MiniAppPermissionDeclaration]
    /// Idempotent cleanup for owned registrations beyond host notifications/search.
    public let onUnregister: (@MainActor @Sendable () async throws -> Void)?
    public let restoreLifecycle: MiniAppRestoreLifecycle?
    /// Synchronous, screen-independent native registration performed by the
    /// host during `application(_:didFinishLaunchingWithOptions:)`.
    public let onHostLaunch: (@MainActor () throws -> Void)?
    public let onHostPhaseChange: (@MainActor (MiniAppHostPhase) -> Void)?
    public let onSceneActivityChange: MiniAppSceneActivityDispatcher.Handler?
    public let onNotificationAction: (@MainActor (MiniAppNotificationAction) async -> Void)?
    public let notificationPresentation: (@MainActor (MiniAppForegroundNotification) -> UNNotificationPresentationOptions)?
    public let notificationCategories: [UNNotificationCategory]
    public let resolveIncomingURL: MiniAppURLRouter.Resolver?
    private let rootView: @MainActor (MiniAppContext) -> AnyView
    private let appendDestination: (@MainActor (String, inout NavigationPath) -> Bool)?

    public init<Root: View>(
        id: MiniAppID,
        title: String,
        systemImage: String,
        backup: MiniAppBackupProvider? = nil,
        fileBackup: MiniAppFileBackupProvider? = nil,
        restoreLifecycle: MiniAppRestoreLifecycle? = nil,
        lifetime: MiniAppFeatureLifetime? = nil,
        presentations: MiniAppPresentationOwner? = nil,
        removal: MiniAppRemovalProvider? = nil,
        permissions: [MiniAppPermissionDeclaration] = [],
        onUnregister: (@MainActor @Sendable () async throws -> Void)? = nil,
        appendDestination: (@MainActor (String, inout NavigationPath) -> Bool)? = nil,
        resolveIncomingURL: MiniAppURLRouter.Resolver? = nil,
        onHostLaunch: (@MainActor () throws -> Void)? = nil,
        onHostPhaseChange: (@MainActor (MiniAppHostPhase) -> Void)? = nil,
        onSceneActivityChange: MiniAppSceneActivityDispatcher.Handler? = nil,
        onNotificationAction: (@MainActor (MiniAppNotificationAction) async -> Void)? = nil,
        notificationCategories: [UNNotificationCategory] = [],
        notificationPresentation: (@MainActor (MiniAppForegroundNotification) -> UNNotificationPresentationOptions)? = nil,
        makeRootView: @escaping @MainActor (MiniAppContext) -> Root
    ) {
        precondition(id.isValid, "Mini-app IDs must start with a-z and contain only a-z, 0-9, '.', '-', or '_'.")
        self.id = id
        self.title = title
        self.systemImage = systemImage
        precondition(backup == nil || backup?.id == id, "Backup provider must belong to this Feature.")
        self.backup = backup
        precondition(fileBackup == nil || fileBackup?.id == id, "File backup provider must belong to this Feature.")
        self.fileBackup = fileBackup
        // A custom restore lifecycle may include store-specific stop recovery.
        // Otherwise reuse the same lifetime as ordinary host entry.
        precondition(lifetime == nil || lifetime?.id == id, "Lifetime must belong to this Feature.")
        precondition(presentations == nil || presentations?.id == id)
        self.presentations = presentations
        self.lifetime = lifetime
        precondition(removal == nil || removal?.id == id, "Removal provider must belong to this Feature.")
        precondition(Set(permissions.map(\.id)).count == permissions.count && permissions.allSatisfy { !$0.id.isEmpty },
                     "Permission IDs must be nonempty and unique within a Feature.")
        self.removal = removal
        self.permissions = permissions
        self.onUnregister = onUnregister
        self.restoreLifecycle = restoreLifecycle
        self.appendDestination = appendDestination
        self.resolveIncomingURL = resolveIncomingURL
        self.onHostLaunch = onHostLaunch
        self.onHostPhaseChange = onHostPhaseChange
        self.onSceneActivityChange = onSceneActivityChange
        self.onNotificationAction = onNotificationAction
        self.notificationCategories = notificationCategories
        self.notificationPresentation = notificationPresentation
        self.rootView = { context in
            AnyView(makeRootView(context))
        }
    }

    @MainActor
    public func makeDestination() -> AnyView {
        if let lifetime {
            return AnyView(MiniAppLifetimeDestination(lifetime: lifetime) {
                rootView(MiniAppContext(id: id))
            }.environment(\.miniAppLifetime, lifetime))
        }
        return rootView(MiniAppContext(id: id))
    }

    @MainActor
    public var effectiveRestoreLifecycle: MiniAppRestoreLifecycle? {
        restoreLifecycle ?? lifetime?.restoreLifecycle
    }

    /// Integration appends its Feature's native navigation values to an empty
    /// path. The root View is stack content, not an element in this path.
    /// Returning false rejects an unsupported identifier without changing the host.
    @MainActor
    public func navigationPath(for destination: String) -> NavigationPath? {
        guard let appendDestination else { return nil }
        var path = NavigationPath()
        guard appendDestination(destination, &path) else { return nil }
        return path
    }
}

private struct MiniAppLifetimeKey: EnvironmentKey {
    static let defaultValue: MiniAppFeatureLifetime? = nil
}

public extension EnvironmentValues {
    var miniAppLifetime: MiniAppFeatureLifetime? {
        get { self[MiniAppLifetimeKey.self] }
        set { self[MiniAppLifetimeKey.self] = newValue }
    }
}

/// The view waits for startup but does not own the Feature's lifetime. A normal
/// navigation switch can discard this view while owned work keeps running.
private struct MiniAppLifetimeDestination<Content: View>: View {
    let lifetime: MiniAppFeatureLifetime
    @ViewBuilder let content: () -> Content
    @State private var attempt = 0

    var body: some View {
        Group {
            switch lifetime.state {
            case .running, .stopping:
                // Keep the presenting view mounted until native onDismiss and
                // runtime cleanup finish. Removing it at .stopping loses the
                // acknowledgement that shutdown is waiting for.
                content()
                    .disabled(lifetime.state == .stopping)
                    .overlay {
                        if lifetime.state == .stopping {
                            ProgressView("終了を待っています")
                                .accessibilityIdentifier("miniapp.start.pending")
                        }
                    }
            case .failed(let reason):
                ContentUnavailableView {
                    Label("アプリを開始できません", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(reason)
                } actions: {
                    Button("再試行") { attempt += 1 }
                        .accessibilityIdentifier("miniapp.start.retry")
                }
            case .stopped:
                Button("アプリを開始") { attempt += 1 }
                    .accessibilityIdentifier("miniapp.start.resume")
            case .starting:
                ProgressView("アプリを準備しています")
                    .accessibilityIdentifier("miniapp.start.pending")
            }
        }
        .task(id: attempt) {
            do { try await lifetime.start() }
            catch { /* The lifetime owns failure state; view cancellation is not a failure. */ }
        }
    }
}
#endif
