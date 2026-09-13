import UIKit
import SwiftUI
import JibunKitCore

final class ShareViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        guard let context = extensionContext else { return }
        let providers = context.inputItems.compactMap { $0 as? NSExtensionItem }.flatMap { $0.attachments ?? [] }
        let controller = UIHostingController(rootView: ShareInputScreen(context: context, providers: providers))
        addChild(controller)
        view.addSubview(controller.view)
        controller.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            controller.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            controller.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            controller.view.topAnchor.constraint(equalTo: view.topAnchor),
            controller.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        controller.didMove(toParent: self)
    }
}

private struct ShareInputScreen: View {
    let context: NSExtensionContext
    let providers: [NSItemProvider]
    @State private var destinations: [MiniAppIncomingDestination] = []
    @State private var prepared: MiniAppPreparedIncoming?
    @State private var errorMessage: String?
    @State private var job: Task<Void, Never>?
    @State private var started = false
    @State private var ending = false
    @State private var finished = false

    var body: some View {
        NavigationStack {
            List {
                if job != nil { ProgressView("処理しています") }
                if let errorMessage { Text(errorMessage).foregroundStyle(.red).accessibilityIdentifier("share.error") }
                if let prepared {
                    Section("受信先を選択（\(prepared.inputs.count)件）") {
                        ForEach(destinations) { destination in
                            Button(destination.title) { save(to: destination) }
                                .disabled(job != nil || ending)
                                .accessibilityIdentifier("share.destination.\(destination.id)")
                        }
                        if destinations.isEmpty {
                            Text("この入力を受け取れるミニアプリがありません。JibunKitで受信先を登録・有効化してから共有してください。")
                        }
                    }
                    Text("共有データを保存します。JibunKitを開き、「受信」から取り込めます。")
                        .font(.footnote)
                }
            }
            .navigationTitle("JibunKitへ共有")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { cancel() }.disabled(ending)
                }
            }
        }
        .onAppear { load() }
        .onDisappear { job?.cancel() }
    }

    private func load() {
        guard !started else { return }
        started = true
        job = Task { @MainActor in
            defer { job = nil }
            do {
                let result = try await MiniAppIncomingProviderLoader.load(providers)
                var retained = false
                defer { if !retained { try? result.removeTemporaryFiles() } }
                let inbox = try MiniAppIncomingStore.shared()
                let catalog = try await Task.detached { try inbox.destinations() }.value
                try Task.checkCancellation()
                destinations = catalog.filter { destination in result.inputs.allSatisfy { destination.accepts($0.typeIdentifier) } }
                prepared = result
                retained = true
            } catch is CancellationError { }
            catch { errorMessage = error.localizedDescription }
        }
    }

    private func save(to destination: MiniAppIncomingDestination) {
        guard job == nil, let prepared, !ending else { return }
        errorMessage = nil
        job = Task { @MainActor in
            defer { job = nil }
            do {
                let inbox = try MiniAppIncomingStore.shared()
                let task = Task.detached { try inbox.enqueue(for: MiniAppID(destination.id), inputs: prepared.inputs) }
                _ = try await withTaskCancellationHandler { try await task.value } onCancel: { task.cancel() }
                // enqueue rechecks the shared catalog under the same lock as
                // disable/remove. Complete only after the durable rename.
                try? prepared.removeTemporaryFiles()
                self.prepared = nil
                ending = true
                finished = true
                context.completeRequest(returningItems: [])
            } catch is CancellationError { }
            catch { errorMessage = "保存できませんでした。\(error.localizedDescription)" }
        }
    }

    private func cancel() {
        guard !ending else { return }
        ending = true
        let pending = job
        pending?.cancel()
        Task { @MainActor in
            // Wait for callback-owned file copies to settle before terminating
            // this request. A late successful commit remains a successful share.
            await pending?.value
            guard !finished else { return }
            if let prepared { try? prepared.removeTemporaryFiles() }
            self.prepared = nil
            finished = true
            context.cancelRequest(withError: NSError(domain: NSCocoaErrorDomain, code: NSUserCancelledError))
        }
    }
}
