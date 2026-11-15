# Mac App Store submission

Everything App Store Connect asks for, kept next to the app. The layout of
`metadata/` follows fastlane `deliver` (`fastlane deliver --metadata_path
appstore/metadata`), but every file can also be pasted by hand.

```
appstore/
  metadata/<locale>/        name, subtitle, description, keywords, promo text, URLs
  metadata/review_information/notes.txt   App Review notes
  screenshots/compose.py    builds out/<locale>/*.png (2880x1800) from raw/ + captions.json
  privacy-policy.md         text for https://mirmir.tech/privacy
  PrivacyInfo.xcprivacy     the app's privacy manifest, to add to the target
```

Locales: `en-US` (primary) and `pl`.

## Readiness review (0.6.0, 14 Nov 2026)

### Already in order

- App and helper sandboxed; the helper carries only `app-sandbox` and
  `inherit`; no `get-task-allow` (`scripts/release/check-sandbox.sh`).
- arm64 only, macOS 27, hardened runtime, `LSApplicationCategoryType`
  developer tools, `NSLocalNetworkUsageDescription` present.
- Guideline 2.4.5: no own updater, no login item, nothing installed outside
  the bundle, no root, the helper runs from `Contents/Helpers`.
- Guideline 2.5.2: downloads are model weights (data); no executable code is
  downloaded.
- The main window opens on launch, so the reviewer is not left with only a
  menu bar icon.
- `scripts/release.sh --app-store [--upload]` archives, signs with Apple
  Distribution, embeds the profile and builds the signed `.pkg`.

### Must be settled before submitting

1. **Export compliance.** `Info.plist` declares
   `ITSAppUsesNonExemptEncryption = false`, but the bundle contains its own
   implementations of standard algorithms: BoringSSL (swift-nio-ssl,
   swift-crypto) in the app and rustls with aws-lc-rs in the helper (TLS for
   remote servers, Remote Access and Hugging Face downloads). Apple treats
   "an industry standard algorithm, not provided within the Apple operating
   system" as needing the French encryption declaration for distribution in
   France.
   **Decided (14 Nov 2026):** France is left out of Availability. The App
   Encryption Documentation questionnaire was answered (standard algorithms
   beyond the OS, not available in France) and App Store Connect replied that
   no documents are needed and that `ITSAppUsesNonExemptEncryption = false`
   may stay. Before adding France: file the French declaration with ANSSI,
   upload it, set the key to `true` and add `ITSEncryptionExportComplianceCode`.
2. **Privacy policy URL.** `https://mirmir.tech/privacy` does not exist yet.
   Publish `privacy-policy.md` there (or on docs.mirmir.tech and change
   `metadata/*/privacy_url.txt`).
3. **One-time account setup** from `docs/release.md`: Apple Distribution and
   Mac Installer Distribution certificates, the `Mirmir Mac App Store`
   profile, the app record for `tech.mirmir.app`, an App Store Connect API
   key for `--upload`.
4. **App name.** `MiRMiR – LLM Runtime` must be free in App Store Connect;
   names are unique store-wide.

### Should be fixed (not blocking, cheap)

- Done (14 Nov 2026): Configuration (Cmd-7) edits the current server's
  configuration (Hugging Face token, HTTP API key, server and runtime
  settings) through `GetConfiguration`/`UpdateConfiguration`; the gated-model
  tooltip points there; "1 instances" is singular. `Resources/PrivacyInfo.xcprivacy`
  is in the target, and the copyright line reads `© 2026 Bazyli Zygan`.
- Recapture screenshots from the App Store build: the Instances capture shows
  the CLI socket `~/.local/state/mirmir/mirmir.sock`, so it is not the
  sandboxed app. A Models screen and a listed remote server would also help.
- Run `xcrun altool --validate-app` before the first upload; it catches
  problems with the SwiftPM resource bundles and the embedded dylibs
  (`libjaccl.dylib`) early.

### App Store Connect answers

| Field | Answer |
|:---|:---|
| Category | Developer Tools; secondary Productivity |
| Price | Free |
| App Privacy | Data Not Collected |
| Third-party content | Yes: the app downloads models the user picks from Hugging Face |
| Age rating | Answer honestly that the app is a general-purpose AI chat with no content filter and user-chosen models; expect 18+ |
| Sign-in for review | Not required |
| Encryption | see "Export compliance" above |
| Copyright | `metadata/copyright.txt` (check the legal name) |

From 16 Nov 2026 the age rating questionnaire has new items (dating and
relationships, shared location; required by 12 Jan 2027); MiRMiR answers "no" to both.

## Screenshots

```bash
cd appstore/screenshots
python3 compose.py          # all locales
python3 compose.py pl       # one
```

Raw captures go to `raw/` (`overview`, `chat`, `panel`, `instances`, as
`.png` or `.webp`). Take the main window at its default 1280x800 points on a
Retina display with Cmd-Shift-4, Space, Option-click (no shadow); the panel
the same way. Captions live in `captions.json`. Output: 2880x1800 PNG, the
size App Store Connect accepts for Mac. Fonts: Space Grotesk and Inter (OFL),
static instances built from the website's variable fonts.

## Character limits

name 30 · subtitle 30 · promotional text 170 · keywords 100 · description
4000. Keywords avoid trademarks (model and company names) and words already in the name or subtitle, which Apple indexes anyway.
