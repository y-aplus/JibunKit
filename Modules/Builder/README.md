# Build

A mini app that builds this JibunKit's IPA from the phone. It starts the repository's **Build IPA (quick)** workflow (`.github/workflows/quick-ipa.yml`) through the GitHub API, follows the run, downloads the IPA and hands it to SideStore or AltStore through the share sheet. It never opens GitHub in a browser.

## Set up

1. In JibunKit, open **Build** and enter the repository your JibunKit is built from as `OWNER/REPO` (your own derived repository, not upstream JibunKit unless you build from it) and the branch (default `main`).
2. Tap **Create a Token on GitHub**. It opens GitHub's form for a new fine-grained personal access token with your account as the resource owner, **Actions: Read and write** and **Contents: Read-only** filled in, using GitHub's [URL parameters](https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/managing-your-personal-access-tokens). GitHub cannot pre-select a repository: under **Repository access**, choose **Only select repositories** and that repository. Adjust the expiration if you like, generate the token and copy it.
3. Paste the token into Build and tap **Save**.

To create the token on another device, open `https://github.com/settings/personal-access-tokens/new?name=JibunKit+Build&actions=write&contents=read` and choose the same settings.

The token is kept in the Keychain under this Feature's own service; the repository and the last build in the host's shared defaults under its own key. Deleting the Feature's data in **Manage Mini Apps** removes both, the downloaded IPA and its notification.

## Use

Tap **Build the IPA**. The app may be closed while GitHub builds, which usually takes a few minutes. If you allow it, a notification a few minutes later reminds you to come back; it is sent at the expected time, not when GitHub finishes, so the build may still be running. When the run has finished, tap **Download the IPA**, then **Share the IPA** and choose SideStore or AltStore in the share sheet. In the 2026-10-12 device check SideStore was listed but tapping it did nothing; choosing **Save to Files** and adding the IPA with SideStore's **+** button installed it.

The quick build runs no tests. A failed run shows a link to its page on GitHub.

## Import Features from other repositories

Under **Features from Other Repositories**, tap **Import a Feature** and enter the repository (`OWNER/REPO` means GitHub, or a full Git URL) and, if needed, a branch, tag or commit, the Feature's directory in the repository and a name under `Modules/`. Builder starts the repository's **Import Feature** workflow (`.github/workflows/import-feature.yml`). It runs `python3 Tools/jibunkit-feature.py add` on GitHub, which copies the Feature, records the commit in `JibunKitImports.json` and connects it, and commits the result to the branch set below; this takes about a minute, and Builder follows it while the screen is open. When it has finished, open **Report** to see what the Feature brings: its Swift packages, precompiled code, code that runs during the build, build requirements and `check` findings ([details](../../docs/mini-apps.md#importing-a-feature-from-another-repository)). Then build the IPA as above.

The imported Features are listed from the branch's `JibunKitImports.json`. Tap one to **Update** it to the newest commit of its recorded branch or tag, or to **Remove** it. To delete the data a Feature saved on the phone, do that in **Manage Mini Apps** before installing a build without it.

When the tool stops, for example because the Feature collides with another one or an update conflicts with your own edits, nothing is committed and the report says why. Resolve it on a computer with the same tool. The import never runs code from the other repository; that code runs when you build.

To see what a repository that is not a JibunKit Feature yet, such as an ordinary iOS app, would need to become one, enter it in the same form and tap **Check Compatibility**. Builder starts the **Check Compatibility** workflow (`.github/workflows/check-compatibility.yml`), which runs `python3 Tools/jibunkit-feature.py inspect` and commits nothing. Its **Report** gives a verdict and lists what cannot come into JibunKit, what needs manual or mechanical changes, and what may not work with free signing ([details](../../docs/mini-apps.md#checking-a-repository-first)).

To move such an app in, also enter a name under `Modules/` and tap **Migrate the App**. The **Migrate App** workflow runs `python3 Tools/jibunkit-feature.py migrate`, commits the result to the branch as a draft, which does not change builds, and compiles it; this takes about ten minutes. The **Report** shows what changed, what is still to change and the compile errors. Drafts are listed under the imported Features: **Connect** starts the **Connect Draft** workflow, which compiles the app with the draft and connects it only when that passes and `check` reports nothing; **Open the Report on GitHub** shows its `MIGRATION.md`; **Remove** deletes it ([details](../../docs/mini-apps.md#moving-an-app-in-with-migrate)).


## Boundaries

- The token can start workflows in the selected repository. Anyone who can use the unlocked phone can use it through this Feature.
- The build attaches the IPA to a `build-RUN_ID` prerelease. The workflow keeps the five newest `build-` prereleases and deletes older ones, so download an IPA you want to keep.
- Builder needs no capability, entitlement or background mode. It follows a build only while it is open.
- The Import Feature, Migrate App and Connect Draft workflows can push to the branch they run on. Starting them needs the same token permissions as a build. Code from another repository is compiled only in read-only jobs.

## Develop

The GitHub client, build tracking and string tables are portable and tested on Linux and macOS:

```bash
swift test --package-path Modules/Builder
```

The example app keeps its settings in memory only: `tuist generate --path Modules/Builder --no-open` on macOS.
