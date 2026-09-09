#if os(iOS)
import SwiftUI

struct RecordReminderSection: View {
    let record: Record
    let actions: RecordReminderActions
    @State private var date = Date().addingTimeInterval(3600)
    @State private var busy = false
    @State private var status: String?

    var body: some View {
        Section {
            DatePicker("通知日時", selection: $date, in: Date()...)
            Button("通知を予約") {
                busy = true
                Task {
                    defer { busy = false }
                    do { try await actions.schedule(record, date); status = "通知を予約しました。" }
                    catch { status = error.localizedDescription }
                }
            }.accessibilityIdentifier("records.reminder.schedule")
            Button("この記録の通知を取り消す") {
                busy = true
                Task {
                    defer { busy = false }
                    do { try await actions.cancel(record.id); status = "この記録の通知を取り消しました。" }
                    catch { status = error.localizedDescription }
                }
            }.accessibilityIdentifier("records.reminder.cancel")
            if let status { Text(status).accessibilityIdentifier("records.reminder.status") }
        } header: {
            Text("この記録の通知")
        } footer: {
            Text("再予約はこの記録の通知を置き換えます。他の記録の通知は変更しません。")
        }
        .disabled(busy)
    }
}
#endif
