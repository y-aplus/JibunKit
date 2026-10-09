# JibunKit

JibunKit is a native iOS host for combining your own Swift and SwiftUI features in one app. It preserves normal Swift packages and Apple frameworks while adding explicit boundaries for feature identity, storage, lifecycle, permissions, navigation, system integrations, backup, and shared resources.

It is intended for people who own the source of the features they add. JibunKit is not a runtime plug-in loader, an IPA store, or an automatic converter for existing apps.

English is the primary language for current user and contributor documentation. Historical evidence and issue discussions may remain in Japanese when translating them would obscure their original context. Some maintainer process documents, such as the release procedure, CI boundaries, and coexistence ledger, are also kept in Japanese.

## Release status

The latest release and its IPA are on [GitHub Releases](https://github.com/y-aplus/JibunKit/releases/latest). [Current status](docs/status.md) states the release, its verification and what remains unobserved; other documents link there instead of repeating the version.

CloudKit and APNs integrations are optional and depend on paid signing and Apple services. Their live service paths have not been verified. Other unobserved device or radio conditions remain listed in the status and verification documents; absence of a measurement is not reported as success.

## Start with a feature

The standard path is:

1. Create a private derived repository that keeps JibunKit as `upstream` and your private host as `origin`.
2. Create or adapt a source-based Swift package that exposes a feature view and business APIs.
3. Run the feature independently while developing it.
4. Declare the host connection in the package's `JibunKitFeature.json`, with a thin `MiniAppDefinition` integration.
5. Generate and build the workspace with Tuist and Xcode, locally or through GitHub Actions.
6. Sign and install the resulting app with a method appropriate for your Apple account and device.

Start with [Adding a feature](docs/mini-apps.md). The template command works on Windows, Linux and macOS:

```bash
python3 Tools/jibunkit-feature.py new --name Notes
```

The generated package includes an example app, so feature UI and business logic can be developed without first embedding it in JibunKit. The host integration remains explicit: `JibunKitFeature.json` names the package product, the integration source and the definition, and `python3 Tools/jibunkit-feature.py sync` connects them without editing host files.

For a first feature, prefer an independent package under `Modules/`: it is easier to test in isolation, reuse in a standalone app, and validate from Windows/WSL than code added to the root package. See the feature and build guides for the exact platform limits.

## Build and install

JibunKit currently targets iOS 26 and uses Swift 6, Tuist 4.207.0, and Xcode 26.6 on the verified build path. See [Build, sign, and install](docs/build.md) for local and GitHub Actions commands.

The general delivery path is **source configuration → Tuist/Xcode build → signing → installation**. SideStore is one verified installation example, not a requirement of JibunKit itself. Apple account capabilities, entitlements, App Groups, extensions, and OS services must match the signing method you choose.

## What the host provides

- Stable feature IDs and owner-scoped storage, files, notifications, routes, and system registrations.
- Feature lifecycle and shutdown boundaries for tasks and shared native resources.
- Per-feature management, consent, removal, backup, and restore integration.
- Host composition for navigation, widgets, App Intents, Spotlight, quick actions, icon badges, incoming files, background work, media, location, Bluetooth, multiple windows, and other adopted system surfaces.
- Tests and diagnostic fixtures that keep simulated, native, physical-device, and service-backed evidence distinct.

These are cooperative APIs, not a security sandbox for arbitrary Swift code. A feature remains responsible for its domain validation, data schema, migrations, and correct use of native APIs. Read [Compatibility and stable identities](docs/compatibility.md) before changing IDs, bundle identifiers, App Groups, storage keys, routes, or backup schemas.

## Documentation

- [Adding a feature](docs/mini-apps.md) — package, definition, registration, ownership, and validation.
- [Build, sign, and install](docs/build.md) — local Xcode/Tuist and GitHub Actions paths.
- [Current status](docs/status.md) — stable release, verified boundaries and explicitly unobserved conditions.
- [Feature guides](docs/guides/) — focused integration contracts for Apple system surfaces.
- [Compatibility](docs/compatibility.md) — public API and persisted identity rules.
- [Updating a customized checkout](docs/updating.md) — keeping personal features separate from upstream changes.
- [Contributing](CONTRIBUTING.md) — changes to JibunKit itself.
- [Security policy](SECURITY.md) — private vulnerability reporting.
- [Changelog](CHANGELOG.md) — user-visible history and release state.

Implementation plans, delivery contracts, and dated verification records are supporting evidence. They are not the first-use instructions and do not expand the claims of the current stable release.

## License

JibunKit is available under the [MIT License](LICENSE). Apple SDKs, signing services, and third-party tools keep their own terms. See [third-party notices](THIRD_PARTY_NOTICES.md). This repository does not include Apple SDKs, signing keys, provisioning profiles, or device credentials.
