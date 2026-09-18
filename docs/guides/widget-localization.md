# Widget localization

The normal Counter Widget keeps its stable `JibunKitCounterWidget` kind, timeline provider, deep link, and owner-scoped storage. Only its user-facing copy is localized.

Runtime Widget views and the gallery name and description resolve keys from `Localizable.strings` in the Widget extension target. While WidgetKit runs the extension, `Bundle.main` is the `.appex` bundle, not the containing app bundle. Therefore the production resource glob must include `Sources/JibunKitWidget/Resources/**` in `JibunKitWidget-Extension`; adding these files only to the app target does not localize the Widget.

The native localization test must be hosted by the built app and depend on its Widget extension. It locates the sibling production `.appex` under the host's `PlugIns` directory, verifies its bundle identifier, opens its actual `en.lproj` and `ja.lproj`, and checks every runtime status and gallery key. It deliberately does not inject a fixture bundle into `CounterWidgetCopy`, because that could pass while the shipped extension omitted its resources.

The native bundle test proves packaged strings and lookup inputs. It does not prove that the OS Widget gallery or a home-screen Widget rendered the selected language. Device validation remains separate: inspect the gallery name and description plus the Widget title, unavailable state, and management states after switching between English and Japanese, while retaining the existing value-update and other-owner checks.
