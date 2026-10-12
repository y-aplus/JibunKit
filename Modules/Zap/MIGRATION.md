# Moving Zap Notes into JibunKit

Moved by `python3 Tools/jibunkit-feature.py migrate` from https://github.com/ZigaoWang/ZapNotesApp (root) at 9af0c6153f56e52e6752a08fa148a0c500aebe5b (HEAD), Xcode project Zap.xcodeproj, target Zap Notes.

This Feature is a draft: `sync`, `check` and CI leave it out, so it does not affect builds. When it compiles and `check Modules/Zap` reports nothing, run `python3 Tools/jibunkit-feature.py connect Zap`.

Copied 30 Swift file(s) and 8 resource file(s) into `Sources/ZapFeature`; Modules/Zap has 307 KB.

## Changed

- `Models/AIManager.swift` lines 150: added `bundle: .module` (asset-lookup).
- `Models/AppearanceManager.swift` lines 25, 26: added `bundle: .module` (localized-string).
- `Models/SharedComponents.swift` lines 112: added `bundle: .module` (localized-text).
- `Views/AboutHelpView.swift` lines 15, 17, 27, 41, 49: added `bundle: .module` (localized-text).
- `Views/AppearanceSettingsView.swift` lines 19, 26, 39, 49, 54, 59, 67, 99, 100, 101, 110: added `bundle: .module` (localized-string).
- `Views/AudioNoteView.swift` lines 21, 25: added `bundle: .module` (localized-text).
- `Views/CommandButtonView.swift` lines 36: added `bundle: .module` (localized-text).
- `Views/HomeView.swift` lines 37: added `bundle: .module` (asset-lookup).
- `Views/HomeView.swift` lines 15, 21, 22, 23, 24, 43, 238, 239, 246, 249, 258, 260, 262, 264, 281, 317, 322: added `bundle: .module` (localized-string).
- `Views/HomeView.swift` lines 201: added `bundle: .module` (localized-text).
- `Views/NoteRowView.swift` lines 196, 206: added `bundle: .module` (localized-text).
- `Views/OnboardingView.swift` lines 47: added `bundle: .module` (asset-lookup).
- `Views/OnboardingView.swift` lines 82, 91, 100, 134, 148, 172: added `bundle: .module` (localized-text).
- `Views/SettingsView.swift` lines 17, 20, 26, 29, 35: added `bundle: .module` (localized-string).
- `Views/TextInputView.swift` lines 47, 85: added `bundle: .module` (localized-text).
- `ZapApp.swift`: the `@main` App is now `public struct ZapRootView: View`, which shows the WindowGroup's content; the host opens it from the MiniAppDefinition.
- Copied 8 resource file(s); Package.swift declares them: Assets.xcassets, Localizable.xcstrings, Preview Content/Preview Assets.xcassets.
- Package.swift compiles the code in the Swift 5 language mode, as the app did.
- Localized Info.plist text (en, zh-Hans) is under `app.localizedInfoPlist` in JibunKitFeature.json.
- Info.plist keys are under `app.infoPlist` in JibunKitFeature.json: NSCameraUsageDescription, NSMicrophoneUsageDescription, NSPhotoLibraryUsageDescription, NSSpeechRecognitionUsageDescription.

## Still to change

- [audio-session] The audio session is shared. Submit the Feature's requirement to the host's audio coordinator. See docs/guides/audio.md
  Sources/ZapFeature/Models/NotesViewModel.swift:172, Sources/ZapFeature/Views/AudioNoteView.swift:118, Sources/ZapFeature/Views/AudioPlayerInlineView.swift:49, Sources/ZapFeature/Views/AudioPlayerInlineView.swift:61, Sources/ZapFeature/Views/AudioPlayerInlineView.swift:62 (+3 more)
- [color-scheme] preferredColorScheme changes the whole presentation, including other Features. Use environment(\.colorScheme, ...) on the Feature's subtree. See docs/guides/feature-appearance.md
  Sources/ZapFeature/Views/CommandButtonView.swift:206, Sources/ZapFeature/Views/CommandButtonView.swift:210, Sources/ZapFeature/Views/ContentView.swift:22
- [documents-directory] App-wide directories are shared with every Feature. Use MiniAppFiles for the Feature's own files. See docs/guides/database-files.md
  Sources/ZapFeature/Models/AIManager.swift:154, Sources/ZapFeature/Models/NotesViewModel.swift:317, Sources/ZapFeature/Models/SharedComponents.swift:98, Sources/ZapFeature/Views/AudioNoteView.swift:62, Sources/ZapFeature/Views/AudioPlayerInlineView.swift:68 (+2 more)
- [main-bundle] Bundle.main is JibunKit's bundle, not the Feature's; use Bundle.module for the Feature's resources. See docs/updating.md
  Sources/ZapFeature/Views/AboutHelpView.swift:19, Sources/ZapFeature/Views/OnboardingView.swift:19, Sources/ZapFeature/Views/PrivacyPolicyView.swift:20, Sources/ZapFeature/Views/TermsOfServiceView.swift:20
- [open-url] Requests made right after a Spotlight or notification launch can be dropped. Use MiniAppExternalURL.open(_:). See docs/guides/feature-url-routing.md#opening-another-app
  Sources/ZapFeature/Views/OnboardingView.swift:199
- [standard-defaults] Every Feature shares the app's standard defaults. Use owner-scoped keys from MiniAppContext.storageKey(_:) or MiniAppStorage.sharedDefaults(). See docs/mini-apps.md#4-use-owner-scoped-apis
  Sources/ZapFeature/Models/AppearanceManager.swift:11, Sources/ZapFeature/Models/AppearanceManager.swift:12, Sources/ZapFeature/Models/AppearanceManager.swift:13, Sources/ZapFeature/Models/NotesViewModel.swift:287, Sources/ZapFeature/Models/NotesViewModel.swift:304 (+2 more)
