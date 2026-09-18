# P2-S Android BLE peripheral setup

This is a preparation recipe, not radio evidence. It uses nRF Connect for Android as a controllable GATT peripheral. Do not install it or claim P2-S device completion until the candidate app and iPad build have both been approved.

## Android setup

The Android device must support BLE peripheral advertising. Android exposes this through `BluetoothAdapter.isMultipleAdvertisementSupported()` and a non-null `BluetoothLeAdvertiser`; nRF Connect must also show and successfully start its Advertiser. Turn Bluetooth on and grant the Nearby devices permissions requested by the app. Android 12 and later enforce `BLUETOOTH_ADVERTISE` for advertising and `BLUETOOTH_CONNECT` for communication. Older Android/app versions can additionally request Location for BLE scanning.

In nRF Connect, open **Configure GATT Server**, create and select a custom configuration, and enter the values from [the fixture README](../../Tests/Fixtures/ble-peripheral/README.md):

1. Add primary service `ad539a02-1289-44dc-bd27-f991c68a1fb9`.
2. Add characteristic `9e0f4195-64b6-4c4a-8ffa-e8dd8f4036d5` with READ and WRITE properties and open read/write permissions.
3. Add characteristic `0b1ec4d4-1383-4460-b1e2-9ae98653cc1b` with READ and NOTIFY properties and open read/write permissions. nRF Connect adds its CCCD automatically.
4. Import [JibunKit-P2S-notify.xml](../../Tests/Fixtures/ble-peripheral/JibunKit-P2S-notify.xml) in the Macros screen. Nordic publishes the macro XML grammar and examples; the fixture follows those documented elements and hexadecimal byte syntax.
5. Set the Android local name to `JibunKit-P2S-5276`. Create a connectable advertisement containing the custom service UUID, then start the selected GATT server configuration and advertisement.

Legacy advertising data is limited to 31 bytes. A 128-bit service UUID plus the complete local name and protocol overhead may not fit in one packet. Keep the service UUID in the primary advertisement and put the local name in the scan response, or shorten the advertised name if nRF Connect reports overflow. The Android address may rotate and is not a stable identifier.

Nordic documents that GATT server configurations can be imported from XML, but its public documentation does not specify that XML schema. For that reason this repository deliberately provides manual GATT setup plus a documented-format macro, not a guessed server-configuration file.

## Safe JibunKit sequence

The current P2 Bluetooth probe calls an unfiltered `scan()`; the service UUID text field does not filter scan results. Use the advertised local name only to choose the likely Android device, then prove its identity after connecting:

1. Start the imported macro on Android. It sets the READ + WRITE characteristic to `01 02` and waits for a read.
2. In JibunKit, scan and select `JibunKit-P2S-5276`. Do not write yet.
3. Connect, discover all services, and verify service `ad539a02-1289-44dc-bd27-f991c68a1fb9` exists.
4. Enter the READ + WRITE characteristic UUID, discover it, and read it. Continue only if the received value is exactly `01 02`.
5. Enter the READ + NOTIFY characteristic UUID, discover it, and subscribe. Wait for the UI to show that notification is enabled.
6. Return to the READ + WRITE characteristic, set the outgoing hex to `03 04`, and use **Write with response**. Android's macro checks that exact value and sends notification `05 06`.
7. Verify JibunKit reports a successful write and receives `05 06` from the NOTIFY characteristic. Save both device logs with the UUIDs and timestamps.

The local name and UUIDs prevent accidental selection in a controlled test area; they are not authentication or a security boundary.

## Primary references

- [Nordic nRF Connect documentation: Advertiser and Configure GATT Server](https://github.com/NordicSemiconductor/Android-nRF-Connect/blob/main/documentation/README.md)
- [Nordic macro XML grammar: server read/write, set-value, and send-notification](https://github.com/NordicSemiconductor/Android-nRF-Connect/blob/main/documentation/Macros/README.md)
- [Nordic macro XML example using hexadecimal bytes](https://github.com/NordicSemiconductor/Android-nRF-Connect/blob/main/Thingy52%20sample%20macros/macros/Blinky.xml)
- [Android Bluetooth permissions](https://developer.android.com/develop/connectivity/bluetooth/bt-permissions)
- [Android BluetoothLeAdvertiser API and 31-byte legacy limit](https://developer.android.com/reference/android/bluetooth/le/BluetoothLeAdvertiser)
- [Android BluetoothAdapter advertising capability check](https://developer.android.com/reference/android/bluetooth/BluetoothAdapter)
