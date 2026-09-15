import Foundation
import JibunKitCore

#if os(macOS)
let args = CommandLine.arguments
guard args.count >= 4 else { fatalError("root command owner [argument]") }
let root = URL(fileURLWithPath: args[1], isDirectory: true)
let store = try MiniAppSharedState<Int>(owner: MiniAppID(args[3]), containerURL: root)
do {
    switch args[2] {
    case "prepare": try store.initialize(0, enabled: true)
    case "increment":
        let generation = try store.read().generation
        for _ in 0..<Int(args[4])! { try store.update(generation: generation) { $0 += 1 } }
    case "read":
        let snapshot = try store.read()
        let result: [String: Any] = ["generation": snapshot.generation.uuidString, "value": snapshot.value]
        print(String(data: try JSONSerialization.data(withJSONObject: result), encoding: .utf8)!)
    case "close":
        FileHandle.standardOutput.write(Data("closing\n".utf8))
        try store.setEnabled(false)
    case "enable": try store.setEnabled(true)
    case "replace": try store.replaceWhileDisabled(Int(args[4])!)
    case "remove": try store.remove()
    case "old": try store.update(generation: UUID(uuidString: args[4])!) { $0 += 999 }
    case "pin":
        let generation = try store.read().generation
        try store.update(generation: generation) { value in
            value += 1
            FileHandle.standardOutput.write(Data("pinned\n".utf8))
            guard readLine() == "release" else { throw CocoaError(.userCancelled) }
        }
    default: fatalError("unknown command")
    }
} catch {
    FileHandle.standardError.write(Data((String(describing: error) + "\n").utf8))
    exit(2)
}
#endif
