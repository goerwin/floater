# Floater

Floater is a native macOS utility that opens AI responses in a draggable floating panel. It accepts requests from a small composer, the `floater` CLI, or the `floater://` URL scheme. Response text is selectable, so you can copy only part of it.

Floater uses Apple Foundation Models on device. It requires macOS 26 or later and a Mac that supports Apple Intelligence, with Apple Intelligence enabled and ready.

## Build and run

```sh
Scripts/build-app.sh
open build/Floater.app
```

Floater runs in the menu bar. Choose **New request** to open the composer. The first launch registers the `floater://` URL scheme with macOS.

## Make targets

Run these from the project directory:

- **make test** runs the Swift test suite.
- **make dev** quits Floater, rebuilds the debug app, and opens the composer. Set `FLOATER_PROMPT`, `FLOATER_INPUT`, and optionally `FLOATER_TITLE` to run a request directly.

```sh
make dev FLOATER_PROMPT="Summarize this text" FLOATER_INPUT="Done. Committed" FLOATER_TITLE="Quick test"
```
- **make install** builds a release app and copies it to /Applications. macOS will ask for administrator access.
- **make release VERSION=0.1.0** builds a versioned DMG and checksum.
- **make release-patch**, **make release-minor**, or **make release-major** previews release notes and asks before pushing a version tag. Pushing the tag starts the GitHub release workflow.

The GitHub release workflow signs the app and needs these repository Actions secrets:

- MAC_BUILD_CERTIFICATE_BASE64
- MAC_BUILD_CERTIFICATE_BASE64_PASSWORD
- MAC_APP_CERTIFICATE

## CLI

Install Floater in `~/Applications` and the CLI in `~/.local/bin`:

```sh
Scripts/install-cli.sh
```

Make sure `~/.local/bin` is on your `PATH`, then call it from a shell or automation workflow:

```sh
floater --prompt "Translate this text to Spanish" --input "Hello, world" --title "Translation"
cat notes.txt | floater --prompt "Summarize this" --input -
```

An automation source can also open a URL directly:

```text
floater://prompt?prompt=Translate%20this%20text&input=hola%20mundo&title=Translation
```

The optional `--title` flag or `title` URL parameter sets the panel heading.

The **Copy** button copies the full response and returns to the previous app. Select any portion of the response and use the normal macOS copy shortcut to copy only that text. **Replace** puts the full response in the clipboard, returns to the previous app, and sends Command-V. macOS Accessibility access is required for Replace; Floater asks for it the first time you use that action.

## Licensing

Source code is available under the MIT License. The Floater name and any original app artwork are reserved and are not covered by that license. This project does not reuse Mic Muter's name, icon, or artwork.
