#if canImport(AlarmKit)
import AlarmKit
import JibunKitCore
import SwiftUI

@available(iOS 26.0, *)
public struct AlarmDiagnosticView<F: FixtureAlarmFeature>: View {
    private let runtime: FixtureAlarmRuntime<F>
    @State private var status = "読み込み中"
    public init(runtime: FixtureAlarmRuntime<F>) { self.runtime = runtime }

    public var body: some View {
        Form {
            Section(F.title) {
                Text(status).accessibilityIdentifier("alarm.\(F.owner.rawValue).status")
                Button("OS許可を要求（app全体）") { run { await runtime.requestAuthorization() } }
                Button("5分後に固定登録") { run { await runtime.schedule(.fixed(.now.addingTimeInterval(300))) } }
                Button("平日 9:00 に繰返し") {
                    run { await runtime.schedule(.relative(hour: 9, minute: 0,
                        weekdays: [.monday, .tuesday, .wednesday, .thursday, .friday])) }
                }
                Button("60秒 countdownを今すぐ開始") { run { await runtime.schedule(.immediateCountdown(seconds: 60)) } }
                Button("一時停止") { run { await runtime.perform(.pause) } }
                Button("再開") { run { await runtime.perform(.resume) } }
                Button("停止") { run { await runtime.perform(.stop) } }
                Button("取消") { run { await runtime.perform(.cancel) } }
                Button("cold照合") { run { await runtime.reconcile() } }
                Button("このFeatureだけreset") { run { await runtime.resetFeatureOnly() } }
            }
        }
        .task { await refresh() }
    }

    private func run(_ operation: @escaping @Sendable () async -> Void) {
        Task { await operation(); await refresh() }
    }
    @MainActor private func refresh() async { status = await runtime.message }
}

@available(iOS 26.0, *)
public enum AlarmDiagnosticViewFactory {
    public static func featureA() -> some View { AlarmDiagnosticView(runtime: featureAAlarmRuntime) }
    public static func featureB() -> some View { AlarmDiagnosticView(runtime: featureBAlarmRuntime) }
}
#endif
