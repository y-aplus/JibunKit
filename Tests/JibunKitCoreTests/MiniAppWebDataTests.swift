import XCTest
import JibunKitCore

final class MiniAppWebDataTests: XCTestCase {
    func testPersistentIdentifierIsStableAndSeparatesOwnersAndProfiles() {
        let first = MiniAppContext(id: MiniAppID("first"))
        XCTAssertEqual(first.websiteDataStoreIdentifier().uuidString.lowercased(), "f6ffdf23-ed0e-85d0-8e1c-543a4e9a481e")
        XCTAssertNotEqual(first.websiteDataStoreIdentifier(), first.websiteDataStoreIdentifier(profile: "other"))
        XCTAssertNotEqual(first.websiteDataStoreIdentifier(), MiniAppContext(id: MiniAppID("second")).websiteDataStoreIdentifier())
        XCTAssertNotEqual(MiniAppContext(id: MiniAppID("a.b")).websiteDataStoreIdentifier(profile: "c"),
                          MiniAppContext(id: MiniAppID("a")).websiteDataStoreIdentifier(profile: "b.c"))
    }

    #if canImport(WebKit)
    @available(macOS 14.0, iOS 17.0, *)
    @MainActor
    func testFactoryReturnsPersistentNativeStoreForOwnerIdentifier() {
        let context = MiniAppContext(id: MiniAppID("web-owner"))
        let store = context.websiteDataStore(profile: "signed-in")

        XCTAssertTrue(store.isPersistent)
        XCTAssertEqual(store.identifier, context.websiteDataStoreIdentifier(profile: "signed-in"))
    }
    #endif
}
