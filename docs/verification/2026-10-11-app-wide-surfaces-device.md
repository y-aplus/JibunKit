# App-wide surfaces device check

Checked on 2026-10-11 on the owner's iPhone. These are the 1.1.0 surfaces that no normal Feature uses, plus the scanner entry points added after 1.1.0.

## Build

The branch `claude/device-check-surfaces` added a module Feature, SurfaceCheck, and a second Feature, SurfaceCheck B, to the normal host. Neither is in main. Source `890cce077e93828c81eedf5f87679a738c4d6588`, [run 38062064157](https://github.com/y-aplus/JibunKit/actions/runs/38062064157), IPA attached to the `surface-check-20261011` prerelease. The app was installed over the existing one, which had already allowed notifications with badges.

## Results

| Surface | What was done | Result |
| --- | --- | --- |
| Spotlight item (`MiniAppSpotlightNamespace`, `MiniAppSpotlightRoute`) | Indexed two items, searched from the Home Screen and opened each | Both opened their SurfaceCheck destination. |
| Spotlight item, then `MiniAppExternalURL` | The second item's destination opens Settings as soon as it appears | Moved to Settings, except once, the first time: it stayed on the destination. Not reproduced afterwards. A likely cause is that the first launch after installing took longer than the 5-second activation wait, which then fails with `inactive`; the record of that attempt was lost when the app quit, so this is not confirmed. |
| Spotlight "Search in App" (shown as 「アプリで検索」) | Searched and chose JibunKit's "Search in App" | The choice of SurfaceCheck and SurfaceCheck B appeared, and the chosen Feature received the query. |
| A Feature's own `NSUserActivity` type | Made the activity current, left the app, found it in Spotlight and opened it | Delivered to SurfaceCheck's destination with its `userInfo`. |
| `MiniAppExternalURL.open` | Opened Settings and Safari; also requested Settings after 5 seconds and went to the Home Screen meanwhile | The direct opens worked. The delayed request did not open while JibunKit was in the background, but opened Settings the next time JibunKit became active. This was a defect, fixed in `bfefcfa`: an expired request now fails with `inactive`. |
| `scanCode` | Scanned and tapped a code | Returned the payload. |
| `runDataScanner`: first code, continuous, review | One scanner of each kind | Finished on the first code; collected several codes until swiped down; showed the code over the camera and finished on a tap. |
| Icon badge sum | Set counts in SurfaceCheck and B with a Reminder scheduled, then disabled B in management | The icon showed the sum, and B's share disappeared when it was disabled. |

Not checked: the notification Service and Content extensions. The Service extension runs only for remote notifications, which the free signing used for SideStore cannot receive.
