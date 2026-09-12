import JibunKitCore
import SwiftUI
import WidgetKit

@main
struct WidgetFixtureHostApp: App {
    @State private var status: String

    init() {
        do {
            try Self.write(owner: "owner-a", value: 11)
            try Self.write(owner: "owner-b", value: 22)
            WidgetCenter.shared.reloadAllTimelines()
            _status = State(initialValue: "ready")
        } catch {
            let message = "storage-error:\(error)"
            print(message)
            _status = State(initialValue: message)
        }
    }

    var body: some Scene {
        WindowGroup {
            VStack {
                Text(status).accessibilityIdentifier("widget-fixture.status")
                Button("Update Feature A") {
                    do {
                        try Self.write(owner: "owner-a", value: 33)
                        WidgetCenter.shared.reloadAllTimelines()
                        status = "a-updated"
                    } catch {
                        status = "storage-error:\(error)"
                        print(status)
                    }
                }
                .accessibilityIdentifier("widget-fixture.update-a")
            }
        }
    }

    private static func write(owner: String, value: Int) throws {
        let defaults = try MiniAppStorage.sharedDefaults()
        let context = MiniAppContext(id: MiniAppID(owner))
        MiniAppStorage.withExclusiveAccess {
            defaults.set(value, forKey: context.storageKey("shared-value"))
        }
    }
}
