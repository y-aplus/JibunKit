#if os(iOS)
import SwiftUI
import UIKit

/// Embeds a Feature-created view controller without moving presentation state
/// into the host. The controller can request cancellation through the closure
/// passed to `makeViewController`.
public struct MiniAppViewControllerAdapter<Controller: UIViewController>: UIViewControllerRepresentable {
    public typealias UIViewControllerType = Controller

    private let makeController: @MainActor (@escaping @MainActor () -> Void) -> Controller
    private let updateController: @MainActor (Controller) -> Void
    private let requestDismiss: @MainActor () -> Void
    private let didDismantle: @MainActor () -> Void

    public init(
        makeViewController: @escaping @MainActor (@escaping @MainActor () -> Void) -> Controller,
        updateViewController: @escaping @MainActor (Controller) -> Void = { _ in },
        requestDismiss: @escaping @MainActor () -> Void,
        didDismantle: @escaping @MainActor () -> Void = {}
    ) {
        makeController = makeViewController
        updateController = updateViewController
        self.requestDismiss = requestDismiss
        self.didDismantle = didDismantle
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(requestDismiss: requestDismiss, didDismantle: didDismantle)
    }

    public func makeUIViewController(context: Context) -> Controller {
        makeController(context.coordinator.requestDismiss)
    }

    public func updateUIViewController(_ uiViewController: Controller, context: Context) {
        updateController(uiViewController)
    }

    public static func dismantleUIViewController(_ uiViewController: Controller, coordinator: Coordinator) {
        coordinator.didDismantle()
    }

    @MainActor
    public final class Coordinator {
        fileprivate let requestDismiss: @MainActor () -> Void
        fileprivate let didDismantle: @MainActor () -> Void

        fileprivate init(
            requestDismiss: @escaping @MainActor () -> Void,
            didDismantle: @escaping @MainActor () -> Void
        ) {
            self.requestDismiss = requestDismiss
            self.didDismantle = didDismantle
        }
    }
}
#endif
