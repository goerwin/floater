# Branding assets

`Resources/FloaterIcon.svg` is the single source of truth for the app and README
icons. It contains the blue floating panel artwork and its star.

The menu bar and panel title use Apple's native `sparkles` SF Symbol. Both read
the name from `FloaterSymbol` so they stay in sync. macOS handles its appearance
and size in the menu bar.

## Regenerate

Requires Python 3, macOS `iconutil`, and `rsvg-convert` (`brew install librsvg`).

```sh
make assets
```

Generated files live in `Resources/Generated` and are checked in. Normal builds
and releases use these files without needing the SVG renderer installed.
After editing the source, regenerate and include the generated changes.

The generator produces:

- `Floater.icns`, containing all ten required macOS icon sizes.
- A 256-pixel README icon.

Every icon size renders directly from the SVG. Intermediate PNG sizes are
created in a temporary directory and removed after packaging the ICNS.

`Scripts/build-app.sh` copies the ICNS into the app bundle.
The app intentionally runs in the menu bar without a Dock icon.
