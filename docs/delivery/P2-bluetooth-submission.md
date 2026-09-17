# P2 Bluetooth submission

## Delivered boundary

- `MiniAppBluetoothCoordinator` and `MiniAppBluetoothService`: owner-scoped admission, scan/connect/disconnect, service/characteristic discovery, read/write/subscribe, generation filtering, shutdown, unregister, and synchronous restoration preparation.
- `MiniAppCoreBluetoothCentral`: normal CoreBluetooth central adapter with owner-specific restoration identifiers and retained peripheral/service/characteristic delegates.
- Pure XCTest coverage for two-owner isolation, same-peripheral cancellation, stale/duplicate callbacks, power/authorization gates, disabled restoration, and the full operation surface.
- `P2BluetoothProbe`: two ordinary Feature definitions using independent `MiniAppFeatureLifetime` instances; native tests exercise definitions and manager construction.

## Host integration

The parent-owned host should append `P2BluetoothProbe.definitions` to its registry/native fixture, call existing `onHostLaunch` hooks after persisted management admission is applied, and compose `UIBackgroundModes = [bluetooth-central]` plus a Bluetooth usage description into the fixture manifest. No host, manifest, project, or workflow file is changed by this submission.

Shutdown order is management admission close, lifetime/runtime join, native owner cancellation, then unregister/removal. The coordinator removes generations before explicit cancel so duplicate disconnect callbacks cannot revive or mutate the owner. A disabled owner's launch hook passes `false`, so no `CBCentralManager` exists to restore it.

## Evidence and remaining checks

The pure tests use an instrumented fake and must not be described as radio evidence. An iOS Simulator native build proves adapter compilation only; Simulator lacks the BLE radio behavior needed for this contract. Real-device radio, permission UI, background wake, termination/relaunch restoration, and reboot remain manual device checks described in the guide. Real APNs/CloudKit and P2 background/cold/radio validation remain outside this submission.

This worker ran on Windows where `swift`/`swiftc` is not installed. Therefore neither SwiftPM XCTest nor the iOS/CoreBluetooth compile was run here; the parent native boundary must run both against this exact source commit on macOS/Xcode 26.

Swift 6 review: coordinator, service, adapter, delegates, and XCTest fixtures are `@MainActor`; escaping event callbacks are explicitly main-actor/sendable and capture owners/services weakly where lifetimes can outlive consumers. Runtime cleanup captures stable owner/token values and clears only the matching service generation.
