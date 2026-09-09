#if os(iOS)
import Foundation
import SwiftUI

/// A Feature-owned mini-app definition: identity, display info, and Root View
/// factory in one place. The host only enumerates definitions in
/// `MiniAppRegistry` and never edits per-Feature fields.
public struct MiniAppDefinition: Identifiable {
    public let id: MiniAppID
    public let title: String
    public let systemImage: String
    public let backup: MiniAppBackupProvider?
    public let fileBackup: MiniAppFileBackupProvider?
    private let rootView: @MainActor (MiniAppContext) -> AnyView
    private let appendDestination: (@MainActor (String, inout NavigationPath) -> Bool)?

    public init<Root: View>(
        id: MiniAppID,
        title: String,
        systemImage: String,
        backup: MiniAppBackupProvider? = nil,
        fileBackup: MiniAppFileBackupProvider? = nil,
        appendDestination: (@MainActor (String, inout NavigationPath) -> Bool)? = nil,
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
        self.appendDestination = appendDestination
        self.rootView = { context in
            AnyView(makeRootView(context))
        }
    }

    @MainActor
    public func makeDestination() -> AnyView {
        rootView(MiniAppContext(id: id))
    }

    /// Integration appends its Feature's native navigation values after the root.
    /// Returning false rejects an unsupported identifier without changing the host.
    @MainActor
    public func navigationPath(for destination: String) -> NavigationPath? {
        guard let appendDestination else { return nil }
        var path = NavigationPath([id])
        guard appendDestination(destination, &path) else { return nil }
        return path
    }
}
#endif
