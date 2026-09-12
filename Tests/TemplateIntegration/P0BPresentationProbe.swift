// Copied only into the isolated generated host, never the distributed app.
import JibunKitCore
import Observation
import SwiftUI
import UIKit

@MainActor
private final class PresentationProbeOwner {
    let id: MiniAppID
    let presentations: MiniAppPresentationOwner
    let state: PresentationProbeState
    lazy var lifetime = MiniAppFeatureLifetime(id: id) { [presentations] runtime in
        try presentations.connect(to: runtime)
    }

    init(_ rawID: String) {
        id = MiniAppID(rawID)
        presentations = MiniAppPresentationOwner(id: id)
        state = PresentationProbeState()
        state.presentations = presentations
    }
}

@MainActor
@Observable
private final class PresentationProbeState {
    weak var presentations: MiniAppPresentationOwner?
    var showsSheet = false
    var showsCover = false
    var showsUIKit = false
    var lastEvent = "ready"
    var draft = ""
    private var handles: [MiniAppPresentationOwner.Kind: MiniAppPresentationOwner.Handle] = [:]
    private var completions: [MiniAppPresentationOwner.Kind: CheckedContinuation<Void, Never>] = [:]

    func show(_ kind: MiniAppPresentationOwner.Kind) {
        guard handles[kind] == nil, let presentations else { return }
        do {
            handles[kind] = try presentations.begin(kind) { [weak self] in
                await self?.requestEnd(kind)
            }
            setPresented(true, kind: kind)
            lastEvent = "showing \(name(kind))"
        } catch {
            lastEvent = "rejected \(name(kind))"
        }
    }

    func cancel(_ kind: MiniAppPresentationOwner.Kind) {
        setPresented(false, kind: kind)
    }

    func didEnd(_ kind: MiniAppPresentationOwner.Kind) {
        setPresented(false, kind: kind)
        if let handle = handles.removeValue(forKey: kind) { presentations?.didEnd(handle) }
        completions.removeValue(forKey: kind)?.resume()
        lastEvent = "ended \(name(kind))"
    }

    private func requestEnd(_ kind: MiniAppPresentationOwner.Kind) async {
        guard handles[kind] != nil else { return }
        await withCheckedContinuation { continuation in
            completions[kind] = continuation
            if isPresented(kind) { setPresented(false, kind: kind) }
        }
    }

    private func isPresented(_ kind: MiniAppPresentationOwner.Kind) -> Bool {
        switch kind {
        case .sheet: showsSheet
        case .fullScreenCover: showsCover
        case .uiViewController: showsUIKit
        }
    }

    private func setPresented(_ presented: Bool, kind: MiniAppPresentationOwner.Kind) {
        switch kind {
        case .sheet: showsSheet = presented
        case .fullScreenCover: showsCover = presented
        case .uiViewController: showsUIKit = presented
        }
    }

    private func name(_ kind: MiniAppPresentationOwner.Kind) -> String {
        switch kind {
        case .sheet: "sheet"
        case .fullScreenCover: "cover"
        case .uiViewController: "uikit"
        }
    }
}

@MainActor
enum P0BPresentationProbe {
    private static let a = PresentationProbeOwner("presentation-a")
    private static let b = PresentationProbeOwner("presentation-b")
    static let definitions = [definition(a), definition(b)]

    private static func definition(_ owner: PresentationProbeOwner) -> MiniAppDefinition {
        MiniAppDefinition(
            id: owner.id,
            title: owner.id == a.id ? "Presentation A" : "Presentation B",
            systemImage: "rectangle.on.rectangle",
            lifetime: owner.lifetime
        ) { _ in
            PresentationProbeRoot(owner: owner)
        }
    }
}

private struct PresentationProbeRoot: View {
    let owner: PresentationProbeOwner
    @Bindable private var state: PresentationProbeState

    init(owner: PresentationProbeOwner) {
        self.owner = owner
        _state = Bindable(owner.state)
    }

    var body: some View {
        VStack(spacing: 14) {
            Text(owner.id.rawValue).accessibilityIdentifier("presentation.owner")
            Text(state.lastEvent).accessibilityIdentifier("presentation.status")
            TextField("Draft", text: $state.draft)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("presentation.draft")
            Button("Show sheet") { state.show(.sheet) }.accessibilityIdentifier("presentation.show.sheet")
            Button("Show full screen") { state.show(.fullScreenCover) }
                .accessibilityIdentifier("presentation.show.cover")
            Button("Show UIKit") { state.show(.uiViewController) }
                .accessibilityIdentifier("presentation.show.uikit")
            Button("Stop owner") { Task { await owner.lifetime.stop() } }
                .accessibilityIdentifier("presentation.stop")
        }
        .sheet(isPresented: $state.showsSheet, onDismiss: { state.didEnd(.sheet) }) {
            Button("Cancel sheet") { state.cancel(.sheet) }
                .accessibilityIdentifier("presentation.cancel.sheet")
        }
        .fullScreenCover(isPresented: $state.showsCover, onDismiss: { state.didEnd(.fullScreenCover) }) {
            Button("Cancel full screen") { state.cancel(.fullScreenCover) }
                .accessibilityIdentifier("presentation.cancel.cover")
        }
        .sheet(isPresented: $state.showsUIKit, onDismiss: { state.didEnd(.uiViewController) }) {
            MiniAppViewControllerAdapter(
                makeViewController: { requestDismiss in
                    PresentationProbeViewController(requestDismiss: requestDismiss) {
                        Task {
                            await owner.lifetime.stop()
                            state.lastEvent = "owner stopped"
                        }
                    }
                },
                requestDismiss: { state.cancel(.uiViewController) }
            )
        }
    }
}

@MainActor
private final class PresentationProbeViewController: UIViewController {
    private let requestDismiss: @MainActor () -> Void
    private let requestStop: @MainActor () -> Void

    init(
        requestDismiss: @escaping @MainActor () -> Void,
        requestStop: @escaping @MainActor () -> Void
    ) {
        self.requestDismiss = requestDismiss
        self.requestStop = requestStop
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        let button = UIButton(type: .system, primaryAction: UIAction(title: "Cancel UIKit") { [weak self] _ in
            self?.requestDismiss()
        })
        button.accessibilityIdentifier = "presentation.cancel.uikit"
        let stop = UIButton(type: .system, primaryAction: UIAction(title: "Stop owner") { [weak self] _ in
            self?.requestStop()
        })
        stop.accessibilityIdentifier = "presentation.stop.uikit"
        let stack = UIStackView(arrangedSubviews: [button, stop])
        stack.axis = .vertical
        stack.spacing = 20
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])
    }
}
