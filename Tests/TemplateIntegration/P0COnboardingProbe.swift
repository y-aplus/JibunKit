// Temporary generated host only. Uses the evaluated Registry, not source text.
import Foundation
import JibunKitCore
import SwiftUI

@MainActor
enum P0COnboardingProbe {
    // Generated-host fault injection: the linked Notes product remains present,
    // but the real Registry omits its definition for this process.
    static func registrations(_ definitions: [MiniAppDefinition]) -> [MiniAppDefinition] {
        guard ProcessInfo.processInfo.arguments.contains("--p0c-omit-notes") else { return definitions }
        return definitions.filter { $0.id != MiniAppID("notes") }
    }

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
        Text(issues.isEmpty ? "passed: counter,notes,records,reminder" : "Sources/JibunKit/MiniAppRegistry.swiftの登録を確認してください: \(issues)")
            .accessibilityIdentifier("p0c.connection.result")
    }
}
