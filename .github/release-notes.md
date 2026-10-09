## What's new

- **Copy text from images (OCR)** — hover an image clip and click the text-scan button, or right-click ▸ *Copy Text from Image*. Press **⌃⇧⌘T** and drag over anything on screen to copy the text in it. On-device Apple Vision, works offline.
- **Keep Awake** — a small switch in the panel stops the Mac sleeping (15 min → 5 h, or until turned off). ⌥-click or right-click the menu bar icon to toggle; the icon turns into a coffee cup while it's on.
- **Notification control** — *Show all*, *Choose apps* or *Hide all* banners, including notifications forwarded from your iPhone. Hidden banners are listed in the panel so nothing is lost.

## Install

1. Download **ClipMate.dmg** below, open it, and drag ClipMate into Applications.
2. The app isn't notarized by Apple, so the first launch is blocked. Open **System Settings ▸ Privacy & Security**, scroll down and click **Open Anyway** next to ClipMate, then confirm.
   *(Or in Terminal: `xattr -dr com.apple.quarantine /Applications/ClipMate.app`)*
3. Notification control needs **Accessibility**: System Settings ▸ Privacy & Security ▸ Accessibility ▸ enable ClipMate. If an older ClipMate is already in that list, remove it (–) and add the new one, since each build has a new signature.

Requires macOS 13 Ventura or later. Universal (Apple silicon + Intel).
