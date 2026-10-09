## What's new

- **Copy text from images (OCR)** — hover an image clip and click the text-scan button, or right-click ▸ *Copy Text from Image*. Press **⌃⇧⌘T** and drag over anything on screen to copy the text in it. On-device Apple Vision, works offline.
- **Keep Awake** — a small switch in the panel stops the Mac sleeping (15 min → 5 h, or until turned off). ⌥-click or right-click the menu bar icon to toggle; the icon turns into a coffee cup while it's on.
- **Notification control** — *Show all*, *Choose apps* or *Hide all* banners, including notifications forwarded from your iPhone. Hidden banners are listed in the panel so nothing is lost.

- **Privacy & Permissions screen** — on first launch ClipMate lists exactly what it keeps and what each permission is for. Permissions are only requested when you first use a feature that needs them, after a plain-language explanation (nothing is requested at launch).

- **Permissions that keep asking are now fixed in-app** — if macOS shows ClipMate switched on but this copy isn't allowed (every update is a new app to macOS), ClipMate says so and offers **Fix Permission** and **Reopen ClipMate** instead of triggering the system prompt over and over.
- **Notification control now works on macOS Tahoe** — pop-up banners were mistaken for the Notification Center sidebar and skipped; fixed. App switches now say *Shown* / *Hidden*, plus **Send test notification** and **Test & copy report** in Settings for troubleshooting.

## Install

1. Download **ClipMate.dmg** below, open it, and drag ClipMate into Applications.
2. **"ClipMate Not Opened — Apple could not verify…"** — this build isn't notarized by Apple (that needs a paid Apple Developer account), so macOS blocks the first launch. It is not a problem with the app. Click **Done**, then open **System Settings ▸ Privacy & Security**, scroll down to *"ClipMate" was blocked…* and click **Open Anyway**, then enter your password. You only do this once.
   *(Or in Terminal: `xattr -dr com.apple.quarantine /Applications/ClipMate.app`)*
3. When you first turn on Notification control, ClipMate explains what it reads and asks for **Accessibility**: System Settings ▸ Privacy & Security ▸ Accessibility ▸ enable ClipMate. If an older ClipMate is already in that list, remove it (–) and add the new one, since each build has a new signature.

Requires macOS 13 Ventura or later. Universal (Apple silicon + Intel).
