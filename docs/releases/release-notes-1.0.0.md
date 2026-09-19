# JibunKit 1.0.0 — unpublished candidate

Final publication approval is pending. The current stable release is 0.8.5.

JibunKit hosts independently developed Swift/SwiftUI Features in one iOS app. It supplies ownership, coordination and lifecycle boundaries that would otherwise be lost when separate apps share a process. It is a source integration framework, not a loader for arbitrary IPA files or a security sandbox between Features.

## Included scope

- Owner-scoped persistence, selected backups, restore, schema and data-removal hooks; Feature lifecycle and failure isolation.
- Navigation, scene-bound presentation, incoming files and sharing, notifications, HTTP/Web state, widgets, controls and App Intents.
- Audio, capture, Live Activities/alarms, background work and transfer reconnection, location, BLE, multiple windows and ordinary foreground AR.
- Standalone Feature scaffolding and Tuist/Xcode host integration. The normal IPA includes Counter and Reminder; Records is a source example. Diagnostic Features and private Zaiko sources are excluded.

## Verification and limits

The owner accepted the v1 criteria on 2026-09-19. [Acceptance and unobserved conditions](../verification/2026-09-19-final-observation-boundary.md) distinguish physical-device results, Simulator results and native contract tests. Physical iBeacon/background boundary delivery, actual BackgroundTasks launch/expiration, physical iPad multiple windows and actual AR OS-interruption recovery remain unobserved. They are not reported as passed.

CloudKit and APNs are optional integrations requiring suitable signing and service configuration; live communication is unverified and is not a prerequisite for the normal free-signing use case. Generic HTTP synchronization and owner isolation remain supported requirements.

Feature namespaces are cooperative isolation, not security boundaries. OS scheduling, signing entitlements and platform limits remain in force. Features own their data schemas, server semantics and recovery behavior.

## Build and installation

Configure your Features, build with Tuist/Xcode, then sign and install using a method appropriate to your environment. SideStore is one tested installation example, not a JibunKit dependency. Back up data before replacing an installation; keep bundle IDs, Feature IDs and storage identities stable.

Candidate: 1.0.0/build16. Candidate source, CI result and IPA SHA-256 will be finalized in the [release verification record](../verification/2026-09-19-1.0-release.md) before approval. No release asset is published yet.
