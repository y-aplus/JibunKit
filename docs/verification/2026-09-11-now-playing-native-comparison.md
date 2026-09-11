# Native Now Playing ownership comparison (2026-09-11)

## Question

Can two Features rely on the standard `MPNowPlayingSession` boundaries for independent players, Now Playing metadata, remote-command targets, and active-session selection, or does the host need an owner coordinator first?

## Standard API boundary

Apple defines `MPNowPlayingSession` as the object for managing Now Playing information and remote commands for multiple players. Each `AVPlayer` may belong to only one session. Each session exposes its own `nowPlayingInfoCenter` and `remoteCommandCenter`, plus `canBecomeActive`, `isActive`, and `becomeActiveIfPossible()` for asking the system to select it.

Manual metadata and automatic publishing are mutually exclusive. The fixture sets `automaticallyPublishesNowPlayingInfo = false` before writing each session's `nowPlayingInfoCenter`.

Remote command block registration returns a target token. Cleanup must call `removeTarget(_:)` on the same session command; broad `removeTarget(nil)` would remove unrelated targets and is not used.

## Native fixture

`NowPlayingOwnershipProbe` constructs two real `AVPlayer` instances and two real `MPNowPlayingSession` instances in the signed generated host. It verifies:

1. each session retains only its own player;
2. the session Now Playing info centers and remote command centers are distinct objects;
3. setting Feature B metadata does not replace Feature A metadata;
4. command registration returns distinct target tokens, and A removes only its token from A's command;
5. removing A's command target preserves both player associations and B's metadata;
6. activation request results and each session's `isActive` state are captured without assuming that native sessions enforce exclusive ownership.

The activation result is intentionally not required to be `true`: eligibility and final system selection remain native policy. The fixture also cannot synthesize a genuine Control Center or accessory command through public API, so it verifies session/target ownership and cleanup but not OS command delivery. Control Center presentation, command dispatch, audio-session arbitration, lock-screen behavior, interruptions, and device-only behavior remain unverified.

In this itemless-player experiment, both sessions reported `isActive == true` after B requested activation. This is not evidence that Control Center sends commands to both Features, nor that two playable sessions need a host coordinator. Actual playback and system command delivery must be compared before deciding whether native selection needs supplementation. JibunKit does not impose a new one-Feature playback restriction from these snapshots.

## Generated-host integration required

The shared workflow/host owner needs to:

1. copy `NowPlayingOwnershipProbe.swift` into `Sources/JibunKit`;
2. copy `NowPlayingOwnershipUITests.swift` into `UITests`;
3. insert `NowPlayingOwnershipProbe.definition` into the temporary `MiniAppRegistry`;
4. run `MigrationUITests/NowPlayingOwnershipUITests/testTwoNativeNowPlayingSessionsKeepFeatureStateIndependent`.

Native CI result is recorded below.

## Apple references

- [`MPNowPlayingSession`](https://developer.apple.com/documentation/mediaplayer/mpnowplayingsession)
- [`MPNowPlayingSession.remoteCommandCenter`](https://developer.apple.com/documentation/mediaplayer/mpnowplayingsession/remotecommandcenter)
- [`MPNowPlayingSession.becomeActiveIfPossible(completion:)`](https://developer.apple.com/documentation/mediaplayer/mpnowplayingsession/becomeactiveifpossible%28completion%3A%29)
- [`MPRemoteCommand`](https://developer.apple.com/documentation/mediaplayer/mpremotecommand)
- [`MPRemoteCommand.removeTarget(_:action:)`](https://developer.apple.com/documentation/mediaplayer/mpremotecommand/removetarget%28_%3Aaction%3A%29)

## Parent integration

The temporary generated host now copies both fixtures and places the probe first in its launcher. The UI result includes both native activation return values and `isActive` snapshots, and XCTest records that label in the log. Production Registry and app sources do not include the probe.

The first native run, [34553746620](https://github.com/y-aplus/JibunKit/actions/runs/34553746620), reached both activation requests: MediaRemote answered A in about 30 ms and B in about 3 ms. It then crashed inside `MPNowPlayingSession.removePlayer(_:)` because the framework attempted to remove an unregistered `currentItem` observer from an itemless `AVPlayer`. The activation wait was not the timeout source; XCTest waited because the app had terminated before publishing its final result.

The comparison intentionally keeps the itemless players so eligibility and activation behavior without playable content remain observable. It removes the unrelated `removePlayer(_:)` mutation and instead verifies that A's command-target cleanup preserves both session/player associations and B's metadata. The fixture separately logs each activation return value, A's `isActive` after its request, and both sessions' `isActive` values after B's request.

Run [34558893997](https://github.com/y-aplus/JibunKit/actions/runs/34558893997) supplied the decisive native observation: `a-request=true a-state-after-a=true b-request=true a-state-after-b=true b-state-after-b=true`. The two session-specific metadata/command boundaries remained independent, but activating B did not make A inactive. The run failed only because the fixture had temporarily treated exclusivity as a standard-API invariant; the finalized fixture records this behavior rather than asserting an API guarantee that does not exist.

Final run [34559851129](https://github.com/y-aplus/JibunKit/actions/runs/34559851129) passed the complete workflow. The native comparison passed in 14.271 seconds with the same observed state (`a-request=true a-state-after-a=true b-request=true a-state-after-b=true b-state-after-b=true`), and the existing mini-app search regression passed in 33.125 seconds.
