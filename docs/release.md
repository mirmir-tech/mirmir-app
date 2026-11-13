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
   notarization, for a look on this Mac only.
3. Smoke test the stapled DMG on another Mac: open it, drag Mirmir to
   Applications, start it, check that This Mac connects, then add a remote
   server (Instances → Add Server) and open Remote Access.
4. Create the GitHub release `v0.6.0` in `mirmir-tech/mirmir-app` and attach
   `build/release/Mirmir-0.6.0.dmg` and `build/release/Mirmir-macOS.dmg`. The website's
   download button points to
   `https://github.com/mirmir-tech/mirmir-app/releases/latest/download/Mirmir-macOS.dmg`.

The app needs macOS 27 or later on Apple silicon: the bundled MLX is built
for the default deployment target, which keeps the NAX kernels on M5. It is
not sandboxed: it reads mirmir's Unix socket and starts the bundled
`mirmir serve`. Remote API keys are stored in the login Keychain under the
service `tech.mirmir.app.remote-key`.
