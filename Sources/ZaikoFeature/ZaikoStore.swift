#if os(iOS)
import Foundation
import JibunKitCore
import SwiftUI
import UniformTypeIdentifiers
import UserNotifications

struct InventoryBackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }

    var text: String

    init(text: String) {
        self.text = text
    }

    init(configuration: ReadConfiguration) throws {
        guard
            let data = configuration.file.regularFileContents,
            let text = String(data: data, encoding: .utf8)
        else {
            throw ZaikoError.importFailed
        }
        self.text = text
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}

@MainActor
final class ZaikoStore: ObservableObject {
    @Published private(set) var items: [InventoryItem]
    @Published var appState: AppState
    @Published var currentCategory: String
    @Published var isEditMode: Bool
    @Published var authorizationStatus: UNAuthorizationStatus
    @Published var transientMessage: String?

    private let context: MiniAppContext
    private let storageKey: String
    private let backupLatestKey: String
    private let backupPreviousKey: String
    private let notificationPrefix: String

    private let defaults: UserDefaults?
    private let notificationCenter: UNUserNotificationCenter
    private let configurationError: SharedGroupResolutionError?

    init(
        context: MiniAppContext,
        infoDictionary: [String: Any] = Bundle.main.infoDictionary ?? [:],
        notificationCenter: UNUserNotificationCenter = .current()
    ) {
        self.context = context
        self.storageKey = context.storageKey("state")
        self.backupLatestKey = context.storageKey("backup.latest")
        self.backupPreviousKey = context.storageKey("backup.prev")
        self.notificationPrefix = context.notificationRequestIdentifier + "."
        self.notificationCenter = notificationCenter
        do {
            let resolved = try MiniAppStorage.sharedDefaults(infoDictionary: infoDictionary)
            self.defaults = resolved
            self.configurationError = nil
            let loaded = Self.loadState(from: resolved, key: storageKey)
            items = loaded.items
            appState = loaded.app.mergedWithDefaults()
        } catch let error as SharedGroupResolutionError {
            self.defaults = nil
            self.configurationError = error
            items = []
            appState = AppState.makeDefault()
        } catch {
            self.defaults = nil
            self.configurationError = .missingLogicalIdentifier
            items = []
            appState = AppState.makeDefault()
        }
        currentCategory = InventoryDomain.allCategories
        isEditMode = false
        authorizationStatus = .notDetermined
        transientMessage = nil

        Task {
            await refreshNotificationAuthorization()
            await rescheduleNotifications()
        }
    }

    init(
        context: MiniAppContext,
        defaults: UserDefaults,
        notificationCenter: UNUserNotificationCenter = .current()
    ) {
        self.context = context
        self.storageKey = context.storageKey("state")
        self.backupLatestKey = context.storageKey("backup.latest")
        self.backupPreviousKey = context.storageKey("backup.prev")
        self.notificationPrefix = context.notificationRequestIdentifier + "."
        self.defaults = defaults
        self.notificationCenter = notificationCenter
        self.configurationError = nil
        let loaded = Self.loadState(from: defaults, key: storageKey)
        items = loaded.items
        appState = loaded.app.mergedWithDefaults()
        currentCategory = InventoryDomain.allCategories
        isEditMode = false
        authorizationStatus = .notDetermined
        transientMessage = nil
    }

    var filteredItems: [InventoryItem] {
        let base = currentCategory == InventoryDomain.allCategories
            ? items
            : items.filter { $0.category == currentCategory }
        return InventoryDomain.sortedItems(
            base,
            pauseState: appState.globalPause,
            thresholdDays: appState.alertThresholdDays
        )
    }

    var availableCategories: [String] {
        let categories = Set(items.map(\.category).filter { !$0.isEmpty })
        let sorted = categories.sorted { $0.localizedCompare($1) == .orderedAscending }
        return [InventoryDomain.allCategories] + sorted
    }

    var alertItems: [InventoryItem] {
        items.filter { isAlertItem($0) }
    }

