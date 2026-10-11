# Build

A mini app that builds this JibunKit's IPA from the phone. It starts the repository's **Build IPA (quick)** workflow (`.github/workflows/quick-ipa.yml`) through the GitHub API, follows the run, downloads the IPA and hands it to SideStore or AltStore through the share sheet. It never opens GitHub in a browser.

## Set up

1. On GitHub, create a fine-grained personal access token (Settings → Developer settings → Personal access tokens → Fine-grained tokens):
   - Repository access: **Only select repositories**, the repository JibunKit is built from.
   - Permissions: **Actions: Read and write**, **Contents: Read-only**.
   - Choose an expiration you are comfortable with; enter a new token when it expires.
2. In JibunKit, open **Build**, enter the repository as `OWNER/REPO`, the branch (default `main`) and the token, and tap **Save**.

The token is kept in the Keychain under this Feature's own service; the repository and the last build in the host's shared defaults under its own key. Deleting the Feature's data in **Manage Mini Apps** removes both, the downloaded IPA and its notification.

## Use

Tap **Build the IPA**. The app may be closed while GitHub builds, which usually takes a few minutes. If you allow it, a notification a few minutes later reminds you to come back; it is sent at the expected time, not when GitHub finishes, so the build may still be running. When the run has finished, tap **Download the IPA**, then **Send to SideStore or AltStore** and choose the installer in the share sheet.

The quick build runs no tests. A failed run shows a link to its page on GitHub.

## Boundaries

- The token can start workflows in the selected repository. Anyone who can use the unlocked phone can use it through this Feature.
- The build attaches the IPA to a `build-RUN_ID` prerelease; this Feature does not delete old prereleases.
- Builder needs no capability, entitlement or background mode. It follows a build only while it is open.

## Develop

The GitHub client, build tracking and string tables are portable and tested on Linux and macOS:

```bash
swift test --package-path Modules/Builder
```

The example app keeps its settings in memory only: `tuist generate --path Modules/Builder --no-open` on macOS.
