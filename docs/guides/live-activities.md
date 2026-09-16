# Live Activities integration

JibunKit keeps ActivityKit payloads in the Feature module. Define a concrete
`MiniAppLiveActivityAttributes` type, its business-specific `ContentState`, an
`ActivityConfiguration`, and any `LiveActivityIntent` beside the Feature. Do not
turn delivery state, a match score, or another domain model into a common timer
or untyped payload.

## Coordinator contract

Create one `MiniAppLiveActivityCoordinator<ActivityKitLiveActivityDriver<A>>`
singleton per owner in the **app process**. The Feature supplies:

- its `MiniAppID`, concrete attributes/content types, and current-generation
  admission closure;
- `MiniAppContinuingJournal.shared(owner:namespace:)` for OS bindings outside
  backup business data;
- final Feature content used by management cleanup.

`start` returns a typed `MiniAppLiveActivityDescriptor`. Keep its complete
identity (`owner`, `localID`, `generation`, `registrationID`) and opaque Activity
ID together. `update`, `end`, and Intent delivery reject a stale generation,
replacement registration, wrong owner, or mismatched Activity ID. Two Features
may deliberately use the same `localID`; owner remains part of the key.

The coordinator records `.starting` before `Activity.request`. A request error or
post-request journal failure is not success and the pending row remains available
to cold `reconcile`. ActivityKit `update` and `end` are asynchronous but do not
throw an OS acknowledgement; the adapter observes state for a bounded interval
and reports `nativeStateUnresolved` while retaining retry information.

## Host lifecycle

Expose `coordinator.surface(id:finalContent:)` from the Feature singleton and add
it to the Feature's `MiniAppDefinition.continuingSurfaces` registration when the
host integration is present. The ordering is:

1. launch/resume: `reconcile`, then `open`; never recreate a missing activity;
2. disable/delete: `close` (drains admitted work), `endOwned`, then ordinary
   unregister/removal;
3. restore stop: `close`, `endOwned`, replace business payload; resume reconciles
   and opens without restarting old work;
4. failed-stop recovery opens only when management still permits the owner.

Cleanup deliberately uses the journal and typed ActivityKit enumeration, not
`MiniAppSharedState.read`, because normal state access is closed during
maintenance. It ends only activities whose immutable attributes prove the same
owner. Unknown typed OS rows stay diagnostic during reconcile and are never
assigned to another owner.

The fixture's copy-ready Definition wiring is
`Tests/ContinuingLiveActivities/DefinitionExamples.swift.fixture`. Its A and B
packages use different attributes and owners with the same `same-id`; resetting
A does not modify B.

## Targets and metadata

The app and embedded widget extension both depend on the Feature package. Register
each Feature's `ActivityConfiguration` in the extension `WidgetBundle`, and its
`AppIntentsPackage` in targets where metadata discovery requires it. Put
`LiveActivityIntent` in the app-linked Feature product: the system runs it in the
app process without opening the UI, so it must reach the same singleton.

Set the app Info.plist Boolean `NSSupportsLiveActivities` to `YES`. The provided
local adapter uses `pushType: nil`; it does not implement APNs. JibunKit's journal
and shared business store require the same App Group entitlement/container in the
app and extension. Inspect the final built plist, extension embedding, entitlements,
provisioning, signatures, and App Intents metadata rather than inferring them from
source settings.

## Fixture and verification

`Tests/ContinuingLiveActivities/Project.swift.fixture` builds Standalone A,
Standalone B, and Combined from the same two package sources. Each diagnostic
view displays initial state and the latest start/update/end failure. The widget
extension supplies the Lock Screen/Dynamic Island display and interactive button.

Foundation fake tests verify serialization, duplicate suppression, stale
generation/registration rejection, post-native persistence recovery, bounded
failure, and A cleanup/B retention. They do not prove ActivityKit behavior. Xcode
and device verification must additionally cover request authorization/error,
Lock Screen/Dynamic Island rendering, Intent metadata and routing, force-quit and
cold reconcile, immediate/default end behavior, disable/delete/restore retry, and
B remaining visible and durable after A fails or resets.

## Apple references

- [Activity and its request/update/end/state APIs](https://developer.apple.com/documentation/activitykit/activity)
- [Displaying live data with Live Activities](https://developer.apple.com/documentation/activitykit/displaying-live-data-with-live-activities)
- [ActivityConfiguration](https://developer.apple.com/documentation/widgetkit/activityconfiguration)
- [LiveActivityIntent](https://developer.apple.com/documentation/appintents/liveactivityintent)
- [NSSupportsLiveActivities](https://developer.apple.com/documentation/bundleresources/information-property-list/nssupportsliveactivities)
- [Adding interactivity to widgets and Live Activities](https://developer.apple.com/documentation/widgetkit/adding-interactivity-to-widgets-and-live-activities)
- [Emoji Rangers sample](https://developer.apple.com/documentation/widgetkit/emoji-rangers-supporting-live-activities-interactivity-and-animations)
