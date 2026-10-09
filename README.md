# Floater

A native macOS menu bar app that displays Apple Intelligence responses in a floating window. Requests run on device using Apple Foundation Models.

Requires macOS 26 or later and a Mac with Apple Intelligence enabled and ready.

## Features

- **Floating window:** stays above other apps and can be dragged anywhere.
- **New Request:** write a prompt with optional input text.
- **Results:** copy the full response or a selection, edit your request, and run it again.
- **Replace:** update selected text in the previous app, or the whole field when nothing is selected. Requires Accessibility permission.
- **History:** search and reopen the latest 100 successful results, saved locally.
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

## License

[MIT](LICENSE). The Floater name and original artwork are reserved.
