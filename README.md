# ScreenJot

A tiny macOS menu-bar app for fast screenshots with scribbles and quick GIF recordings.
Native Swift + AppKit, ScreenCaptureKit, no third-party dependencies, no App Store.

## Shortcuts

| Key | Action |
| --- | --- |
| `⌘⇧4` | Start a screenshot |
| `⌘⇧5` | Start a GIF recording |
| `Tab` | Cycle target: **Region** → **Window** → **Full Screen** |
| drag / click | Pick the region, window, or screen |
| `⏎` | Copy result to the clipboard |
| `⇧⏎` | Save As… |
| `esc` | Cancel |
| `⌘Z` / `⇧⌘Z` | Undo / redo a stroke (screenshot editor) |
| `⇧` while dragging | Constrain the region to a square |

**Screenshot flow:** pick an area → the capture appears in place → draw on it with the mouse → `⏎` or `⇧⏎`.

**GIF flow:** pick an area → recording starts immediately (red frame + timer) → `⏎`, the Stop button or `⌘⇧5` again stops it → the GIF previews in place → `⏎` or `⇧⏎`.
Recordings are 15 fps at 1x scale and capped at 30 seconds.

While ScreenJot is running it disables the native `⌘⇧4` / `⌘⇧5` bindings; quitting restores them.
The menu-bar icon has a toggle for this, a Launch-at-Login switch, and a shortcut to the permission pane.

## Requirements

- macOS 14 Sonoma or later
- Screen Recording permission (System Settings › Privacy & Security › Screen & System Audio Recording)

## Install from the DMG

1. Open the DMG and drag **ScreenJot.app** to **Applications**.
2. The build is not notarized, so on first launch right-click the app → **Open** → **Open**, or run:
   ```sh
   xattr -dr com.apple.quarantine /Applications/ScreenJot.app
   ```
3. Grant Screen Recording permission when prompted, then relaunch ScreenJot.

## Build from source

Only the Xcode Command Line Tools are needed (`xcode-select --install`), no Xcode.

```sh
Scripts/build-app.sh      # → build/ScreenJot.app (universal, ad-hoc signed)
Scripts/make-dmg.sh       # → build/ScreenJot-<version>.dmg
swift run -c release ScreenJotSelfTest   # GIF encoder tests
```

To ship a signed and notarized build once you have a Developer ID:

```sh
CODESIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" NOTARY_PROFILE=screenjot Scripts/make-dmg.sh
```

(`NOTARY_PROFILE` is a `notarytool store-credentials` keychain profile.)

## Layout

```
Sources/ScreenJotCore/     GIF pipeline: palette, color mapping, LZW, encoder, movie → GIF
Sources/ScreenJot/         The app
  Capture/                 Selection overlay, ScreenCaptureKit screenshots, state machine
  Editor/                  Drawing canvas and in-place editor window
  Recording/               SCStream → .mov recorder, recording session/HUD, GIF preview
  Export/                  Clipboard + Save panel
  Support/                 Hotkeys, system shortcut override, permissions, prefs, helpers
Sources/ScreenJotSelfTest/ Encoder tests (CLT has no XCTest)
Scripts/                   Icon renderer, app bundle and DMG builders
```

## License

MIT, see `LICENSE`.
