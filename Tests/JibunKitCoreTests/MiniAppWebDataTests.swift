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
}
