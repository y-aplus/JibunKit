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
    private let rootView: @MainActor (MiniAppContext) -> AnyView

    public init<Root: View>(
        id: MiniAppID,
        title: String,
        systemImage: String,
        makeRootView: @escaping @MainActor (MiniAppContext) -> Root
    ) {
        precondition(id.isValid, "Mini-app IDs must start with a-z and contain only a-z, 0-9, '.', '-', or '_'.")
        self.id = id
        self.title = title
        self.systemImage = systemImage
        self.rootView = { context in
            AnyView(makeRootView(context))
        }
    }

    @MainActor
    public func makeDestination() -> AnyView {
        rootView(MiniAppContext(id: id))
    }
}
#endif
