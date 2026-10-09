# On-device language models

## Current integration contract

JibunKit has no API for Apple's FoundationModels framework. A Feature imports it and uses the system model directly. This guide covers the on-device model only.

A shared host API is not needed because the framework has nothing one Feature could change for another. Unlike an audio session category, there is no process-wide configuration: a `LanguageModelSession` is an object owned by whoever creates it, and `SystemLanguageModel.default` is read for availability only. Stopping and cleanup use the existing [Feature lifetime](feature-lifetime.md). The one thing Features may share is the system's rate limit, described [below](#rate-limits).

### Check availability before each request

Read `SystemLanguageModel.default.availability` before each generation, not once at launch. It changes when the user turns Apple Intelligence on or off and while the model downloads. Show the unavailable reason, such as an ineligible device, Apple Intelligence turned off, or the model not ready, so the user knows what to change.

### Keep sessions inside the Feature

Create the Feature's own `LanguageModelSession` and do not share it with another Feature. A session handles one request at a time; sending another while it is responding fails. Disable input while `isResponding` is true, or wait for the previous request.

### Tie generation to a screen or to the Feature lifetime

Generation started for one screen can be cancelled when the screen goes away, for example with `.task` or by cancelling the task in `onDisappear`. Switching to another Feature also takes the screen away and stops it.

Generation that must continue after the screen changes belongs to the Feature lifetime. Read the `miniAppLifetime` environment value and start it with `lifetime.runtime?.start { ... }` (see `CounterRootView`), so disabling or deleting the Feature waits for it to end. Do not start generation from a detached task that the host cannot stop.

Apple recommends `respond(to:)` instead of streaming for background work. Using the model from the Feature's [background execution](background-execution-ownership.md) has not been tested in this repository.

### Saved data

If the Feature does not save prompts, responses, or transcripts, it needs no removal provider or backup entry for them. If it saves any of them, treat them as Feature data: use owner-scoped storage and a [removal provider](feature-data-removal.md) like any other saved data.

### Error types depend on the Xcode version

The iOS 27 SDK deprecates `LanguageModelSession.GenerationError` and splits its cases across newer error types. An app built with an earlier Xcode keeps receiving the old type, even on iOS 27. The host currently builds with Xcode 26.6, so Features receive `GenerationError`. When the host moves to Xcode 27, check the error handling against that SDK.

### Tests

Keep the model calls in one file, wrapped in `#if os(iOS)` if needed, and keep prompt building, result formatting, and other logic in plain Swift. CI runs Feature package tests on macOS without a usable model ([why](../mini-apps.md#your-package-is-also-built-for-macos)), so test that logic there and check generation on a device.

### Rate limits

The system can reject requests with a rate limit error. Apple does not document what the limit counts, such as the app, the device, or the kind of work. If it counts the app, Features in one JibunKit host share a budget that standalone apps would each have had, and one Feature's use could cause another's errors. The host cannot raise the limit, so Features should show the error and let the user retry later. This difference is recorded as unverified in the [coexistence ledger](../coexistence-ledger.md) (D41).
