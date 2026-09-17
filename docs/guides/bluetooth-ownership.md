# Bluetooth ownership

`MiniAppBluetoothCoordinator` routes CoreBluetooth central work by `MiniAppID`. Each owner receives a distinct `CBCentralManager`, restoration identifier, scan, peripheral table, delegate lifetime, and connection generation. Two Features may connect to the same physical peripheral; stopping A only invokes A's manager and never calls `cancelPeripheralConnection` on B's manager.

Create one `MiniAppBluetoothService` per Feature and connect it from `MiniAppFeatureLifetime.configure`. Runtime shutdown removes delivery first, then stops the owner's scan and connections. A replacement connection gets a new generation, so callbacks from the previous connect/disconnect cannot affect it. Discovery, read, write, and notify calls require the current owner/generation pair.

Call `prepareRestoration(admitted:)` synchronously from `MiniAppDefinition.onHostLaunch`, after persisted management state has set `lifetime.isStartAllowed`. Do not construct a manager for a disabled/removed owner: CoreBluetooth manager construction is what enables native restoration. A restored peripheral is adopted only by the manager for that admitted owner. Removal calls `unregisterAllOwned()` after management has closed admission and joined lifetime shutdown.

The host must declare `bluetooth-central` in `UIBackgroundModes` when background discovery, connection events, or restoration are required. Add an appropriate Bluetooth usage description (`NSBluetoothAlwaysUsageDescription`; deployment-target requirements should be checked against the shipping SDK). Restoration is not a durable business-data store: persist application intent separately, and do not silently restart removed owners.

The adapter keeps `CBPeripheral`, `CBService`, and `CBCharacteristic` objects for the life of their owner manager. The public coordinator uses portable identifiers and data, while direct CoreBluetooth use remains possible alongside it for device-specific protocols. It intentionally does not generalize the peripheral role or every BLE device protocol.

Simulator compilation and fake callbacks verify routing and lifecycle only. They do not prove radio scanning, authorization UI, connection survival, background wake, or state restoration. Those require a real iPhone/iPad and a controllable BLE peripheral. On device, verify A/B simultaneous connections, A disable/remove while B remains noninitial, power-off/on, deny/allow, connect failure, late disconnect, subscribe/read/write, background delivery, process termination restoration, reboot, and removal before restoration.
