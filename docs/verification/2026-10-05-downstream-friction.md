# Downstream feedback: first camera Feature and the switcher bar

Source: [JibunKitHome friction log](https://github.com/y-aplus/JibunKitHome/blob/c88bef966d49a5b297c0e0f40fdef6aeda15e228/docs-local/friction-log.md) F-021 to F-025, in a private repository, supplied by the owner on 2026-10-05. A derived host added a barcode-scanning Feature, the first published-API Feature to use `MiniAppCaptureOwner` and `MiniAppVisionCaptureAdapter`; its only reference was the diagnostic `Tests/MediaCapture/MediaCaptureProbe.swift`. Device observations are user-supplied and were not reproduced here.

Items were ranked by the coexistence contract in [compatibility.md](../compatibility.md): JibunKit compensates for what integration takes away, and the host should not take away what a standalone app has.

| Item | Assessment | Response |
|---|---|---|
| F-025 switcher bar covers the bottom of every Feature | Host bug from `67cd7f2`; also takes the bottom edge a standalone app owns | Fixed: bar removed, switching moved to a long press on the root back button ([scene navigation](../scene-navigation.md)) |
| F-023 owner stop ends a scan with no callback | API defect: an async wrapper waits forever | Fixed: `ended` always delivered; `scanCode(owner:)` added ([capture](../guides/capture.md)) |
| F-024 prerelease workflow rejects every run | Workflow bug | Fixed: split the checked fields on tabs only |
| F-022 presentation anchor and consent box exist only in the probe | Gap: the guide assumes parts that are not public | Open |
| F-021 code scan confirms only on tap | Missing option; additive | Open |

## Critical assessment

- F-025: `Sources/JibunKit/MiniAppListScreen.swift` attached the bar with `safeAreaInset(edge: .bottom)` outside the `NavigationStack`, and the reported device run showed Feature content ignoring its height. The friction log proposed removing the bar on the premise that per-Feature path retention works without it. That premise was wrong: the bar was the only way to leave a detail screen without popping it, and the URL and Spotlight routing UI tests exercised exactly that. Three options were compared: keep the bar and fix the inset; remove it; or remove it and let Features opt in to a switcher button on detail screens. The host cannot add toolbar items to a Feature's detail screens without reaching into SwiftUI's private navigation controller. The owner chose removal. Switching from a detail now requires going back first. Paths left through URLs, notifications, quick actions, Spotlight or a Feature's own route still resume. An opt-in detail-screen button can be added later without changing existing Features.
- F-023: in `MiniAppCaptureNative.swift`, `end(generation:)` marked the operation as ending from the owner, and `presentationDidEnd` then returned without `result`, `failure` or `ended`. `ended` must not be awaited inside that stop, because Features call `owner.stop()` from it and that joins the stop in progress. It is now scheduled after the stop finishes. Run 37267512608 passed all 30 native media tests on the iOS 26 Simulator, including the new owner-stop and `scanCode` tests and the existing test that starts a new scan right after a stop.
- F-024: `read -r` with the default `IFS` split the workflow name "Build JibunKit IPA" on spaces. The downstream run 37255389602 is the reported failure; the fix was checked locally with the same tab-separated input.
- F-022 and F-021 remain open. F-022 should publish the presentation anchor and a consent source that can be set after initialization, so camera Features stop copying probe code. F-021 should add a confirmation choice to `codeOperation` and `scanCode`, keeping tap confirmation as the default.

The derived host also reported that Home Screen quick actions stopped opening the app until SideStore refreshed its signature; an overwrite install did not help. That points to the installed signing state rather than JibunKit code and is not tracked here.
