// Included only in the isolated signed CI host, never in a distributed IPA.
import Foundation
import JibunKitCore
import Observation
import SwiftUI

@MainActor
@Observable
final class BackgroundExecutionProbeState {
    var result = "idle"

    func run() async {
        result = "running"
        let aRuntime = MiniAppRuntime()
        let bRuntime = MiniAppRuntime()
        do {
            let a = try aRuntime.makeBackgroundExecution(
                context: MiniAppContext(id: MiniAppID("background-a")))
            let b = try bRuntime.makeBackgroundExecution(
                context: MiniAppContext(id: MiniAppID("background-b")))
            guard let aLease = try a.begin(operation: "save"),
                  let bLease = try b.begin(operation: "save") else {
                result = "unavailable"
                await aRuntime.shutdown()
                await bRuntime.shutdown()
                return
            }

            aLease.end()
            aLease.end()
            guard aLease.isEnded, !bLease.isEnded,
                  a.activeOperationCount == 0, b.activeOperationCount == 1 else {
                result = "failed: individual-end"
                await aRuntime.shutdown()
                await bRuntime.shutdown()
                return
            }

            await aRuntime.shutdown()
            guard !bLease.isEnded, b.activeOperationCount == 1 else {
                result = "failed: cross-owner-shutdown"
                await bRuntime.shutdown()
                return
            }
            await bRuntime.shutdown()
            guard bLease.isEnded, b.activeOperationCount == 0 else {
                result = "failed: runtime-cleanup"
                return
            }

            print("BACKGROUND_EXECUTION native-acquired=true a-ended=true b-survived-a-shutdown=true runtime-cleanup=true")
            result = "passed"
        } catch {
            result = "failed: \(error)"
        }
    }
}

@MainActor
enum BackgroundExecutionProbe {
    private static let state = BackgroundExecutionProbeState()
    static let definition = MiniAppDefinition(
        id: MiniAppID("background-execution-probe"),
        title: "Background execution probe",
        systemImage: "timer"
    ) { _ in
        VStack {
            Text(state.result).accessibilityIdentifier("background.execution.result")
            Button("Run background execution check") {
                Task { await state.run() }
            }.accessibilityIdentifier("background.execution.run")
        }
    }
}
