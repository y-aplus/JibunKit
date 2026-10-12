# Adding a feature

A JibunKit feature is source code compiled into the host at build time. The preferred shape is a Swift package with business logic and a root view, plus a thin integration that creates one `MiniAppDefinition`.

JibunKit does not load arbitrary IPAs or runtime plug-ins. It also does not automatically convert an existing app target: separate reusable feature code from the app shell first. [Moving an existing app](#moving-an-existing-app) lists what the app shell did and where each responsibility goes.

Prefer a separate package under `Modules/<Name>` for a new personal feature. It gives the feature an isolated test command, a standalone example, and a clearer reuse boundary; a portable package can also run its own tests on Linux/WSL even though the repository's root package cannot. Adding sources to the root package can be reasonable for code inseparable from the host, but it couples validation to the macOS/Xcode path and increases shared CI work.

## 1. Create a standalone feature

On Windows, Linux or macOS, with Python 3:

```bash
python3 Tools/jibunkit-feature.py new --name Notes
```

On macOS, `tuist scaffold feature --name Notes` creates the same files; then run `python3 Tools/jibunkit-feature.py sync` (see [section 2](#2-connect-it-to-the-host)). CI checks that both create identical files.

Use a valid Swift type name beginning with an uppercase letter. The command creates, under `Modules/Notes`, a Swift package with a root view, a small example app with UI-test scaffolding, an `Integration` directory and `JibunKitFeature.json`. It refuses to overwrite an existing directory. The example app needs Tuist on macOS: `tuist generate --path Modules/Notes --no-open`.

Develop and test `NotesExample` independently. Keep domain models, persistence rules, validation, and feature-specific native behavior in this package. The feature package does not need to depend on JibunKitCore unless it directly uses its APIs.

## 2. Connect it to the host

`Modules/Notes/JibunKitFeature.json` declares how the host connects the feature:

```json
{
  "schema": 1,
  "id": "notes",
  "products": ["NotesFeature"],
  "sources": ["Integration/**"],
  "definitions": ["NotesMiniApp.definition"]
}
```

| Key | Meaning |
| --- | --- |
| `id` | The feature ID. It also owns the build requirements and App Shortcuts below. |
| `products` | Library products of this package that the app target depends on. |
| `sources` | Globs inside this directory that the app target compiles, normally the integration. |
| `definitions` | Expressions that each produce one `MiniAppDefinition`. They are added after the hand-registered features in `MiniAppRegistry`. |
| `app` | Optional `infoPlist`, `entitlements` and `localizedInfoPlist` for the app target ([build requirements](guides/feature-build-requirements.md)). |
| `widget` | Optional `products`, `sources` and `widgets` (expressions such as `"NotesWidget()"`) for the widget extension, plus its own `infoPlist`, `entitlements` and `localizedInfoPlist` ([static widgets](guides/package-static-widgets.md)). |
| `appShortcuts` | Optional `{"source": "Integration/AppShortcuts.swift.fragment", "imports": [...]}` ([App Intents](guides/package-app-intents.md)). |

After adding or changing a `JibunKitFeature.json`, run:

```bash
python3 Tools/jibunkit-feature.py sync
```

It checks the files and rewrites `Tuist/ProjectDescriptionHelpers/ModuleFeatures.swift`, which `Project.swift` reads. Commit that file with the feature. `tuist generate` then adds the package, its products, the integration sources, the registry entry, the widgets, the build requirements and the App Shortcuts. You do not edit `Project.swift`, `Package.swift`, `MiniAppRegistry.swift` or the widget bundle, so updates from upstream do not conflict with your features there. CI fails when `sync --check` finds the helper out of date. Every Feature's integration sources compile into the host app as one Swift module, so `sync` also stops when two Features, or a Feature and the host, put a file with the same name or a non-private type, `let` or `var` with the same name at file scope into the app or widget target; it names both files. Otherwise `sync` reads the files only; it does not prove that the code compiles.

Features registered by hand, as Counter and Reminder are, keep working. Do not register the same definition both ways.

## 3. Write the integration

The integration is the thin layer that creates the definition. The generated `Integration/NotesMiniApp.swift` is compiled into the host app, not into the package:

```swift
import JibunKitCore
import NotesFeature

@MainActor
enum NotesMiniApp {
    static let definition = MiniAppDefinition(
        id: MiniAppID("notes"),
        title: "Notes",
        systemImage: "square.grid.2x2"
    ) { _ in
        NotesRootView()
    }
}
```

Because it is part of the app target, it can use JibunKitCore even when the feature package does not depend on it. Give its types names that start with the feature name; they share the app module with every other integration. It is not covered by the package's `swift test`, so keep it thin.

The ID must begin with a lowercase ASCII letter and contain only lowercase letters, digits, `.`, `-`, and `_`. It becomes part of storage, notification, routing, backup, and system-registration identities. Treat a shipped ID as persistent data: do not rename it without a migration. Keep `id` in `JibunKitFeature.json` the same as `MiniAppID` in the definition.

Keep the title, symbol, destination factory, lifecycle hooks, permissions, backup provider, and optional system integrations together in the definition or its integration layer. Do not add feature-specific switches to the host's list or navigation code.

## 4. Use owner-scoped APIs

`MiniAppContext` supplies identities and storage locations owned by the feature. Use it instead of global names for:

- UserDefaults keys and shared-state keys;
- files and database locations;
- notification requests, categories, and routing payloads;
- URL routes and detail destinations;
- backup, restore, removal, and external-input registrations.

These APIs coordinate cooperating features; they do not sandbox arbitrary Swift code. The feature remains responsible for data validation, schema migration, transactions, and correct native API use.

Add only the contracts your feature needs:

- [Feature lifetime](guides/feature-lifetime.md) for work that survives view changes.
- [Store access coordination](guides/store-access-coordination.md) for writes, restore, and removal.
- [Feature management](guides/feature-management.md), [consent](guides/feature-consent.md), and [data removal](guides/feature-data-removal.md).
- [Owned presentations](guides/feature-owned-presentations.md) and [URL routing](guides/feature-url-routing.md).
- [Database and files](guides/database-files.md), [HTTP](guides/feature-http.md), or [Web storage](guides/web-storage-ownership.md).
- [App Intents](guides/package-app-intents.md), [widgets](guides/package-static-widgets.md), and [incoming files](guides/feature-incoming.md).
- [Quick actions, icon badge, Handoff, TipKit and notification extensions](guides/app-wide-surfaces.md), which iOS gives the app only once.
- [On-device language models](guides/foundation-models.md) with FoundationModels.
- Other Apple system surfaces under [docs/guides](guides/).

A read-only screen does not need dummy lifecycle, backup, or removal providers. Add explicit ownership only for resources and data that exist.

## 5. Keep navigation and app shells separate

The JibunKit host owns the outer `NavigationStack`, the feature list, and the return-to-list action. A feature root view supplies content and may own typed routes or navigation inside its own sheets, but it should not create another host-level stack.

The standalone example app owns its own app shell:

```swift
NavigationStack {
    NotesRootView()
}
```

This keeps the same feature usable independently and inside JibunKit.

The host adds only the leading “Mini Apps” button (「ミニアプリ」 on a device set to Japanese) on the feature root; a long press on it switches to another feature. It places nothing on the bottom edge, so a feature can use `safeAreaInset(edge: .bottom)`, a bottom toolbar, or content that scrolls to the bottom as it would in its standalone app.

## 6. Validate the integration

Run the smallest checks that prove each boundary. These work on any platform with Python 3:

```bash
python3 Tools/jibunkit-feature.py sync --check
python3 Tools/jibunkit-feature.py check Modules/Notes
```

The first confirms that the connection files are current; the second reports code that would change other features' state ([details](#moving-an-existing-app)).

To compile without a Mac, push the branch and run the **Compile check** workflow; compiler errors appear in `gh run view <id>` ([build guide](build.md#compile-check-in-actions)):

```bash
gh workflow run compile-check.yml --ref <branch>
```

On macOS:

```bash
swift test --package-path Modules/Notes
tuist generate --no-open
tuist build JibunKit-App
```

The package-specific test may run on Linux/WSL only if that feature's dependencies are portable; the repository-root `swift test` currently does not. A WSL installation that already has a compatible Darwin Swift SDK may additionally perform an iOS compile-only check, but that is not an IPA build or a generally installed prerequisite; see the build guide. A compile check does not run tests or produce an IPA.

To try the feature on your device, commit it and build an IPA with one command; it prints a link to pass to SideStore or AltStore ([build guide](build.md#build-an-ipa-with-one-command)):

```bash
python3 Tools/build-ipa.py
```

Also verify:

1. The standalone example launches and its important behavior works.
2. The integrated host lists exactly one entry and opens it through its stable ID.
3. Data, notifications, tasks, and native registrations do not collide with another feature.
4. Disabling, deleting, restoring, or failing this feature preserves other owners.
5. Package resources and localization load through `Bundle.module`.
6. Any widget, App Intent, extension, entitlement, or background mode is present in the built product.

Compilation, Simulator behavior, installation, physical-device behavior, and live service behavior are separate results. Record what was actually exercised. See [Build, sign, and install](build.md) and [current status](status.md).

### Your package is also built for macOS

CI runs on macOS. `Tools/test-module-packages.py` runs `swift test` for every `Modules/*` package that declares a test target, and the root `swift test` builds any package that a root `Package.swift` target depends on. `swift test` builds for the machine it runs on, so these builds target macOS even when `platforms` lists only iOS. Code that uses UIKit, MapKit's iOS-only API, or other iOS-only frameworks then fails to compile.

Choose one of these per package:

1. Wrap iOS-only files in `#if os(iOS)` and leave Foundation-only logic ungated, so `swift test` tests that logic on macOS. Add a `.macOS(...)` minimum to `platforms` if that logic needs newer API. This is the fastest option and is what [Records](../Modules/Records/README.md) does. Tests cover only the ungated code.
2. Add `Modules/<Name>/ci-test.sh`. CI runs it with `bash` from the package directory instead of `swift test`, and it and must run all of the package's tests itself, for example with `xcodebuild test` on a Simulator. It can test iOS-only code but is slower, and no published feature uses it yet. A `ci-test.sh` is not a way to skip tests.

Putting `condition: .when(platforms: [.iOS])` on a root `Package.swift` dependency is not used or verified in this repository, and it would not change how the package's own `swift test` builds.

## Importing a feature from another repository

A feature that someone keeps in its own Git repository, in the JibunKit form above (`Package.swift` and `JibunKitFeature.json`), can be copied into your host:

```bash
python3 Tools/jibunkit-feature.py add https://github.com/someone/notes --ref v1.0
python3 Tools/jibunkit-feature.py add https://github.com/someone/apps --path Modules/Notes --name Notes
```

The repository is a Git URL, `OWNER/REPO` for GitHub, or a local directory. `add` fetches the branch, tag or full commit hash given with `--ref` (default: the default branch), copies the directory given with `--path` (default: the repository root) to `Modules/<Name>`, writes the repository, ref, commit and path to `JibunKitImports.json`, and runs `sync`. The copy is what gets built, so a build does not depend on the other repository still existing or keeping its history. `add` and `update` read the repository with Git and copy files; they never run code from it. It refuses symbolic links and submodules.

It then lists what the feature brings, read from its files:

- Swift packages it depends on, and those without an exact version, which can change between builds;
- local packages outside its directory, which the copy does not include;
- precompiled code (`.binaryTarget`), whose source is not in the repository;
- plugins and macros, which run code on the build machine during the build;
- its build requirements (Info.plist keys, entitlements, URL schemes, background modes, App Shortcuts);
- [`check`](#moving-an-existing-app) findings. CI stops on these until they are fixed or allowed.

If `sync` stops because the feature collides with another one, the copy stays so that you can fix it in `Modules/<Name>`; `remove <Name>` undoes the import. Review the files and commit them with `JibunKitImports.json` and the generated helper.

To move to a newer commit, commit your work, then run:

```bash
python3 Tools/jibunkit-feature.py update Notes            # the recorded ref, such as main or v1.0
python3 Tools/jibunkit-feature.py update Notes --ref v1.1 # follow another ref from now on
```

`update` prints the old and new commit and what changed in the list above. It applies the upstream change between the two commits to your copy, so your own edits stay: a file changed on both sides is merged, with Git's conflict markers where the edits overlap (`<<<<<<< yours`); a file that cannot be merged as text keeps your version and gets the upstream one next to it as `<file>.upstream`. It then exits with an error until you resolve them. If the recorded commit has disappeared upstream, `update` stops; run `remove` and `add` again, and reapply your edits from Git history.

`remove Notes` deletes `Modules/Notes` and its record and runs `sync`.

The **Import Feature** workflow (`.github/workflows/import-feature.yml`) runs the same commands on GitHub and commits the result to the branch it runs on, only when the command succeeds. The [Build](../Modules/Builder/README.md#import-features-from-other-repositories) mini app starts it from the phone.

## Moving an existing app

Moving an existing Xcode app into a feature means removing its app shell. Move the code into a package as described above, without the `@main` type, `Info.plist`, entitlements, app icon, and launch screen. Then move each responsibility the shell had:

| In the standalone app | In JibunKit |
| --- | --- |
| `@main App` and its `WindowGroup` | The host. Expose a public root view and one `MiniAppDefinition` instead. |
| Start-up work in the app's `init` or root `.task` | Synchronous native registration in `onHostLaunch`; work that outlives a screen through [Feature lifetime](guides/feature-lifetime.md). Do not start business work just because the host launched. |
| Outer `NavigationStack` | Remove it. The host owns the stack ([section 5](#5-keep-navigation-and-app-shells-separate)). |
| `onOpenURL` and URL types | `resolveIncomingURL` and `appendDestination`, plus URL types in the feature build requirements ([URL routing](guides/feature-url-routing.md)). |
| `preferredColorScheme` | `environment(\.colorScheme, ...)` on the feature subtree ([appearance](guides/feature-appearance.md)). |
| Info.plist keys such as usage descriptions and `LSApplicationQueriesSchemes` | [Feature build requirements](guides/feature-build-requirements.md). |
| `UserDefaults.standard`, its own App Group and files | Owner-scoped keys from `MiniAppContext.storageKey(_:)`, `MiniAppStorage.sharedDefaults()` and the feature's file locations. |
| Widget extension | The host widget extension ([static widgets](guides/package-static-widgets.md)). |
| `ASWebAuthenticationSession` | A runtime-owned [web authentication](guides/web-authentication-ownership.md) connection. |
| `UIApplication.shared.open` | `MiniAppExternalURL.open(_:)` ([URL routing](guides/feature-url-routing.md#opening-another-app)). |

To find code that still assumes it is the only app, run:

```bash
python3 Tools/jibunkit-feature.py check Modules/Notes
```

It reports, with the line and the guide to follow, the standalone-app uses in the table above and a few more that change other features' state: `@main`, `UserDefaults.standard` and `@AppStorage` without a store, hard-coded App Groups, app-wide directories, `UIApplication.shared.open`, `.onOpenURL`, `.preferredColorScheme`, `NavigationStack`, `Tips.configure`, badge counts, `shortcutItems`, the notification delegate, `isIdleTimerDisabled`, `AVAudioSession` changes, `deleteAllSearchableItems`, `ASWebAuthenticationSession` and `BGTaskScheduler` registration. It skips `Example`, `UITests` and `Tests`. It matches text, so it can miss uses and can report an intended one, such as a `NavigationStack` inside the feature's own sheet; mark such a line with `// jibunkit: allow navigation-stack`. Without a path it checks every feature that has a `JibunKitFeature.json`, and CI runs it that way.

Choose the feature ID once and keep it. Renaming the app later changes the display name and type names, not the ID.

Data that the standalone app saved stays in that app's own container. JibunKit cannot read it. Data the user wants to keep needs its own route, such as a server the feature syncs with or an export from the old app followed by an import in the feature.

Code written for Swift 5 can be moved first and adapted to Swift 6 later. The host and the integration use Swift 6, but a package target can set its own language mode:

```swift
.target(name: "NotesFeature", swiftSettings: [.swiftLanguageMode(.v5)])
```

This separates the move from the concurrency rewrite. The Swift 6 integration code may still report concurrency errors where it passes the feature's types between actors. Keep the integration thin. If you use `@preconcurrency import` there, treat it as temporary.

## Compatibility checklist

Before publishing an update, review [Compatibility and stable identities](compatibility.md). In particular, do not casually change:

- feature IDs or storage namespaces;
- bundle IDs or App Groups;
- notification request/category IDs;
- widget kinds, App Intent identities, or URL destinations;
- backup schema versions and payload meaning.

The Records module is a larger reference for files, navigation, notifications, and backup integration. See [Records](../Modules/Records/README.md). Focused system-surface details belong in the individual guides rather than in this entry document.

## Troubleshoot package connections

On macOS, run `python3 Tools/check-feature-connection.py --package Modules/Notes --product NotesFeature`. It evaluates the trusted checkout's Swift and Tuist manifests to check the path, library product, target membership and direct host dependency; `--host` selects a different target such as the widget. It does not prove compilation, transitive integration dependencies or runtime registry contents.

Check the first failing boundary in order:

1. Package not found: run `python3 Tools/jibunkit-feature.py sync` and confirm `Modules/Notes/Package.swift` and `JibunKitFeature.json` exist. For a hand-registered package, correct `Project.swift`'s package path.
2. Product not found: match the package's library product and target names; run `swift package --package-path Modules/Notes describe`, package tests and generation.
3. `No such module`: list the product under `products` (app) or `widget.products` (widget extension) and the integration under `sources`, or for a hand-registered package add the dependency and sources to the exact target; then sync, regenerate and build.
4. No list entry or URL destination: list the definition under `definitions`, or add it once to `MiniAppRegistry.all` for a hand-registered feature; inspect the actual registry IDs with `MiniAppValidator.validate(ids:expectedIDs:)` and exercise `jibunkit://mini-app/notes`.

The expected ID set is a test assertion, not another production registry. Source-text searches alone cannot prove these four connections.
