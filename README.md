# Floater

Floater is a native macOS utility that opens AI responses in a draggable floating panel. It accepts requests from a small composer, the `floater` CLI, or the `floater://` URL scheme. Response text is selectable, so you can copy only part of it.

Floater uses Apple Foundation Models on device. It requires macOS 26 or later and a Mac that supports Apple Intelligence, with Apple Intelligence enabled and ready.

## Build and run

```sh
Scripts/build-app.sh
open build/Floater.app
```

Floater runs in the menu bar. Choose **New…** to open the composer. The first launch registers the `floater://` URL scheme with macOS.

In Prompt and Input, **Enter** and **Shift+Enter** add a new line, and **Tab** and **Shift+Tab** insert tabs. Use **Command+R**, **Command+Enter**, or **Run** to submit. **Option+Tab** and **Option+Shift+Tab** move between fields and actions. Outside those editors, ordinary Tab and Shift+Tab also move focus. Response actions follow this order: **Copy, Edit, Replace, Dismiss, History, New**; disabled actions are skipped. Focused buttons activate with Enter or Space. **New** or **Command+N** starts an empty request. Button labels show their keyboard shortcuts.

Pass input as plain text through the composer, `FLOATER_INPUT`, CLI, or URL scheme. Floater wraps nonempty input in `<transcript>...</transcript>` when sending it to the model. The editor and history keep the original input text.

Choose **History** in the panel, **History…** in the menu bar, or **Command+H** to search and reopen completed results. Double-click an entry or select it and choose **Open result**. The saved result opens without generating it again; use **Edit** to change the original prompt or input and rerun it. In the response view, **Command+C** copies selected text or activates Copy when nothing is selected, **Command+E** opens Edit, and **Command+Shift+R** activates Replace when available.

The composer, response, and History share one floating window that stays above other apps. In History, **Command+F** focuses search. **Escape** or **Dismiss** returns to the screen that opened History, preserving its draft or response. Dismissing a saved response returns to History with the same search and selection. Copy and successful Replace return directly to the previous app.

Floater keeps the latest 100 successful, nonempty results locally in `~/Library/Application Support/Floater/history.json`, including each prompt, input, response, and date. Failed and canceled requests aren't saved. Delete individual entries or use **Clear history…** to remove all saved history.

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

The **Copy** button copies the full response and returns to the previous app. Select any portion of the response and use the normal macOS copy shortcut to copy only that text. **Replace** uses macOS Accessibility to replace selected text in the previous app's focused editable field. When nothing is selected, it replaces the entire field by default. Toggle **Replace entire text** in the menu bar to require a selection instead. Replace stays disabled until Accessibility access is granted. Choose **Enable Accessibility…** in the menu bar to request access and open the relevant System Settings pane. Once granted, the menu shows a disabled **Accessibility enabled** status. Floater checks permission again when a menu opens or the app or its window gains focus. If a field cannot be edited through Accessibility, the response stays open with an error message.

## Licensing

Source code is available under the MIT License. The Floater name and any original app artwork are reserved and are not covered by that license. This project does not reuse Mic Muter's name, icon, or artwork.
