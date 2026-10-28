# Changelog

## 0.1.2

- Let release.sh bump the version and generate the changelog section
- Add Check for Updates against the latest GitHub release
- Draw the menu-bar icon from the app icon's glyph instead of the scissors symbol

## 0.1.1

- Clicking anywhere outside the screenshot editor or GIF preview now copies the result and dismisses it, same as `⏎`
- After a click-away copy, focus stays in the app you clicked instead of jumping back to the previous one
- Menu-bar icon now matches the app icon
- "Check for Updates…" in the menu; a quiet daily check offers the download when a newer release exists

## 0.1.0

First release.

- `⌘⇧4` screenshots with in-place drawing, undo/redo, copy or Save As
- `⌘⇧5` GIF recordings: 15 fps, 1x scale, 30 s cap, built-in encoder
- `Tab` cycles Region / Window / Full Screen in both modes
- Takes over the native `⌘⇧4` / `⌘⇧5` shortcuts while running, restores them on quit
- Launch at Login toggle and permission status in the menu-bar menu
- Universal binary (Apple Silicon + Intel), macOS 14 or later
