ScreenJot — first launch
========================

1. Drag ScreenJot.app into the Applications folder.

2. This build is not notarized by Apple, so the first launch needs one extra step.
   Either:  right-click ScreenJot.app → Open → Open
   or run in Terminal:
       xattr -dr com.apple.quarantine /Applications/ScreenJot.app

3. On first launch macOS asks for Screen Recording permission.
   Enable ScreenJot in System Settings › Privacy & Security › Screen & System Audio Recording,
   then relaunch ScreenJot (menu bar icon › Quit, open it again).

Shortcuts
---------
  ⌘⇧4   Screenshot          ⌘⇧5   Record GIF
  Tab   Region / Window / Full Screen       esc   Cancel
  ⏎     Copy to clipboard   ⇧⏎   Save As…
  ⌘Z    Undo drawing (screenshots)

While ScreenJot runs it takes over ⌘⇧4 and ⌘⇧5 from macOS. Quitting ScreenJot
restores the native shortcuts. You can also toggle this from the menu bar icon.
