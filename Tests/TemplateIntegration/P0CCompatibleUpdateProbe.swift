// Copied only into the generated compatibility host.
import Foundation
import JibunKitCore
import ResourceFeatureA
import ResourceFeatureB
import SwiftUI

@MainActor
enum P0CCompatibleUpdateProbe {
    static let definition = MiniAppDefinition(
        id: MiniAppID("p0-c-compatible-update"),
        title: "Package compatible update",
        systemImage: "shippingbox.and.arrow.backward"
    ) { _ in
        P0CCompatibleUpdateView()
    }
}

private struct P0CCompatibleUpdateView: View {
    @State private var result = "pending"

    var body: some View {
        Text(result)
            .accessibilityIdentifier("p0c.compatible-update.result")
            .task { result = await verify() }
    }

    private func verify() async -> String {
        do {
            guard let stage = launchValue(after: "-P0CCompatibleStage") else {
                return "failed: missing stage"
            }
            let directory = try FileManager.default.url(
                for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true
            ).appendingPathComponent("p0-c-compatible-update", isDirectory: true)
            let a = try FeatureACompatibleUpdate.run(stage: stage, directory: directory)
            let b = try FeatureBCompatibleUpdate.run(stage: stage, directory: directory)
            let resources = try resourceValues()
            return "passed:\(stage)|\(a)|\(b)|\(resources.joined(separator: "|"))"
        } catch {
            return "failed: \(error)"
        }
    }

    private func resourceValues() throws -> [String] {
        [
            try ResourceFeatureAValues.jsonOwner(),
            ResourceFeatureAValues.explicitGreeting(locale: "en"),
            ResourceFeatureAValues.explicitGreeting(locale: "fr"),
            ResourceFeatureAValues.explicitGreeting(locale: "ja"),
            try ResourceFeatureBValues.jsonOwner(),
            ResourceFeatureBValues.explicitGreeting(locale: "en"),
            ResourceFeatureBValues.explicitGreeting(locale: "fr"),
            ResourceFeatureBValues.explicitGreeting(locale: "ja"),
        ]
    }

    private func launchValue(after argument: String) -> String? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: argument), arguments.indices.contains(index + 1)
        else { return nil }
        return arguments[index + 1]
    }
}
