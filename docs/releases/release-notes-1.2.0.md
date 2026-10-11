# JibunKit 1.2.0

Previous stable release: 1.1.0. This release makes adding a Feature mostly a matter of its own files, shows the host's screens in the device language, adds a Focus filter, and lets camera Features configure their own data scanner.

## Adding Features

- A Feature under `Modules/` connects to the host through its own `JibunKitFeature.json`: package products, integration sources, definitions, widgets, build requirements and App Shortcuts. `python3 Tools/jibunkit-feature.py sync` writes the generated Tuist helper, so adding a Feature no longer edits `Project.swift`, `Package.swift`, `MiniAppRegistry.swift` or the widget bundle. Hand-registered Features keep working. See [Mini apps](../mini-apps.md).
- `python3 Tools/jibunkit-feature.py new --name Notes` creates a Feature package on Windows, Linux or macOS, with the same files as `tuist scaffold feature`, which now also creates the integration and `JibunKitFeature.json`.
- `python3 Tools/jibunkit-feature.py check` reports code from a standalone app that changes other Features' state inside JibunKit, such as `UserDefaults.standard` or `UIApplication.shared.open`, with the guide to follow. CI runs it.
- The manual **Compile check** workflow compiles the app and extensions for iOS without tests, signing or an IPA, and reports compiler errors as annotations. It gives feedback without a Mac.

## Host changes you will notice

- The host's own screens follow the device language: the list, management, backup and restore, inbox, the Spotlight search choice, the Share and Action extensions, and Core's start and error text. They are written in English with a Japanese translation, so a device set to Japanese shows the same wording as before and other languages show English. Features keep their own text. A derived host that changed these strings in Swift now changes the English text and its entry in the `Localizable.strings` tables instead.
- The **Show Mini Apps** Focus filter (Settings > Focus > a Focus > Focus Filters > JibunKit). The mini apps a Focus does not choose leave the list, the switch menu, the quick actions and the icon badge. They still open from links, notifications and Spotlight.
- Reminder shows its scheduled reminder on the app icon badge and asks for badge permission with its notification permission.

## For Feature authors

- `MiniAppVisionCaptureAdapter.runDataScanner` and `dataScannerOperation`: create and configure your own `DataScannerViewController` and delegate; the adapter reserves the camera, presents the scanner, starts and stops scanning and dismisses it. End the scan with `MiniAppDataScannerSession.finish()` to finish on the first code, read several codes in a row, or show the code and wait for a tap. See [capture](../guides/capture.md).
- Set `content.filterCriteria = context.notificationFilterCriteria` on notifications so the Focus filter can silence those of hidden mini apps.
- The icon badge needs notification authorization that includes `.badge`; ask for it with your notification permission.

## Fixes

- `MiniAppExternalURL.open` no longer opens another app long after the request: if the user leaves JibunKit while the request waits for activation, it now fails with `inactive` instead of opening the URL when JibunKit next becomes active.

## Verification and limits

Release IPA: 5,348,298 bytes, SHA-256 `43c69940e6694d78e1f9a236dab8ed091c9fb95512c7d36e56d67c75e497d9a6`, built from `3064db5`.


See the [verification record](../verification/2026-10-11-1.2-release.md). Device checks on 2026-10-11 covered the app-wide surfaces from 1.1.0, the data scanner modes and the Focus filter. Notification silencing by the Focus filter could not be tested: on the test device the Focus did not silence JibunKit's notifications even without the filter.
