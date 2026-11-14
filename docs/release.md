# Releasing Mirmir for Mac

Mirmir for Mac follows mirmir's version and contains it: the release embeds
mirmir and MLX built from the surrounding Workmir checkout.

1. Check out the release commit of every Workmir child (`mirmir` 0.6.0 and
   the MLX pinned in `scripts/mlx/version.env`); the build installs MLX if
   `.native/mlx` does not point at that release.
2. On a Mac with the Developer ID Application certificate of team
   `5AH2Q9L8R2`, create the notarytool profile once:

   ```bash
   xcrun notarytool store-credentials mirmir-notary \
       --apple-id you@example.com --team-id 5AH2Q9L8R2 --password <app-specific>
   ```

   Then, from a clean checkout of the release commit:

   ```bash
   scripts/release.sh
   ```

   The script runs the tests, builds the Release app signed with Developer
   ID (hardened runtime, secure timestamp, no `get-task-allow`), draws the disk
   image background (`scripts/dmg/background.swift`, 1x and 2x in one TIFF),
   lays out the window through Finder (the first run asks to let the terminal
   control Finder), signs the DMG, notarizes and staples it. It writes
   `build/release/Mirmir-<version>.dmg` and `build/release/Mirmir-macOS.dmg`.
   `scripts/release.sh --skip-notarize` builds the same image without
   notarization, for a look on this Mac only. Both editions check the
   entitlements with `scripts/release/check-sandbox.sh`: the app sandboxed, the
   helper with only `app-sandbox` and `inherit`, no `get-task-allow`.
3. Smoke test the stapled DMG on another Mac: open it, drag Mirmir to
   Applications, start it, check that This Mac connects and
   `curl http://127.0.0.1:18080/v1/models` answers, grant a Hugging Face cache
   in Settings → Model folders and check that its models are listed, then add
   a remote server (Instances → Add Server) and open Remote Access.
4. Create the GitHub release `v0.6.0` in `mirmir-tech/mirmir-app` and attach
   `build/release/Mirmir-0.6.0.dmg` and `build/release/Mirmir-macOS.dmg`. The website's
   download button points to
   `https://github.com/mirmir-tech/mirmir-app/releases/latest/download/Mirmir-macOS.dmg`.

## Mac App Store

```bash
scripts/release.sh --app-store            # build/release/Mirmir-<version>.pkg
scripts/release.sh --app-store --upload   # and send it to App Store Connect
```

It archives the Release app signed with Apple Distribution and the Mac App
Store provisioning profile (embedded), checks the sandbox, and packages it
with `productbuild`, signed with the Mac Installer Distribution certificate.
`--upload` validates and uploads it with `altool` and an App Store Connect API
key (`MIRMIR_ASC_KEY_ID`, `MIRMIR_ASC_ISSUER`, the `.p8` in
`~/.appstoreconnect/private_keys`). It stops with what is missing. Once, in
the developer account of team `5AH2Q9L8R2`:

1. create the **Apple Distribution** and **Mac Installer Distribution**
   certificates (Xcode → Settings → Accounts → Manage Certificates);
2. register the App ID `tech.mirmir.app` and create a **Mac App Store**
   provisioning profile for it named `Mirmir Mac App Store` (or set
   `MIRMIR_APPSTORE_PROFILE`), then double-click it to install it;
3. create the app record in App Store Connect with the bundle ID
   `tech.mirmir.app`; the app declares no non-exempt encryption.

## Notes

The app needs macOS 27 or later on Apple silicon: the bundled MLX is built
for the default deployment target, which keeps the NAX kernels on M5. Both
editions are sandboxed (`Resources/Mirmir.entitlements`); the bundled
`mirmir serve` inherits the sandbox and keeps its state in the app's
container, apart from the CLI's. Remote API keys are stored in the login
Keychain under the service `tech.mirmir.app.remote-key`.
