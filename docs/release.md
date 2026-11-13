# Releasing Mirmir for Mac

Mirmir for Mac follows mirmir's version. 0.6.0 needs mirmir 0.6.0: protocol 2
and remote access.

1. Install mirmir 0.6.0 (`cargo install mirmir --version 0.6.0 --locked`)
   and check `mirmir --version`.
2. On a Mac with a Developer ID Application certificate, from a clean checkout
   of the release commit:

   ```bash
   MIRMIR_SIGN_IDENTITY="Developer ID Application: … (TEAMID)" \
   MIRMIR_NOTARY_PROFILE=mirmir-notary \
   scripts/release.sh
   ```

   The script runs the tests, builds the release bundle, signs it with the
   hardened runtime, builds a DMG, notarizes and staples it.
3. Smoke test the stapled DMG on another Mac: open it, drag Mirmir to
   Applications, start it, check that This Mac connects, then add a remote
   server (Instances → Add Server) and open Remote Access.
4. Create the GitHub release `v0.6.0` in `mirmir-tech/mirmir-app` and attach
   `build/Mirmir-0.6.0.dmg` and `build/Mirmir-macOS.dmg`. The website's
   download button points to
   `https://github.com/mirmir-tech/mirmir-app/releases/latest/download/Mirmir-macOS.dmg`.

The app is not sandboxed: it reads mirmir's Unix socket and starts
`mirmir serve`. Remote API keys are stored in the login Keychain under the
service `tech.mirmir.app.remote-key`.

Bundling mirmir with `scripts/bundle.sh --helper` is for local testing only.
mirmir links `libmlx.dylib` dynamically, so a distributable helper would also
need the MLX library and its Metal library inside the bundle.
