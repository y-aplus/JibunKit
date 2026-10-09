# JibunKit 1.1.0

Previous stable release: 1.0.0. This release adds app-wide system surfaces that iOS gives the app only once, Feature parts that camera and app-launching Features previously had to copy, and fixes found while moving existing apps into a derived host.

## Host changes you will notice

- The bottom “ミニアプリを切り替え” bar is gone, so the bottom edge belongs to the Feature. On a Feature root, tap “ミニアプリ” to return to the list, or long-press it to switch to another Feature. Switching from a detail screen requires going back first. Paths left through URLs, notifications, quick actions or Spotlight still resume.
- The app has a default icon. A derived host replaces `Sources/JibunKit/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png` with its own.

## New app-wide surfaces

Each is opt-in per Feature and routed only to its owner.

- Spotlight "Search in App" (`MiniAppDefinition.searchDestination`). One accepting Feature opens directly; several are offered as a choice.
- Home Screen quick actions for recently opened Features (`quickActions`, or one default item that opens the Feature).
- Per-Feature icon badge counts (`MiniAppContext.setBadgeCount`). The icon shows the sum over enabled Features.
- A Feature's own `NSUserActivity` types, such as Handoff (`MiniAppDefinition.userActivity`).
- Optional Notification Service and Content extensions with owner dispatch. Neither is built unless enabled, because each needs its own App ID when signing.
- The host configures TipKit once at launch. **Features must not call `Tips.configure()`.**

## New Feature parts

- `MiniAppExternalURL.open(_:)` opens another app and waits for JibunKit to become active, so a request made right after a Spotlight or notification launch is not dropped.
- `MiniAppPresentationAnchor` and `MiniAppConsentSource` for presenting UIKit controllers and reading consent from objects created with the definition. `MiniAppCaptureOwner` and `MiniAppVisionCaptureAdapter` accept them.
- `MiniAppVisionCaptureAdapter.scanCode(owner:)` returns a scanned code, or nil when the scanner was closed or stopped.

## Fixes

- A presented document or code scanner always reports `ended`, including when its capture owner stops it. Code waiting for the scan no longer hangs.
- Backup import rejects archives with more than 100,000 entries or a declared size beyond the available disk space, and stops writing an entry that expands past its declared size.
- Incoming handoff rejects unaccepted types before copying files.
- The widget extension is built with extension-only API checks.
- **Publish IPA prerelease** no longer rejects every successful build run.

## Documentation

Moving an existing app into a Feature, Swift 5 language mode per target, Feature packages built for macOS in CI, model-state navigation and URLs of a Feature's own scheme, widget products, publishing a derived host's IPA, and using the on-device language model (FoundationModels).

## Verification and limits

Shared, Module, native media, optional-extension, normal-host UI and generated-host UI tests ran on the candidate source. Five generated-host UI tests (two notification tests, the Records reminder, the idle timer and Web data clearing) fail; they failed in the same way before this release and are not counted as passes. On an iPhone, the owner confirmed the new icon, kept Counter and Reminder data after an overwrite install, the root “ミニアプリ” button and long-press switching, and quick actions from a running and a closed app.

Icon badges, Spotlight "Search in App", `NSUserActivity` routing, `MiniAppExternalURL`, `scanCode` and the notification extensions are not used by the Features in the normal IPA. They are covered by automated tests and builds, not by a device check of this release. The [verification record](../verification/2026-10-10-1.1-release.md) lists the runs and results.

## Build and installation

Configure your Features, build with Tuist/Xcode, then sign and install using a method appropriate to your environment. SideStore is one tested installation example. Back up data before replacing an installation; keep bundle IDs, Feature IDs and storage identities stable.

Version: 1.1.0/build17. Build source `0a6c4602690c233f69ed3d4b148f0a430db181ec`, run 37959506516 succeeded. IPA SHA-256: `c1e0ac8c599db9fba4d1a0c61870db73a36202a50a03f7e21ef09d69ca41998e` (5,258,091 bytes).
