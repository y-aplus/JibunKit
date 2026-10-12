# Moving My App into JibunKit

Moved by `python3 Tools/jibunkit-feature.py migrate` from https://github.com/gadirom/Art-in-Swift VerletEngine.swiftpm at fe34d516ccce3615f096bb661e2d7b017694860f (HEAD), Swift Playgrounds app (root).

This Feature is a draft: `sync`, `check` and CI leave it out, so it does not affect builds. When it compiles and `check Modules/Verlet` reports nothing, run `python3 Tools/jibunkit-feature.py connect Verlet`.

Copied 14 Swift file(s) and 0 resource file(s) into `Sources/VerletFeature`; Modules/Verlet has 48 KB.

## Changed

- `MyApp.swift`: the `@main` App is now `public struct VerletRootView: View`, which shows the WindowGroup's content; the host opens it from the MiniAppDefinition.
- Package.swift depends on the app's Swift packages: .package(url: "https://github.com/MetalBuilder/MetalBuilder", "0.2.3"..<"1.0.0"), .package(url: "https://github.com/gadirom/TransformGesture", "0.0.1"..<"1.0.0").
- Package.swift compiles the code in the Swift 5 language mode, as the app did.

## Still to change

Nothing that the checks find.
