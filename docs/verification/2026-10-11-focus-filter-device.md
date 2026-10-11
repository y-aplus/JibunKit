# Focus filter device check

Checked on 2026-10-11 on the owner's iPhone with the "Work" Focus.

## Builds

1. `claude/focus-filter` at `51a43ff`, [run 38075137461](https://github.com/y-aplus/JibunKit/actions/runs/38075137461): the normal host with the Show Mini Apps filter.
2. The check branch `claude/focus-check`, [run 38097775693](https://github.com/y-aplus/JibunKit/actions/runs/38097775693): build 1 plus `90f8cc0` (perform waits for the badge update) and a diagnostic Feature, FocusCheck, that logged each `perform`, each read of `appContext` and each badge update, and scheduled test notifications with `filterCriteria` set to `focuscheck`, `counter` or nothing. Neither the diagnostic Feature nor its log is in main.

## Results

| Item | Result |
| --- | --- |
| The filter in Settings > Focus > Work > Focus Filters | JibunKit offers 「表示するミニアプリ」 with the translated description and the registered mini apps to choose from. |
| `perform` | Called when the Focus turned on from Control Center while JibunKit was open (application state inactive), with the chosen IDs. |
| `appContext` | Read by the system when the filter was saved and again right after `perform`, with the chosen IDs. |
| Mini app list | Showed only the chosen mini apps with the footer. Also correct after the app was quit and the Focus changed meanwhile. |
| Switch menu | Lists the other shown mini apps; with one chosen mini app on screen it shows only "All Mini Apps", as designed. |
| Quick actions | Only the chosen mini apps. |
| Icon badge | Build 1 kept a hidden mini app's count: `perform` returned before the badge update ran. With `90f8cc0` the total became 2 (only the chosen mini app's 2; Reminder's 1 left out). |
| Notification silencing | Not confirmed. All three test notifications showed banners with sound, whether JibunKit was in the Focus's allowed apps or not, and also with the filter turned off. Intelligent Breakthrough & Silencing (「インテリジェントブレークスルーと非通知」) was off. So in this setup the Focus did not silence JibunKit's notifications even without the filter, and the filter's predicate could not be tested. The cause is unknown. |
