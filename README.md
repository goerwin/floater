# Floater

<p align="center">
  <img src="Resources/Generated/readme-icon.png" width="128" alt="Floater icon">
</p>

A native macOS menu bar app that displays Apple Intelligence responses in a floating window. Requests run on device using Apple Foundation Models.

Requires macOS 26 or later and a Mac with Apple Intelligence enabled and ready.

## Features

- **Floating window:** stays above other apps and can be dragged anywhere.
- **New Request:** write a prompt with optional input text.
- **Results:** copy the full response or a selection, edit your request, and run it again.
- **Replace:** paste over selected text in the previous app, or the whole field when nothing is selected. Keeps the result on your clipboard. Requires Accessibility permission.
- **History:** search and reopen the latest 100 successful results, saved locally.
- **Updates:** use **Check for Updates...** in the menu to download and install new versions.
- **Automation:** send requests through the CLI or `floater://` URLs.

## Build and run

```sh
make dev-app
```

Use **New** to start a request, **Open** to return to the current window, and **History** to browse saved results.

## Automation

Install the app and CLI with `Scripts/install-cli.sh`. Add `~/.local/bin` to your `PATH`, then send a request:

```sh
floater --prompt "Translate to Spanish" --input "Hello, world"
```

You can also open a request from another app or workflow:

```text
floater://prompt?prompt=Translate%20to%20Spanish&input=Hello%2C%20world
```

## Releases

Run `make release-patch`, `make release-minor`, or `make release-major` to preview and confirm a version tag push. Keep the working tree clean first. You can also run **Release** from the GitHub Actions tab with a tag.

Pushing a `vMAJOR.MINOR.PATCH` tag publishes `Floater-<version>.dmg`, `Floater-<version>-SHA256SUMS`, and the signed Sparkle `appcast.xml`. Verify the DMG with `shasum -c Floater-<version>-SHA256SUMS`.

GitHub Actions needs the repository secrets `MAC_APP_CERTIFICATE`, `MAC_BUILD_CERTIFICATE_BASE64`, `MAC_BUILD_CERTIFICATE_BASE64_PASSWORD`, and `SPARKLE_PRIVATE_KEY` to publish releases. The Sparkle key must match `SUPublicEDKey` in `Resources/Info.plist`, shared with Key Remapper.

Versions released before the Sparkle updater was added need one manual installation of a newer release to enable in-app updates.

## License

[MIT](LICENSE). The Floater name and original artwork are reserved.
