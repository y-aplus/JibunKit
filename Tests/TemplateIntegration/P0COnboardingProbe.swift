// Temporary generated host only. Uses the evaluated Registry, not source text.
import JibunKitCore
import SwiftUI

@MainActor
enum P0COnboardingProbe {
    static let definition = MiniAppDefinition(
        id: MiniAppID("p0-c-onboarding"), title: "Feature接続の診断", systemImage: "checklist"
    ) { _ in
        P0COnboardingView()
    }
}

private struct P0COnboardingView: View {
    var body: some View {
        let expected: Set<MiniAppID> = [.counter, .reminder, MiniAppID("notes"), MiniAppID("records")]
        let issues = MiniAppValidator.validate(ids: MiniAppRegistry.all.map(\.id), expectedIDs: expected)
        Text(issues.isEmpty ? "passed: counter,notes,records,reminder" : "Registry登録を確認してください: \(issues)")
            .accessibilityIdentifier("p0c.connection.result")
    }
}
