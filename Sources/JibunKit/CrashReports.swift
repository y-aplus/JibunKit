#if os(iOS)
import CryptoKit
import Foundation
import MetricKit
import Observation
import SwiftUI

/// Crash and hang reports that iOS delivers through MetricKit, usually when
/// JibunKit opens again after it stopped. They stay on this iPhone until the
/// user shares or deletes them in Manage Mini Apps; `Tools/symbolicate-crash.py`
/// turns a shared report into function names and lines.
@MainActor
@Observable
final class CrashReportStore {
    struct Report: Identifiable, Hashable {
        let id: String
        let file: URL
        let receivedAt: Date
        let kind: String
        let summary: [String]
        /// The mini app that was open when the previous process ended.
        let miniApp: String?
        let appVersion: String?

        var isSwiftTrap: Bool { summary.first?.hasPrefix("EXC_BREAKPOINT") == true }
    }

    static let shared = CrashReportStore()
    /// The open mini app, written whenever it changes, so a report can name it.
    static let lastMiniAppKey = "jibunkit.diagnostics.last-mini-app"
    nonisolated private static let limit = 20

    private(set) var reports: [Report] = []
    let directory: URL
    /// Read at launch, before this process opens a mini app.
    private let previousMiniApp: String?
    private let subscriber = Subscriber()
    private var started = false

    init(directory: URL = URL.applicationSupportDirectory.appending(path: "CrashReports", directoryHint: .isDirectory),
         defaults: UserDefaults = .standard) {
        self.directory = directory
        previousMiniApp = defaults.string(forKey: Self.lastMiniAppKey)
        reload()
    }

    /// Subscribes to MetricKit and keeps the payloads it already delivered.
    func start() {
        guard !started else { return }
        started = true
        let directory = directory, miniApp = previousMiniApp
        subscriber.receive = { payloads in
            // MetricKit calls on its own queue; save there, then show on the main actor.
            let saved = Self.save(payloads, to: directory, miniApp: miniApp)
            if saved { Task { @MainActor in CrashReportStore.shared.reload() } }
        }
        MXMetricManager.shared.add(subscriber)
        if Self.save(MXMetricManager.shared.pastDiagnosticPayloads, to: directory, miniApp: miniApp) {
            reload()
        }
    }

    func reload() {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        reports = files.filter { $0.pathExtension == "json" }.compactMap(Self.report(at:))
            .sorted { $0.receivedAt > $1.receivedAt }
    }

    func delete(_ report: Report) {
        try? FileManager.default.removeItem(at: report.file)
        reload()
    }

    func deleteAll() {
        for report in reports { try? FileManager.default.removeItem(at: report.file) }
        reload()
    }

    /// Writes each crash or hang payload once, named by its content, and keeps the newest `limit`.
    nonisolated static func save(_ payloads: [MXDiagnosticPayload], to directory: URL, miniApp: String?) -> Bool {
        var saved = false
        for payload in payloads {
            guard let (kind, summary) = summary(of: payload) else { continue }
            let json = payload.jsonRepresentation()
            let name = SHA256.hash(data: json).prefix(8).map { String(format: "%02x", $0) }.joined()
            let file = directory.appending(path: "\(name).json")
            guard !FileManager.default.fileExists(atPath: file.path),
                  let payloadObject = try? JSONSerialization.jsonObject(with: json) else { continue }
            let info = Bundle.main.infoDictionary ?? [:]
            var record: [String: Any] = [
                "receivedAt": ISO8601DateFormatter().string(from: Date()),
                "kind": kind,
                "summary": summary,
                "appVersion": "\(info["CFBundleShortVersionString"] as? String ?? "?") (\(info["CFBundleVersion"] as? String ?? "?"))",
                "payload": payloadObject,
            ]
            if let miniApp { record["miniApp"] = miniApp }
            do {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                let data = try JSONSerialization.data(withJSONObject: record, options: [.prettyPrinted, .sortedKeys])
                try data.write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
                saved = true
            } catch {
                continue
            }
        }
        if saved { trim(directory) }
        return saved
    }

