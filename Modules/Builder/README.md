# Build

A mini app that builds this JibunKit's IPA from the phone. It starts the repository's **Build IPA (quick)** workflow (`.github/workflows/quick-ipa.yml`) through the GitHub API, follows the run, downloads the IPA and hands it to SideStore or AltStore through the share sheet. It never opens GitHub in a browser.

## Set up

1. In JibunKit, open **Build** and enter the repository your JibunKit is built from as `OWNER/REPO` (your own derived repository, not upstream JibunKit unless you build from it) and the branch (default `main`).
2. Tap **Create a Token on GitHub**. It opens GitHub's form for a new fine-grained personal access token with your account as the resource owner, **Actions: Read and write** and **Contents: Read-only** filled in, using GitHub's [URL parameters](https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/managing-your-personal-access-tokens). GitHub cannot pre-select a repository: under **Repository access**, choose **Only select repositories** and that repository. Adjust the expiration if you like, generate the token and copy it.
3. Paste the token into Build and tap **Save**.

To create the token on another device, open `https://github.com/settings/personal-access-tokens/new?name=JibunKit+Build&actions=write&contents=read` and choose the same settings.

The token is kept in the Keychain under this Feature's own service; the repository and the last build in the host's shared defaults under its own key. Deleting the Feature's data in **Manage Mini Apps** removes both, the downloaded IPA and its notification.

## Use

Tap **Build the IPA**. The app may be closed while GitHub builds, which usually takes a few minutes. If you allow it, a notification a few minutes later reminds you to come back; it is sent at the expected time, not when GitHub finishes, so the build may still be running. When the run has finished, tap **Download the IPA**, then **Share the IPA** and choose SideStore or AltStore in the share sheet. If the installer is not listed there, as SideStore was not in the 2026-10-12 device check, choose **Save to Files** and add the IPA with the installer's **+** button.

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
