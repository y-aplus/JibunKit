import Foundation
import JibunKitCore

#if os(macOS)
let args = CommandLine.arguments
guard args.count >= 3 else { fatalError("root command [owner] [count]") }
let root = URL(fileURLWithPath: args[1], isDirectory: true)
let inbox = try MiniAppIncomingStore(containerURL: root)
let a = MiniAppID("process-a")
let b = MiniAppID("process-b")
do {
switch args[2] {
case "prepare":
    try inbox.publish([a, b].map { .init(id: $0, title: $0.rawValue, typeIdentifiers: ["public.data"]) })
case "enqueue":
    let owner = MiniAppID(args[3])
    for index in 0..<Int(args[4])! {
        let receipt = try inbox.enqueue(for: owner, inputs: [.text("\(owner.rawValue)-\(index)")])
        print(receipt.id.uuidString)
    }
case "close":
    try inbox.setAdmission(.init(id: a, title: a.rawValue, typeIdentifiers: ["public.data"]), enabled: false)
case "delete":
    try inbox.removeOwnedData(for: a)
case "list":
    let listing = try inbox.pending(for: MiniAppID(args[3]))
    guard listing.unreadableIDs.isEmpty else { fatalError("Incomplete/corrupt published receipt") }
    print(String(data: try JSONEncoder().encode(listing.receipts), encoding: .utf8)!)
case "pin":
    let first = try inbox.pending(for: a).receipts[0]
    try inbox.withReceipt(id: first.id, owner: a) { receipt, _ in
        FileHandle.standardOutput.write(Data(("pinned:" + receipt.id.uuidString + "\n").utf8))
        // The driver releases this barrier after starting another process's
        // removal. Removal must not finish before this accessor returns.
        guard readLine() == "release" else { fatalError("Missing release") }
    }
default: fatalError("Unknown command")
}
} catch {
    FileHandle.standardError.write(Data((String(describing: error) + "\n").utf8))
    exit(2)
}
#else
// The executable is a macOS-only CI helper, never an iOS target dependency.
#endif
