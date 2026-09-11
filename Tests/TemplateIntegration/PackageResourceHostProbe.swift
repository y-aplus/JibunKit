// Copied only into the temporary generated host used by CI, never into a distributed IPA.
import Foundation
import JibunKitCore
import ResourceFeatureA
import ResourceFeatureB
import SwiftUI

@MainActor
enum PackageResourceHostProbe {
    static let definition = MiniAppDefinition(
        id: MiniAppID("package-resource-host"),
        title: "Package resources",
        systemImage: "globe"
    ) { _ in
        PackageResourceHostProbeView()
    }
}

private struct PackageResourceHostProbeView: View {
    var body: some View {
        VStack {
            Text(observedLanguage)
                .accessibilityIdentifier("package-resource-host.language")
            Text(result)
                .accessibilityIdentifier("package-resource-host.result")
        }
    }

    private var observedLanguage: String {
        Locale.preferredLanguages.first?
            .split(separator: "-").first.map(String.init) ?? "missing"
    }

    private var result: String {
        do {
            return [
                try ResourceFeatureAValues.jsonOwner(),
                ResourceFeatureAValues.greeting(),
                try ResourceFeatureBValues.jsonOwner(),
                ResourceFeatureBValues.greeting(),
            ].joined(separator: "|")
        } catch {
            return "error:\(error)"
        }
    }
}
