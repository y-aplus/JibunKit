import AppIntents
import InteractiveFeatureA
import InteractiveFeatureB
import JibunKitCore
import XCTest

@MainActor
final class InteractiveNativeTests: XCTestCase {
    private func stores() throws -> (FeatureAStore, FeatureBStore) {
        let a = try FeatureAStore.shared(), b = try FeatureBStore.shared()
        try a.state.initialize(.initial, enabled: false)
        try a.state.setEnabled(false)
        try a.state.replaceWhileDisabled(.initial)
        try a.state.setEnabled(true)
        try b.state.initialize(.initial, enabled: false)
        try b.state.setEnabled(false)
        try b.state.replaceWhileDisabled(.initial)
        try b.state.setEnabled(true)
        return (a, b)
    }

    func testEntityQueriesAndNativeIntentUpdateOnlySelectedOwnerAndItem() async throws {
        let (a, b) = try stores()
        let aItems = try await FeatureAQuery().suggestedEntities()
        let bItems = try await FeatureBQuery().suggestedEntities()
        XCTAssertEqual(aItems.map(\.name), ["same-id", "second-id"])
        XCTAssertEqual(bItems.map(\.name), ["same-id", "second-id"])
        let selection = try XCTUnwrap(aItems.first { $0.name == "second-id" })
        let resolved = try await FeatureAQuery().entities(for: [selection.id])
        XCTAssertEqual(resolved.map(\.id), [selection.id])
        _ = try await FeatureAIncrement(item: selection).perform()
        XCTAssertEqual(try a.state.read().value.items["second-id"]?.value, 31)
        XCTAssertEqual(try a.state.read().value.items["same-id"]?.value, 10)
        XCTAssertEqual(try b.state.read().value.items["second-id"]?.value, 40)
        let foreign = try await FeatureBQuery().entities(for: [selection.id])
        XCTAssertTrue(foreign.isEmpty)
    }

    func testWidgetAndControlConfigurationResolveSameSelectionAndRejectDeletedItem() async throws {
        let (a, b) = try stores()
        let item = try XCTUnwrap(a.entities().first { $0.name == "same-id" })
        var widget = FeatureAWidgetConfiguration()
        widget.item = item
        var control = FeatureAControlConfiguration()
        control.item = item
        let widgetValue = FeatureAEntry.current(item: widget.item, store: a)
        let controlValue = try await FeatureAControlProvider().currentValue(configuration: control)
        XCTAssertEqual(widgetValue.value, controlValue.value)
        XCTAssertEqual(controlValue.item?.id, item.id)
        try a.deleteFirstItem()
        let resolved = try await FeatureAQuery().entities(for: [item.id])
        XCTAssertTrue(resolved.isEmpty)
        let unavailable = try await FeatureAControlProvider().currentValue(configuration: control)
        XCTAssertNil(unavailable.item)
        XCTAssertNil(FeatureAEntry.current(item: widget.item, store: a).value)
        do { _ = try await FeatureAIncrement(item: item).perform(); XCTFail("Deleted item accepted") } catch {}
        XCTAssertEqual(try b.state.read().value.items["same-id"]?.value, 20)
    }

    func testActualDefinitionsDisableDeleteRestoreAndRejectStaleConfiguration() async throws {
        let (a, b) = try stores()
        let old = try XCTUnwrap(a.entities().first)
        let definition = FeatureAMiniApp.definition(store: a)
        let other = FeatureBMiniApp.definition(store: b)
        let suite = "InteractiveManagement.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let coordinator = MiniAppRestoreCoordinator()
        let manager = MiniAppManagement(registrations: [definition, other].map {
            .init(id: $0.id, removal: $0.removal, externalAccess: $0.externalAccess)
        }, defaults: defaults, consents: .init(defaults: defaults), coordinator: coordinator)
        let provider = try XCTUnwrap(definition.backup)
        let saved = try await provider.exportEntry(coordinator: coordinator)
        try await manager.disable(definition.id)
        do { _ = try await FeatureAIncrement(item: old).perform(); XCTFail() } catch {}
        try await manager.enable(definition.id)
        _ = try await FeatureAIncrement(item: old).perform()
        let backup = try MiniAppBackup(entries: [saved])
        let plan = try MiniAppRestorePlan(backup: backup, selected: [definition.id], providers: [provider])
        try await plan.apply(lifecycles: [definition.id: try XCTUnwrap(definition.effectiveRestoreLifecycle)], coordinator: coordinator)
        XCTAssertEqual(try a.state.read().value.items["same-id"]?.value, 10)
        do { _ = try await FeatureAIncrement(item: old).perform(); XCTFail("Old restore generation accepted") } catch {}
        let restored = try XCTUnwrap(a.entities().first)
        try await manager.remove(definition.id)
        try await manager.enable(definition.id)
        do { _ = try await FeatureAIncrement(item: restored).perform(); XCTFail("Old registration accepted") } catch {}
        XCTAssertEqual(try b.state.read().value.items["same-id"]?.value, 20)
    }

    func testMutationFailureAndCancelledIntentLeaveBothStoresUnchanged() async throws {
        let (a, b) = try stores()
        let item = try XCTUnwrap(a.entities().first)
        XCTAssertThrowsError(try a.increment(item, failBeforeCommit: true))
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            _ = try await FeatureAIncrement(item: item).perform()
        }
        do { try await task.value; XCTFail("Cancelled intent applied") } catch is CancellationError {} catch { XCTFail("\(error)") }
        XCTAssertEqual(try a.value(for: item), 10)
        XCTAssertEqual(try b.state.read().value.items["same-id"]?.value, 20)
        _ = try await FeatureAIncrement(item: item).perform()
        XCTAssertEqual(try a.value(for: item), 11)
    }
}
