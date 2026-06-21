# VoiceToText — Development & Release Runbook

Practical order of operations for this fork: **launch → test → release**.

## Fork facts (one-time setup, already done)

- **Repo:** `origin` = `github.com/Darmikon/voice-to-text` (your fork), `upstream` = `github.com/gug007/voice-to-text`.
- **Git author:** `Darmikon <hrizamer.ci@gmail.com>`. Never add Claude/AI co-author trailers to commits or PRs.
- **Apple signing:** team **Roman Yudin `8ACEP9M78U`**, "Developer ID Application" cert (for notarized releases).
- **Bundle IDs:** Release = `voice-to-text-ai.VoiceToText`; Debug = `voice-to-text-ai.VoiceToText.dev` (app name "VoiceToText Dev"). The separate dev id keeps Accessibility/Input-Monitoring grants from colliding with the prod app.
- **GitHub Actions secrets** on the fork (already set): `APPLE_CERTIFICATE_BASE64`, `APPLE_API_KEY_BASE64`, `APPLE_API_KEY_ID`, `APPLE_API_ISSUER_ID`. The Developer ID .p12 has an **empty password**, so `APPLE_CERTIFICATE_PASSWORD` is intentionally unset.
- Actions must be **enabled** on the fork (GitHub → repo → Actions tab → enable). Done once.

---

## 1. Launch (run locally)

The app is a native macOS SwiftUI menu-bar app. No `npm install` — dependencies are Swift packages (WhisperKit, FluidAudio) resolved by Xcode on first build.

**From Xcode (normal dev loop):**
1. `open VoiceToText/VoiceToText.xcodeproj`
2. Make sure the Apple ID for team Roman Yudin is in Xcode → Settings → Accounts.
3. Press **⌘R**. The Debug build runs as **"VoiceToText Dev"**.
4. First run: grant **Accessibility** + **Input Monitoring** to "VoiceToText Dev" (System Settings → Privacy & Security). The grants persist across rebuilds because the dev build is stably signed.

**From the terminal (optional):** `./scripts/dev.sh` builds the Debug app and installs it to `/Applications/VoiceToText-Dev.app`. Override the signer with `VOICE_TO_TEXT_SIGN_ID="..."` if needed.

Default recording shortcut is **⌥Space** (Option+Space). Whatever you set in the dev app is stored in *your* local prefs only, not in the code.

---

## 2. Test

**Unit harnesses (pure logic — fast, no GUI):**
```bash
bash Tests/run-hotkey-harnesses.sh
```
Every harness must print its `… passed` line and the script must exit 0. These cover the hotkey-state policy, the review send/newline policy, the settings store, etc.

**Build check (compiles the whole app, no signing):**
```bash
cd VoiceToText && xcodebuild -project VoiceToText.xcodeproj -scheme VoiceToText \
  -configuration Debug -derivedDataPath build-dev build CODE_SIGNING_ALLOWED=NO
```
Expect `** BUILD SUCCEEDED **`.

**Manual smoke test** (run the dev app, "Review before pasting" ON):
1. Focus a text field. Press the recording shortcut → record → press again → the review form appears.
2. Press the shortcut again → in-form re-record: only the waveform shows; the mic button becomes **Stop + timer**.
   - **Stop** → transcribes and appends to the end; back to the form.
   - **Cancel** → drops the take, prior text intact (no transcription).
   - **Paste** (during recording) → transcribes-so-far, appends, pastes immediately.
3. In the form: **Return** sends, **Shift+Return** = newline.
4. Settings → Shortcut → toggle **"Newline on Enter"** → Return = newline, configured send shortcut (default ⌘Return) sends.
5. Turn **"Review before pasting"** OFF → record → stop → text pastes immediately (recording HUD shows a centred timer + Paste button).

---

## 3. Release (notarized DMG + auto-update)

A pushed `v*` tag triggers `.github/workflows/release.yml`, which builds Release, signs with your Developer ID, notarizes via Apple, and publishes a GitHub Release with the DMG.

1. Get the work onto `main` (open a PR from your feature branch and merge it — direct pushes to `main` are avoided).
2. Sync and tag:
   ```bash
   git checkout main && git pull origin main
   ./scripts/release.sh patch     # patch|minor|major; bumps the latest v* tag
   ```
3. Watch the build:
   ```bash
   gh run watch <run-id> --repo Darmikon/voice-to-text --exit-status
   # or: github.com/Darmikon/voice-to-text/actions
   ```
4. Get the app: **github.com/Darmikon/voice-to-text/releases/latest** → `VoiceToText.dmg`.

**Verify a release is properly signed + notarized:**
```bash
# after mounting the DMG:
spctl -a -vvv -t install "/Volumes/VoiceToText/VoiceToText.app"
# expect: accepted / source=Notarized Developer ID / origin=Developer ID Application: Roman Yudin (8ACEP9M78U)
```

**Changelog:** the GitHub Release body is auto-generated from commits/PRs since the last tag (`generate_release_notes: true`), and the app shows it in the update prompt — so keep commit/PR messages clean.

**Auto-update:** the installed app polls `Darmikon/voice-to-text/releases/latest` once a day (see `AppUpdater.swift`); a higher version tag → it prompts the user to update. Versions are compared as semver against the app's built-in `MARKETING_VERSION` (set from the tag at build time).

---

## Gotchas

- **No notarization without an active paid Apple Developer membership** on team 8ACEP9M78U.
- The fork inherited upstream's tags up to `v0.0.35`; `release.sh` bumps from the latest, so the first fork release was `v0.0.36`.
- If a tag push doesn't start a run, confirm Actions is enabled on the fork, then re-trigger by deleting + re-pushing the tag.
- Released app is ~11 MB (Swift packages are statically linked, models download at runtime) — that's expected, not a broken build.
</content>
