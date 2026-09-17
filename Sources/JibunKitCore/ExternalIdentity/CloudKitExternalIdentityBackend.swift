#if canImport(CloudKit)
import CloudKit
import Foundation

/// Native adapter for a container explicitly created by an entitled host.
/// Merely constructing a Feature or diagnostic host never calls CKContainer().
public actor CloudKitExternalIdentityBackend: MiniAppExternalIdentityBackend {
    private let container: CKContainer

    public init(container: CKContainer) { self.container = container }

    public func currentAccountIdentifier(in scope: MiniAppExternalContainer) async throws -> String {
        try validate(scope)
        let status = try await container.accountStatus()
        guard status == .available else { throw MiniAppExternalIdentityError.accountUnavailable }
        return try await container.userRecordID().recordName
    }

    public func load(_ identity: MiniAppExternalRecordIdentity) async throws -> MiniAppExternalRecord? {
        try validate(identity.account.container)
        do {
            let record = try await database(identity.account.container).record(for: recordID(identity))
            var fields: [String: String] = [:]
            for key in record.allKeys() { if let value = record[key] as? String { fields[key] = value } }
            return .init(identity: identity, fields: fields)
        } catch let error as CKError where error.code == .unknownItem { return nil }
    }

    public func save(_ value: MiniAppExternalRecord) async throws {
        try validate(value.identity.account.container)
        let database = database(value.identity.account.container)
        let zone = CKRecordZone(zoneID: zoneID(value.identity.account))
        _ = try await database.modifyRecordZones(saving: [zone], deleting: [])
        let record = CKRecord(recordType: "JibunKitExternalData", recordID: recordID(value.identity))
        for (key, field) in value.fields { record[key] = field as CKRecordValue }
        _ = try await database.save(record)
    }

    public func delete(_ identity: MiniAppExternalRecordIdentity) async throws {
        try validate(identity.account.container)
        do { _ = try await database(identity.account.container).deleteRecord(withID: recordID(identity)) }
        catch let error as CKError where error.code == .unknownItem { return }
    }

    public func ensureSubscription(for account: MiniAppExternalAccount) async throws {
        try validate(account.container)
        let database = database(account.container)
        _ = try await database.modifyRecordZones(
            saving: [CKRecordZone(zoneID: zoneID(account))], deleting: [])
        let identifier = subscriptionID(account)
        do { _ = try await database.subscription(for: identifier); return }
        catch let error as CKError where error.code == .unknownItem {}
        let subscription = CKRecordZoneSubscription(zoneID: zoneID(account), subscriptionID: identifier)
        _ = try await database.save(subscription)
    }

    public func deleteOwnedData(for account: MiniAppExternalAccount) async throws {
        try validate(account.container)
        do { _ = try await database(account.container).deleteRecordZone(withID: zoneID(account)) }
        catch let error as CKError where error.code == .zoneNotFound || error.code == .unknownItem { return }
    }

    public func cancelOperations(owner: MiniAppID) async {
        // Async convenience calls cannot be selectively cancelled. The coordinator's
        // generation check isolates their late completion from the replacement account.
    }

    private func database(_ scope: MiniAppExternalContainer) -> CKDatabase {
        switch scope.database {
        case .privateDatabase: container.privateCloudDatabase
        case .sharedDatabase: container.sharedCloudDatabase
        case .publicDatabase: container.publicCloudDatabase
        }
    }
    private func validate(_ scope: MiniAppExternalContainer) throws {
        guard scope.identifier == container.containerIdentifier else {
            throw MiniAppExternalIdentityError.invalidIdentity
        }
        guard scope.database == .privateDatabase else {
            throw MiniAppExternalIdentityError.backend(
                "CloudKit native adapter supports privateDatabase custom zones only")
        }
    }
    private func zoneID(_ account: MiniAppExternalAccount) -> CKRecordZone.ID {
        CKRecordZone.ID(zoneName: "jibunkit.\(account.owner.storageNamespace)", ownerName: CKCurrentUserDefaultName)
    }
    private func recordID(_ identity: MiniAppExternalRecordIdentity) -> CKRecord.ID {
        CKRecord.ID(recordName: identity.recordName, zoneID: zoneID(identity.account))
    }
    private func subscriptionID(_ account: MiniAppExternalAccount) -> String {
        "jibunkit.\(account.owner.storageNamespace).changes"
    }
}
#endif
