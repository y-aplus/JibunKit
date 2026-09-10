import PrivacyFeatureB
import SwiftUI
#if canImport(PrivacyFeatureA)
import PrivacyFeatureA
#endif

@main struct PrivacyHostApp: App {
    var body: some Scene { WindowGroup { Text(PrivacyFeatureB.owner) } }
}