    nonisolated private static func trim(_ directory: URL) {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        let dated = files.map { ($0, (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast) }
        for (file, _) in dated.sorted(by: { $0.1 > $1.1 }).dropFirst(limit) {
            try? FileManager.default.removeItem(at: file)
        }
    }

    /// The kind and the first lines of a report, or nil for the diagnostics JibunKit does not keep.
    nonisolated static func summary(of payload: MXDiagnosticPayload) -> (String, [String])? {
        if let crash = payload.crashDiagnostics?.first {
            var lines = [[crash.exceptionType.map { exceptionName($0.intValue) },
                          crash.signal.map { signalName($0.intValue) }]
                .compactMap { $0 }.joined(separator: " / ")]
            if let reason = crash.exceptionReason {
                lines.append("\(reason.className): \(reason.composedMessage)")
            }
            if let termination = crash.terminationReason { lines.append(termination) }
            return ("crash", lines.filter { !$0.isEmpty })
        }
        if let hang = payload.hangDiagnostics?.first {
            let seconds = hang.hangDuration.converted(to: .seconds).value
            return ("hang", [String(format: "Hang: %.1f s", seconds)])
        }
        return nil
    }

    nonisolated static func exceptionName(_ type: Int) -> String {
        [1: "EXC_BAD_ACCESS", 2: "EXC_BAD_INSTRUCTION", 3: "EXC_ARITHMETIC", 5: "EXC_SOFTWARE",
         6: "EXC_BREAKPOINT", 10: "EXC_CRASH", 11: "EXC_RESOURCE", 12: "EXC_GUARD"][type] ?? "Exception \(type)"
    }

    nonisolated static func signalName(_ signal: Int) -> String {
        [4: "SIGILL", 5: "SIGTRAP", 6: "SIGABRT", 8: "SIGFPE", 9: "SIGKILL", 10: "SIGBUS", 11: "SIGSEGV",
         13: "SIGPIPE", 15: "SIGTERM"][signal] ?? "Signal \(signal)"
    }

    private static func report(at file: URL) -> Report? {
        guard let data = try? Data(contentsOf: file),
              let record = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let received = (record["receivedAt"] as? String).flatMap(ISO8601DateFormatter().date(from:)) else { return nil }
        return Report(id: file.deletingPathExtension().lastPathComponent, file: file, receivedAt: received,
                      kind: record["kind"] as? String ?? "crash", summary: record["summary"] as? [String] ?? [],
                      miniApp: record["miniApp"] as? String, appVersion: record["appVersion"] as? String)
    }

    private final class Subscriber: NSObject, MXMetricManagerSubscriber, @unchecked Sendable {
        var receive: (@Sendable ([MXDiagnosticPayload]) -> Void)?

        func didReceive(_ payloads: [MXDiagnosticPayload]) {
            receive?(payloads)
        }
    }
}

/// The reports in Manage Mini Apps, to share with whoever fixes the app.
struct CrashReportsScreen: View {
    private let store = CrashReportStore.shared
    @State private var confirmingDeleteAll = false

    var body: some View {
        List {
            if store.reports.isEmpty {
                ContentUnavailableView {
                    Label("No Crash Reports", systemImage: "checkmark.shield")
                } description: {
                    Text("When JibunKit stops unexpectedly, iOS usually delivers a report the next time it opens. Reports stay on this iPhone until you share them.")
                }
            }
            ForEach(store.reports) { report in
                NavigationLink {
                    CrashReportDetail(report: report)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(report.receivedAt, format: .dateTime)
                        Text(verbatim: report.summary.first ?? report.kind).font(.caption.monospaced())
                        if let miniApp = report.miniApp {
                            Text("Open mini app: \(miniApp)").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .onDelete { offsets in
                for index in offsets { store.delete(store.reports[index]) }
            }
        }
        .navigationTitle("Crash Reports")
        .toolbar {
            if !store.reports.isEmpty {
                Button("Delete All", role: .destructive) { confirmingDeleteAll = true }
            }
        }
        .confirmationDialog(Text("Delete all crash reports?"), isPresented: $confirmingDeleteAll, titleVisibility: .visible) {
            Button("Delete All", role: .destructive) { store.deleteAll() }
        }
        .onAppear { store.reload() }
    }
}

private struct CrashReportDetail: View {
    let report: CrashReportStore.Report

    var body: some View {
        List {
            Section {
                LabeledContent("Received", value: report.receivedAt.formatted(.dateTime))
                if let miniApp = report.miniApp {
                    LabeledContent("Open mini app", value: miniApp)
                }
                if let version = report.appVersion {
                    LabeledContent("JibunKit version", value: version)
                }
            }
            Section {
                ForEach(Array(report.summary.enumerated()), id: \.offset) { _, line in
                    Text(verbatim: line).font(.caption.monospaced()).textSelection(.enabled)
                }
                if report.isSwiftTrap {
                    Text("Swift stopped the app on purpose, for example at a force unwrap of nil, an index out of range or a fatalError.")
                        .font(.caption)
                }
            } header: {
                Text("Reason")
            }
            Section {
                ShareLink(item: report.file) {
                    Label("Share the Report", systemImage: "square.and.arrow.up")
                }
            } footer: {
                Text("The report names the functions only as addresses. Share the file with whoever fixes the app; with the symbol files of the build, they can turn it into function names and lines.")
            }
        }
        .navigationTitle(report.kind == "hang" ? Text("Hang") : Text("Crash"))
        .navigationBarTitleDisplayMode(.inline)
    }
}
#endif
