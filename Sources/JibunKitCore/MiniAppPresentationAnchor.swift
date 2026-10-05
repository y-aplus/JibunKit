#if os(iOS)
import SwiftUI
import UIKit

public enum MiniAppPresentationAnchorError: Error, Equatable, Sendable {
    /// The anchored view is not in a window, so there is no scene to present from.
    case notInWindow
}

/// Presents UIKit view controllers from the scene that shows a Feature's view.
/// Attach it with `miniAppPresentationAnchor(_:)` to the view whose scene
/// should present, then pass it to a presenter such as
/// `MiniAppVisionCaptureAdapter(presentationOwner:anchor:)`.
@MainActor
public final class MiniAppPresentationAnchor {
    fileprivate weak var controller: UIViewController?

    public init() {}

    /// Whether the anchored view is currently in a window.
    public var isAvailable: Bool { controller?.viewIfLoaded?.window != nil }

    /// Presents on top of whatever the anchored view already presents and
    /// returns once the presentation animation has finished.
    public func present(_ presented: UIViewController) async throws {
        guard let source = controller, source.viewIfLoaded?.window != nil else {
            throw MiniAppPresentationAnchorError.notInWindow
        }
        var presenter = source
        while let next = presenter.presentedViewController { presenter = next }
        await withCheckedContinuation { continuation in
            presenter.present(presented, animated: true) { continuation.resume() }
        }
    }

    /// Dismisses `presented` if it is still presented, and returns once the
    /// dismissal has finished.
    public func dismiss(_ presented: UIViewController) async {
        guard let presenter = presented.presentingViewController,
              presenter.presentedViewController === presented else { return }
        await withCheckedContinuation { continuation in
            presenter.dismiss(animated: true) { continuation.resume() }
        }
    }
}

public extension View {
    /// Makes `anchor` present from the scene that shows this view.
    func miniAppPresentationAnchor(_ anchor: MiniAppPresentationAnchor) -> some View {
        background(MiniAppPresentationAnchorView(anchor: anchor))
    }
}

private struct MiniAppPresentationAnchorView: UIViewControllerRepresentable {
    let anchor: MiniAppPresentationAnchor

    func makeUIViewController(context: Context) -> AnchorController {
        AnchorController(anchor: anchor)
    }

    func updateUIViewController(_ controller: AnchorController, context: Context) {
        anchor.controller = controller
    }

    static func dismantleUIViewController(_ controller: AnchorController, coordinator: ()) {
        if controller.anchor.controller === controller { controller.anchor.controller = nil }
    }

    final class AnchorController: UIViewController {
        let anchor: MiniAppPresentationAnchor

        init(anchor: MiniAppPresentationAnchor) {
            self.anchor = anchor
            super.init(nibName: nil, bundle: nil)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError() }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            anchor.controller = self
        }
    }
}
#endif
