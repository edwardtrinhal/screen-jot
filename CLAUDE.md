# ScreenJot — notes for Claude

Menu-bar macOS screenshot + GIF app. Swift 5 language mode on a Swift 6.x toolchain, AppKit, SwiftPM only.
The dev machine has Command Line Tools but **no Xcode and no XCTest**; never add an XCTest target.

## Commands
- Build app bundle: `Scripts/build-app.sh` (universal, ad-hoc signed → `build/ScreenJot.app`)
- DMG: `Scripts/make-dmg.sh`
- Tests: `swift run -c release ScreenJotSelfTest` (must print `ALL PASSED`)
- Quick compile check: `swift build -c release 2>&1 | grep -E "error:"`
- Run for manual testing: `open build/ScreenJot.app` (TCC permission is tied to the signature; ad-hoc rebuilds may re-prompt)

## Non-negotiable product decisions (agreed with the user)
- `⌘⇧4` screenshot, `⌘⇧5` GIF. The app disables the native bindings (symbolichotkeys 30 and 184) on launch and restores on quit.
- `Tab` cycles Region / Window / Full Screen in both modes.
- `⏎` copy, `⇧⏎` Save As, `esc` cancel, everywhere.
- GIF: 15 fps, 30 s cap, 1x scale, own encoder in `ScreenJotCore` (no deps).
- Distribution is an unsigned DMG; keep signing/notarization behind env vars in the build script.

## Architecture
- `CaptureController` is the single state machine: idle → selecting → capturing/recording → editing/previewing → idle.
- Overlays (`OverlayWindow`, one per screen) are excluded from the SCK content filter, so capture happens *before* they close.
- Coordinates: AppKit global (bottom-left) everywhere; `Geometry.swift` converts to Quartz / SCK display-local.
- Recording writes H.264 to a temp `.mov` (bounded memory), then `MovieToGIF` (in ScreenJotCore, covered by the self-test) does two passes (palette, encode) with real frame timing.
- `GIFEncoder` does inter-frame differencing + transparency and merges identical frames; `LZWEncoder` must keep the clear-flag-before-emit ordering.

## Style
- Commits: plain messages, no Co-Authored-By trailer, commit per coherent change.
- Keep files small and single-purpose; prefer AppKit over SwiftUI for the overlay/editor windows.
