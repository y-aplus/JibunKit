# Adding a feature

A JibunKit feature is source code compiled into the host at build time. The preferred shape is a Swift package with business logic and a root view, plus a thin integration that creates one `MiniAppDefinition`.

JibunKit does not load arbitrary IPAs or runtime plug-ins. It also does not automatically convert an existing app target: separate reusable feature code from the app shell first.

## 1. Create a standalone feature

On macOS with Tuist 4.207.0:

```bash
tuist scaffold feature --name Notes
tuist generate --path Modules/Notes --no-open
```

Use a valid Swift type name beginning with an uppercase letter. The template creates a Swift package, root view, tests, a small example app, and UI-test scaffolding under `Modules/Notes`. It refuses to overwrite an existing directory.

Develop and test `NotesExample` independently. Keep domain models, persistence rules, validation, and feature-specific native behavior in this package. The feature package does not need to depend on JibunKitCore unless it directly uses its APIs.

## 2. Add the package to the host

In the root `Project.swift`:

1. Add `.package(path: "Modules/Notes")` to `packages`.
2. Add `.package(product: "NotesFeature")` to the `JibunKit-App` target dependencies.
3. Add the dependency separately to a widget or other extension only when that target imports the product.

The package must expose a library product. Do not add the generated example app's `@main` target to the host.

## 3. Define one integration

Create a thin integration next to the feature or in a dedicated integration target:

```swift
import JibunKitCore
import NotesFeature

enum NotesMiniApp {
    static let definition = MiniAppDefinition(
        id: MiniAppID("notes"),
        title: "Notes",
        systemImage: "note.text"
    ) { context in
        NotesRootView(context: context)
    }
}
```

Add `NotesMiniApp.definition` once to `Sources/JibunKit/MiniAppRegistry.swift`.

The ID must begin with a lowercase ASCII letter and contain only lowercase letters, digits, `.`, `-`, and `_`. It becomes part of storage, notification, routing, backup, and system-registration identities. Treat a shipped ID as persistent data: do not rename it without a migration.

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
- Other Apple system surfaces under [docs/guides](guides/).

A read-only screen does not need dummy lifecycle, backup, or removal providers. Add explicit ownership only for resources and data that exist.

## 5. Keep navigation and app shells separate

The JibunKit host owns the outer `NavigationStack`, the feature list, and the return-to-list action. A feature root view supplies content and may own typed routes or navigation inside its own sheets, but it should not create another host-level stack.

The standalone example app owns its own app shell:

```swift
NavigationStack {
    NotesRootView(context: exampleContext)
}
```

This keeps the same feature usable independently and inside JibunKit.

## 6. Validate the integration

Run the smallest checks that prove each boundary:

```bash
swift test
tuist generate --no-open
tuist build JibunKit-App
```

Also verify:

1. The standalone example launches and its important behavior works.
2. The integrated host lists exactly one entry and opens it through its stable ID.
3. Data, notifications, tasks, and native registrations do not collide with another feature.
4. Disabling, deleting, restoring, or failing this feature preserves other owners.
5. Package resources and localization load through `Bundle.module`.
6. Any widget, App Intent, extension, entitlement, or background mode is present in the built product.

Compilation, Simulator behavior, installation, physical-device behavior, and live service behavior are separate results. Record what was actually exercised. See [Build, sign, and install](build.md) and [current status](status.md).

## Compatibility checklist

Before publishing an update, review [Compatibility and stable identities](compatibility.md). In particular, do not casually change:

- feature IDs or storage namespaces;
- bundle IDs or App Groups;
- notification request/category IDs;
- widget kinds, App Intent identities, or URL destinations;
- backup schema versions and payload meaning.

The Records module is a larger reference for files, navigation, notifications, and backup integration. See [Records](../Modules/Records/README.md). Focused system-surface details belong in the individual guides rather than in this entry document.