    var notificationsAuthorized: Bool {
        authorizationStatus == .authorized || authorizationStatus == .provisional || authorizationStatus == .ephemeral
    }

    var notificationStatusText: String {
        if !appState.notificationsEnabled {
            return "アプリ内で通知がオフになっています。"
        }

        switch authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return "在庫が\(Int(appState.alertThresholdDays))日以内に入るタイミングでローカル通知をスケジュールします。"
        case .denied:
            return "通知はiPhoneの設定で拒否されています。設定アプリから許可してください。"
        case .notDetermined:
            return "まだ通知権限を確認していません。リクエストすると有効化できます。"
        @unknown default:
            return "通知状態を確認できませんでした。"
        }
    }

    var exportFilename: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.dateFormat = "yyyyMMdd"
        return "zaiko_backup_\(formatter.string(from: .now)).json"
    }

    func displayMode(for item: InventoryItem) -> DisplayMode {
        InventoryDomain.displayMode(for: item, appState: appState)
    }

    func remainingDays(for item: InventoryItem) -> Double? {
        InventoryDomain.remainingDays(for: item, pauseState: appState.globalPause)
    }

    func remainingStock(for item: InventoryItem) -> Double? {
        InventoryDomain.remainingStock(for: item, pauseState: appState.globalPause)
    }

    func isAlertItem(_ item: InventoryItem) -> Bool {
        InventoryDomain.isAlert(
            item: item,
            pauseState: appState.globalPause,
            thresholdDays: appState.alertThresholdDays
        )
    }

    func setAlertThresholdDays(_ days: Double) {
        appState.alertThresholdDays = max(1, min(days, 30))
        persistAndSchedule()
    }

    func addItem(from draft: ItemDraft) throws {
        let item = try InventoryDomain.makeItem(from: draft)
        items.append(item)
        if !item.unit.isEmpty {
            appState.unitPreferences[item.unit] = draft.displayMode
        }
        persistAndSchedule()
    }

    func updateItem(id: Int64, with draft: ItemDraft) throws {
        guard let index = items.firstIndex(where: { $0.id == id }) else {
            throw ZaikoError.itemNotFound
        }

        items[index] = try InventoryDomain.updateItem(items[index], with: draft)
        if !items[index].unit.isEmpty {
            appState.unitPreferences[items[index].unit] = draft.displayMode
        }
        persistAndSchedule()
    }

    func deleteItem(id: Int64) {
        items.removeAll { $0.id == id }
        appState.notificationRecords.removeValue(forKey: String(id))
        if currentCategory != InventoryDomain.allCategories, !items.contains(where: { $0.category == currentCategory }) {
            currentCategory = InventoryDomain.allCategories
        }
        persistAndSchedule()
    }

    func applyRestock(to id: Int64, remaining: Double, added: Double) throws {
        guard let index = items.firstIndex(where: { $0.id == id }) else {
            throw ZaikoError.itemNotFound
        }

        guard remaining >= 0, added >= 0 else {
            throw ZaikoError.validation("補充値は0以上で入力してください。")
        }

        items[index] = InventoryDomain.applyRestock(
            to: items[index],
            remaining: remaining,
            added: added,
            pauseState: appState.globalPause
        )
        appState.notificationRecords.removeValue(forKey: String(id))
        persistAndSchedule()
    }

    func togglePause() {
        if appState.globalPause.active {
            items = InventoryDomain.shiftItemsForPause(
                items,
                pauseStartedAt: appState.globalPause.startedAt,
                resumedAt: .now
            )
            appState.globalPause = GlobalPauseState(active: false, startedAt: nil)
            persistAndSchedule()
            return
        }

        appState.globalPause = GlobalPauseState(active: true, startedAt: .now)
        persistAndSchedule()
    }

    func exportBackupJSON() -> String {
        let envelope = BackupEnvelope(
            version: 3,
            items: items,
            app: persistedAppState()
        )
        let encoder = Self.makeEncoder(prettyPrinted: true)
        let data = (try? encoder.encode(envelope)) ?? Data()
        return String(decoding: data, as: UTF8.self)
    }

    func importBackup(data: Data) throws {
        let decoder = Self.makeDecoder()

        if let envelope = try? decoder.decode(BackupEnvelope.self, from: data) {
            items = envelope.items
            appState = envelope.app.mergedWithDefaults()
            currentCategory = InventoryDomain.allCategories
            persistAndSchedule()
            return
        }

        if let legacyEnvelope = try? decoder.decode(LegacyBackupEnvelope.self, from: data) {
            items = legacyEnvelope.items.compactMap { InventoryDomain.normalize($0) }
            appState = Self.makeAppState(from: legacyEnvelope.app)
            currentCategory = InventoryDomain.allCategories
            persistAndSchedule()
            return
        }

        if let legacyArray = try? decoder.decode([LegacyInventoryItem].self, from: data) {
            items = legacyArray.compactMap { InventoryDomain.normalize($0) }
            appState = AppState.makeDefault().mergedWithDefaults()
            currentCategory = InventoryDomain.allCategories
            persistAndSchedule()
            return
        }

        throw ZaikoError.importFailed
    }

    func present(error: Error) {
        transientMessage = error.localizedDescription
    }

    func requestNotificationPermission() async {
        await refreshNotificationAuthorization()

        if notificationsAuthorized {
            appState.notificationsEnabled = true
            persist()
            await rescheduleNotifications()
            return
        }

        if authorizationStatus == .denied {
            appState.notificationsEnabled = false
            persist()
            transientMessage = "iPhoneの設定 > 通知 > 在庫管理 から通知を許可してください。"
            return
        }

        do {
            let granted = try await notificationCenter.requestAuthorization(options: [.alert, .badge, .sound])
            await refreshNotificationAuthorization()
            if granted {
                appState.notificationsEnabled = true
                persist()
            } else {
                appState.notificationsEnabled = false
                persist()
            }
            await rescheduleNotifications()
        } catch {
            appState.notificationsEnabled = false
            persist()
            transientMessage = error.localizedDescription
        }
    }

    func setNotificationsEnabled(_ enabled: Bool) async {
        if enabled {
            appState.notificationsEnabled = true
            persist()
            await requestNotificationPermission()
            return
        }

        appState.notificationsEnabled = false
        persist()
        transientMessage = nil
        await rescheduleNotifications()
    }

    func refreshNotificationAuthorization() async {
        let settings = await notificationCenter.notificationSettings()
        authorizationStatus = settings.authorizationStatus
    }

    private func persistAndSchedule() {
        persist()

        Task {
            await rescheduleNotifications()
        }
    }

    private func persist() {
        guard let defaults else {
            transientMessage = configurationError?.localizedDescription ?? "共有保存先を解決できません"
            return
        }
        let appToSave = persistedAppState()
        let envelope = BackupEnvelope(version: 3, items: items, app: appToSave)
        let encoder = Self.makeEncoder(prettyPrinted: false)

        guard let data = try? encoder.encode(envelope) else {
            transientMessage = "データ保存に失敗しました。"
            return
        }

        let previous = defaults.data(forKey: storageKey)
        defaults.set(data, forKey: storageKey)
        defaults.set(data, forKey: backupLatestKey)
        if let previous {
            defaults.set(previous, forKey: backupPreviousKey)
        }

        appState = appToSave
    }

    private func persistedAppState() -> AppState {
        var next = appState.mergedWithDefaults()
        next.firstSavedAt = items.isEmpty ? appState.firstSavedAt : (appState.firstSavedAt ?? .now)

        let activeKeys = Set(items.map { String($0.id) })
        next.notificationRecords = next.notificationRecords.filter { activeKeys.contains($0.key) }
        return next
    }

    private func nextNotificationDate(for item: InventoryItem, now: Date = .now) -> Date? {
        guard
            !appState.globalPause.active,
            let remaining = InventoryDomain.remainingDays(for: item, pauseState: appState.globalPause, now: now)
        else {
            return nil
        }

        let thresholdDays = appState.alertThresholdDays
        let offsetFromThreshold = remaining - thresholdDays
        if offsetFromThreshold <= 0 {
            return now.addingTimeInterval(5)
        }

        return now.addingTimeInterval(offsetFromThreshold * 86_400)
    }

    private func notificationRequest(for item: InventoryItem, fireDate: Date) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = "\(item.name) の補充タイミングです"
        content.body = item.unit.isEmpty
            ? "在庫がしきい値に入りました。補充を確認してください。"
            : "在庫がしきい値に入りました。\(item.unit)の残量を確認してください。"
        content.sound = .default
        content.userInfo = context.notificationUserInfo

        let components = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: fireDate
        )
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        return UNNotificationRequest(
            identifier: notificationPrefix + String(item.id),
            content: content,
            trigger: trigger
        )
    }

    func rescheduleNotifications() async {
        await refreshNotificationAuthorization()

        let itemIdentifiers = Set(items.map { notificationPrefix + String($0.id) })
        let pending = await notificationCenter.pendingNotificationRequests()
        let staleIdentifiers = pending
            .map(\.identifier)
            .filter { $0.hasPrefix(notificationPrefix) && !itemIdentifiers.contains($0) }

        if !staleIdentifiers.isEmpty {
            notificationCenter.removePendingNotificationRequests(withIdentifiers: staleIdentifiers)
        }

        guard appState.notificationsEnabled, notificationsAuthorized else {
            notificationCenter.removePendingNotificationRequests(withIdentifiers: Array(itemIdentifiers))
            return
        }

        let now = Date()
        var nextRecords = appState.notificationRecords

        for item in items {
            let identifier = notificationPrefix + String(item.id)

            guard let fireDate = nextNotificationDate(for: item, now: now) else {
                notificationCenter.removePendingNotificationRequests(withIdentifiers: [identifier])
                continue
            }

            let cycleKey = item.notificationCycleKey
            let hasRecord = nextRecords[String(item.id)] == cycleKey
            if fireDate <= now.addingTimeInterval(6), hasRecord {
                continue
            }

            let request = notificationRequest(for: item, fireDate: fireDate)
            do {
                try await notificationCenter.add(request)
                nextRecords[String(item.id)] = cycleKey
            } catch {
                transientMessage = error.localizedDescription
            }
        }

        if nextRecords != appState.notificationRecords {
            appState.notificationRecords = nextRecords
            persist()
        }
    }

    private static func loadState(from defaults: UserDefaults, key: String) -> BackupEnvelope {
        guard let data = defaults.data(forKey: key) else {
            return BackupEnvelope(version: 3, items: [], app: AppState.makeDefault())
        }

        let decoder = makeDecoder()
        return (try? decoder.decode(BackupEnvelope.self, from: data))
            ?? BackupEnvelope(version: 3, items: [], app: AppState.makeDefault())
    }

    private static func makeEncoder(prettyPrinted: Bool) -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(DateCoding.string(from: date))
        }
        if prettyPrinted {
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        }
        return encoder
    }

    private static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let rawValue = try container.decode(String.self)

            if let parsed = DateCoding.date(from: rawValue) {
                return parsed
            }

            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unsupported ISO8601 date: \(rawValue)"
            )
        }
        return decoder
    }

    private static func makeAppState(from legacyApp: LegacyAppState?) -> AppState {
        guard let legacyApp else {
            return AppState.makeDefault()
        }

        var state = AppState.makeDefault()
        state.globalPause = legacyApp.globalPause ?? state.globalPause
        state.unitPreferences = state.unitPreferences.merging(legacyApp.unitPreferences ?? [:]) { _, new in new }
        state.installMarker = legacyApp.installMarker ?? state.installMarker
        state.firstSavedAt = legacyApp.firstSavedAt
        state.alertThresholdDays = legacyApp.alertThresholdDays ?? state.alertThresholdDays
        return state
    }
}
#endif
