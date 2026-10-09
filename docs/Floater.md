# Floater

## Goal

Build a lightweight native macOS utility that can receive prompts from **any automation source**, run them through an AI provider, and display the result in a keyboard-friendly floating panel.

The app should feel like a temporary extension of the current app, not a separate application. The panel is compact and draggable, keeps a fixed width as it grows vertically with the response, and lets users select and copy part of the response.

## Overall Flow

```text
Any source
   │
   ├── Alfred workflow
   ├── Terminal command
   ├── URL scheme
   └── Other automation
   │
   │ prompt + optional input + optional window title
   ▼
Floating App
   │
   ├── Show panel immediately
   │      └── Loading state
   │
   ├── Send prompt to AI provider
   │
   └── Display result
          │
          ├── Copy
          ├── Replace
          └── Dismiss
```

## Input / Integration

The app should be provider- and caller-agnostic.

It should be callable through:

- CLI / Terminal
- Custom URL scheme
- Alfred workflows
- Other automation tools in the future

For example:

```bash
floater --prompt="Translate this text" --input="hola mundo" --title="Translation"
```

or:

```text
floater://prompt?prompt=Translate%20this%20text&input=hola%20mundo&title=Translation
```

Alfred is simply one possible client of the app, not a dependency.
Automation sources can set the panel heading with `--title` or the `title` URL parameter.

## AI Providers

AI execution should be separated from the UI and input layer.

The app should support a provider abstraction, with:

- **Apple Intelligence / Foundation Models as the default provider**
- Additional providers added later, such as OpenAI, Anthropic, Ollama, etc.

The caller should optionally be able to select a provider, while the app has a sensible default.

Conceptually:

```text
Request
   │
   ▼
AI Provider
   ├── Apple Intelligence (default)
   ├── OpenAI
   ├── Anthropic
   └── Other providers
```

## Responsibilities

### Input sources

Responsible for:

- Providing the prompt.
- Providing optional input/context.
- Optionally selecting an AI provider.
- Optionally specifying actions or presentation behavior.

### Floating App

Responsible for:

- Receiving requests.
- Showing the floating panel immediately.
- Running the AI request.
- Showing loading/progress state.
- Displaying the result, ideally streaming it.
- Providing keyboard-first actions.
- Returning focus to the previous application.

### AI Layer

Responsible for:

- Provider abstraction.
- Prompt execution.
- Streaming results where supported.
- Provider-specific configuration.

## MVP Priorities

1. Native floating panel.
2. Generic CLI interface.
3. Custom URL scheme.
4. Apple Intelligence as the default provider.
5. Clean provider abstraction for future providers.
6. Immediate loading state.
7. AI result display.
8. Copy / Replace / Dismiss.
9. Keyboard navigation.
10. Focus restoration.

Keep the first version intentionally small.

The core experience should be:

**Any source -> prompt -> floating panel -> AI result -> action.**

## Native implementation

- Build a native SwiftUI and AppKit menu bar app for macOS 26 or later.
- Use Apple Foundation Models as the default on-device provider.
- Keep provider execution separate from the panel and input handling.
- Provide a CLI command and `floater://` URL scheme for automation.
- Let users drag the panel, select response text, copy the full result, replace text in the previous app, or dismiss the panel.

## Licensing

License source code under MIT. Reserve the Floater name and original app artwork outside the source license. Do not reuse Mic Muter's name, icon, or artwork.
