# Floater

<p align="center">
  <img src="Resources/Generated/readme-icon.png" width="128" alt="Floater icon">
</p>

A native macOS menu bar app that displays local AI responses in a floating window. Choose Gemma 4 E4B or Apple Intelligence.

Requires macOS 26 or later. Gemma uses llama.cpp; Apple Intelligence requires a supported Mac with Apple Intelligence enabled and ready.

## Features

- **Floating window:** stays above other apps and can be dragged anywhere.
- **New Request:** write one prompt containing your instructions and any text to process.
- **Models:** choose a model from the menu bar. The submenu shows the current model, marks the selected option, and remembers your choice.
- **Results:** preview the response as it streams. Once generation succeeds, copy the full response or a selection, or use Replace. Edit your request to run it again.
- **Replace (Command+S):** paste over selected text in the previous app, or the whole field when nothing is selected. Keeps the result on your clipboard. Requires Accessibility permission.
- **History:** search and reopen the latest 100 successful results, saved locally.
- **Updates:** use **Check for Updates...** in the menu to download and install new versions.
- **Automation:** send requests through the CLI or `floater://` URLs. Skip chosen apps, or read the selected text in the app behind them.

## Build and run

```sh
make dev-app
```

Use **New** to start a request, **Open** to return to the current window, and **History** to browse saved results.

Local builds use a trusted Apple Development certificate when available and otherwise use ad-hoc signing. The build checks certificate revocation because macOS can move apps signed with a revoked certificate to the Trash. To keep Accessibility permission across rebuilds, create a new Apple Development certificate in Xcode if your old one was revoked.

## Models

Gemma 4 E4B is selected by default. Install its runner with Homebrew:

```sh
brew install llama.cpp
```

The first Gemma request downloads Google's official 4-bit E4B model (about 5.2 GB) to the Hugging Face cache. Later requests use the cached model offline. Floater runs `llama-completion` for each request and releases it afterward; no background server stays running. Only the final answer appears in the result.

Open Floater's menu and choose **Gemma 4 E4B → Apple Intelligence** to switch. Switching models applies to the next request, including requests from the CLI and URLs.

## Automation

Install the app and CLI with `Scripts/install-cli.sh`. Add `~/.local/bin` to your `PATH`, then send a request:

```sh
floater --prompt "Translate to Spanish: Hello, world"
```

Use `--prompt -` to read the full prompt from standard input. Floater sends it as written, without adding tags or task instructions. Add any labels or delimiters you want to your prompt.

Repeat `--ignore` with a bundle id to skip that app when choosing where to read and where Replace pastes. Floater remembers the last two other apps, so it can use the one behind an ignored app. Leave Floater running first, or it will not have seen that app.

`--capture-input` appends the selected text, or the whole text when nothing is selected, to your prompt after a blank line. The captured text stays selected, so Replace swaps it. Reading and Replace both need Accessibility permission.

Capture waits for macOS Accessibility notifications instead of fixed delays. The source app must expose its editor text; editors with text accessibility disabled need that mode enabled first.

```sh
floater --prompt "Rewrite this for clarity" --title "Fix Grammar" \
  --ignore com.example.launcher --capture-input
```

You can also open a request from another app or workflow. Repeat `ignore` for each bundle id, and set `capture=1` to read the field:

```text
floater://prompt?prompt=Translate%20to%20Spanish%3A%20Hello%2C%20world
floater://prompt?prompt=Rewrite%20this&ignore=com.example.launcher&capture=1
```

Existing `--input` arguments and URL `input` parameters remain compatible: their text is appended after a blank line, with no tags. Explicit input takes precedence over capture. Older history entries combine their prompt and input in the same way when opened.

## Releases

Run `make release-patch`, `make release-minor`, or `make release-major` to preview and confirm a version tag push. Keep the working tree clean first. You can also run **Release** from the GitHub Actions tab with a tag.

Pushing a `vMAJOR.MINOR.PATCH` tag publishes `Floater-<version>.dmg`, `Floater-<version>-SHA256SUMS`, and the signed Sparkle `appcast.xml`. Verify the DMG with `shasum -c Floater-<version>-SHA256SUMS`.

GitHub Actions needs the repository secrets `MAC_APP_CERTIFICATE`, `MAC_BUILD_CERTIFICATE_BASE64`, `MAC_BUILD_CERTIFICATE_BASE64_PASSWORD`, and `SPARKLE_PRIVATE_KEY` to publish releases. The Sparkle key must match `SUPublicEDKey` in `Resources/Info.plist`, shared with Key Remapper.

## License

[MIT](LICENSE). The Floater name and original artwork are reserved.
