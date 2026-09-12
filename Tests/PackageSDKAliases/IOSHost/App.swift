import SDKAliasBridge
import SwiftUI

@main
struct SDKAliasHostApp: App {
    var body: some Scene {
        WindowGroup {
            SDKAliasContentView()
        }
    }
}

@MainActor
struct SDKAliasContentView: View {
    @State private var snapshot = SDKAliasBridge.snapshot()

    var body: some View {
        VStack(spacing: 12) {
            value(snapshot.aVersion, id: "sdk-alias.a-version")
            value(snapshot.bVersion, id: "sdk-alias.b-version")
            value(snapshot.aConfiguration, id: "sdk-alias.a-configuration")
            value(snapshot.bConfiguration, id: "sdk-alias.b-configuration")

            Button("Write B") {
                SDKAliasBridge.writeB("ios-b-written")
                snapshot = SDKAliasBridge.snapshot()
            }
            .accessibilityIdentifier("sdk-alias.write-b")

            Button("Update A") {
                SDKAliasBridge.writeA("ios-a-updated")
                snapshot = SDKAliasBridge.snapshot()
            }
            .accessibilityIdentifier("sdk-alias.update-a")
        }
        .padding()
    }

    private func value(_ text: String, id: String) -> some View {
        Text(text)
            .accessibilityIdentifier(id)
    }
}
