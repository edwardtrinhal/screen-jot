# ScreenJot

A tiny macOS menu-bar app for fast screenshots with scribbles and quick GIF recordings.
Native Swift + AppKit, ScreenCaptureKit, no third-party dependencies, no App Store.

**[Download the latest DMG](https://github.com/edwardtrinhal/screen-jot/releases/latest/download/ScreenJot.dmg)** · [website](https://edwardtrinhal.github.io/screen-jot/) · [all releases](https://github.com/edwardtrinhal/screen-jot/releases)

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
| click elsewhere | Copy to the clipboard and dismiss (same as `⏎`) |
| `⌘Z` / `⇧⌘Z` | Undo / redo a stroke (screenshot editor) |
| `⇧` while dragging | Constrain the region to a square |

**Screenshot flow:** pick an area → the capture appears in place → draw on it with the mouse → `⏎` or `⇧⏎`.

**GIF flow:** pick an area → recording starts immediately (red frame + timer) → `⏎`, the Stop button or `⌘⇧5` again stops it → the GIF previews in place → `⏎` or `⇧⏎`.
Recordings are 15 fps at 1x scale and capped at 30 seconds.

While ScreenJot is running it disables the native `⌘⇧4` / `⌘⇧5` bindings; quitting restores them.
The menu-bar icon has a toggle for this, a Launch-at-Login switch, a shortcut to the permission pane,
and **Check for Updates…**, which compares the running version with the latest GitHub release and offers the DMG.
There is no auto-install: quit ScreenJot and drag the new app over the old one.

## Requirements

- macOS 14 Sonoma or later
- Screen Recording permission (System Settings › Privacy & Security › Screen & System Audio Recording)

## Install from the DMG

1. Open the DMG and drag **ScreenJot.app** to **Applications**.
2. The build is not notarized, so macOS blocks the first launch. Open the app once, then go to
   **System Settings › Privacy & Security**, scroll down and click **Open Anyway**. Or skip the dialog with:
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

The build script signs with a self-signed "ScreenJot Dev Signing" certificate that `Scripts/dev-cert.sh`
creates on first use in its own keychain (`~/Library/Keychains/screenjot-dev.keychain-db`). This keeps the
app's code identity stable, so macOS remembers the Screen Recording grant across rebuilds. Set
`CODESIGN_IDENTITY=-` for a plain ad-hoc signature instead (the permission is then re-asked after every build).

If macOS keeps asking for Screen Recording although the toggle is on, the saved grant belongs to a build
with a different signature. Reset it and grant again:

```sh
tccutil reset ScreenCapture app.screenjot.ScreenJot
```

To ship a signed and notarized build once you have a Developer ID:

```sh
CODESIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" NOTARY_PROFILE=screenjot Scripts/make-dmg.sh
```

(`NOTARY_PROFILE` is a `notarytool store-credentials` keychain profile.)

## Releasing

```sh
Scripts/release.sh patch     # 0.1.1 → 0.1.2; also minor, major, or an explicit X.Y.Z
Scripts/release.sh           # release whatever VERSION already says
```

With a bump argument the script writes `VERSION`, adds a `## <version>` section to `CHANGELOG.md` made from
the commit subjects since the last tag, and commits. Edit `CHANGELOG.md` first if you want hand-written notes
(then run it without an argument). Either way it then builds the DMG, tags `v<version>`, pushes, and creates a
GitHub release with the DMG attached as `ScreenJot.dmg` (so `releases/latest/download/ScreenJot.dmg` always
points at the newest build) plus the versioned file. The landing page in `docs/` and the in-app update check
both follow that latest release.

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
Scripts/                   Icon renderer, app bundle and DMG builders, release script
docs/                      Landing page (GitHub Pages)
```

## License

MIT, see `LICENSE`.
