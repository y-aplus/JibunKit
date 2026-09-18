#if os(iOS)
import JibunKitCore
import Observation
import SwiftUI
import UIKit

@MainActor
enum P2AppearanceProbe {
    static let first = P2AppearanceFeature(id: MiniAppID("p2-appearance-a"), title: "Appearance A", scheme: .dark)
    static let second = P2AppearanceFeature(id: MiniAppID("p2-appearance-b"), title: "Appearance B", scheme: .light)
    static let definitions = [first.definition, second.definition]
}

@MainActor @Observable
final class P2AppearanceFeature {
    let id: MiniAppID
    let title: String
    let scheme: ColorScheme
    var requested = false
    var effective = false
    var rootEnvironment = "unread"
    var rootTrait = "unread"
    var sheetEnvironment = "closed"
    var sheetTrait = "closed"
    var showingSheet = false

    @ObservationIgnored private let timer: MiniAppIdleTimer
    @ObservationIgnored private var sceneIdle: MiniAppSceneIdleTimer?
    @ObservationIgnored private var sceneActivities: [UUID: MiniAppSceneActivity] = [:]
    @ObservationIgnored
    lazy var lifetime = MiniAppFeatureLifetime(id: id) { [weak self] runtime in
        guard let self else { return }
        let scope = try runtime.makeSceneIdleTimer(for: self.id, using: self.timer)
        self.sceneIdle = scope
        for activity in self.sceneActivities.values { scope.receive(activity) }
        try scope.setRequested(self.requested)
        self.refreshEffective()
    }

    init(id: MiniAppID, title: String, scheme: ColorScheme, timer: MiniAppIdleTimer = .shared) {
        self.id = id
        self.title = title
        self.scheme = scheme
        self.timer = timer
    }

    var definition: MiniAppDefinition {
        MiniAppDefinition(
            id: id, title: title, systemImage: "circle.lefthalf.filled", lifetime: lifetime,
            onSceneActivityChange: { [weak self] in self?.receive($0) }
        ) { [self] _ in
            P2AppearanceRoot(feature: self, policy: .environment(scheme))
        }
    }

    func setRequested(_ value: Bool) {
        requested = value
        do { try sceneIdle?.setRequested(value) }
        catch { requested = false }
        refreshEffective()
    }

    func receive(_ activity: MiniAppSceneActivity) {
        guard activity.featureID == id else { return }
        if activity.isConnected { sceneActivities[activity.sceneID] = activity }
        else { sceneActivities.removeValue(forKey: activity.sceneID) }
        sceneIdle?.receive(activity)
        refreshEffective()
    }

    func refreshEffective() {
        effective = timer.activeOwners.contains(id)
    }
}

enum P2AppearancePolicy {
    case environment(ColorScheme)
    case preferred(ColorScheme)
    case inherited
}

struct P2AppearanceRoot: View {
    @Bindable var feature: P2AppearanceFeature
    let policy: P2AppearancePolicy

    var body: some View {
        applyPolicy(to: NavigationStack {
            Form {
                Section("Appearance") {
                    P2AppearanceReading(label: "root", feature: feature)
                    Button("Sheetを表示") { feature.showingSheet = true }
                        .accessibilityIdentifier("p2.appearance.\(feature.id.rawValue).sheet.open")
                }
                Section("Idle timer") {
                    Toggle("画面を点灯し続ける", isOn: Binding(
                        get: { feature.requested }, set: feature.setRequested
                    ))
                    Text("requested=\(feature.requested) effective=\(feature.effective)")
                        .accessibilityIdentifier("p2.appearance.\(feature.id.rawValue).idle")
                    Button("状態を再読込") { feature.refreshEffective() }
                }
            }
            .navigationTitle(feature.title)
            .sheet(isPresented: $feature.showingSheet) {
                P2AppearanceReading(label: "sheet", feature: feature)
            }
        })
    }

    @ViewBuilder
    private func applyPolicy<Content: View>(to content: Content) -> some View {
        switch policy {
        case .environment(let scheme): content.environment(\.colorScheme, scheme)
        case .preferred(let scheme): content.preferredColorScheme(scheme)
        case .inherited: content
        }
    }
}

private struct P2AppearanceReading: View {
    @Environment(\.colorScheme) private var colorScheme
    let label: String
    let feature: P2AppearanceFeature

    var body: some View {
        VStack(alignment: .leading) {
            Text("environment=\(name(colorScheme))")
            Text("trait=\(label == "root" ? feature.rootTrait : feature.sheetTrait)")
        }
        .accessibilityIdentifier("p2.appearance.\(feature.id.rawValue).\(label)")
        .background(P2AppearanceTraitReader { style in
            let value = name(style)
            if label == "root" {
                feature.rootEnvironment = name(colorScheme)
                feature.rootTrait = value
            } else {
                feature.sheetEnvironment = name(colorScheme)
                feature.sheetTrait = value
            }
        })
    }

    private func name(_ value: ColorScheme) -> String { value == .dark ? "dark" : "light" }
    private func name(_ value: UIUserInterfaceStyle) -> String {
        switch value { case .dark: "dark"; case .light: "light"; default: "unspecified" }
    }
}

private struct P2AppearanceTraitReader: UIViewControllerRepresentable {
    let receive: @MainActor (UIUserInterfaceStyle) -> Void

    func makeUIViewController(context: Context) -> P2AppearanceTraitViewController {
        P2AppearanceTraitViewController(receive: receive)
    }

    func updateUIViewController(_ controller: P2AppearanceTraitViewController, context: Context) {
        controller.receive = receive
        controller.report()
    }
}

@MainActor
final class P2AppearanceTraitViewController: UIViewController {
    var receive: @MainActor (UIUserInterfaceStyle) -> Void
    init(receive: @escaping @MainActor (UIUserInterfaceStyle) -> Void) {
        self.receive = receive
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func viewDidAppear(_ animated: Bool) { super.viewDidAppear(animated); report() }
    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection); report()
    }
    func report() { receive(traitCollection.userInterfaceStyle) }
}

@MainActor
final class P2ContainedAppearanceViewController: UIViewController {
    init(style: UIUserInterfaceStyle) {
        super.init(nibName: nil, bundle: nil)
        overrideUserInterfaceStyle = style
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}
#endif
