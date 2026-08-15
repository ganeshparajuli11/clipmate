# ClipMate

A tiny macOS menu bar app for the things you paste all day: pinned texts, recent clips, and a one-key area screenshot.

<!-- Repo description suggestion:
     "A lightweight macOS menu bar app for pinned texts, clipboard history, and quick screenshots."
     Suggested topics: macos, menubar, swift, swiftui, appkit, clipboard,
                       clipboard-manager, productivity, menu-bar-app, screenshot
-->

## Features

- **Pinned texts** — up to four. Your email, your phone number, that boilerplate reply. Click to copy, with a brief in-row `Copied ✓`.
- **Clipboard history** — the last 6 clips (configurable, 3–12), newest first. Fills automatically as you copy; click any entry to put it back on the clipboard.
- **Catches cuts too** — ClipMate watches the pasteboard, so ⌘X is captured exactly like ⌘C, from any app.
- **Pin from the panel** — one click on a clip's pin button files it into the first free slot. Click again to un-pin. No slot picker, no trip to Settings.
- **Starts completely empty** — no sample pins, no fake clips. Nothing appears until you actually copy something.
- **Screenshot** — drag-select any region. Save a timestamped PNG to the Desktop, or copy it straight to the clipboard with no file written at all.
- **Ask once, then remember** — optionally have ClipMate ask Copy-or-Save the first time, then silently reuse your answer forever.
- **Two global hotkeys** — show/hide the panel (⌘2 by default) and take a screenshot without opening the panel first (⌘F1). Both re-recordable.
- **Launch at login** — one toggle.
- **Text only** — images and files on the clipboard are ignored rather than stored, which keeps memory flat.

## Screenshots

> _TODO: add screenshots here._
>
> - `docs/panel.png` — the panel open in the menu bar
> - `docs/settings.png` — the Settings window

## Install

### Build from source

1. Install **Xcode** from the Mac App Store (free).
2. Open `ClipMate.xcodeproj`.
3. Let Xcode resolve the `KeyboardShortcuts` package (it does this on its own).
4. Press **⌘R**. The icon appears in your menu bar.

To keep it around permanently:

5. **Product ▸ Archive ▸ Distribute App ▸ Copy App**, then drag `ClipMate.app` into `/Applications`.
6. Open Settings from the panel's gear button, add your pins, and turn on **Launch at login**.

From then on it just runs — no Xcode, no terminal.

### Gatekeeper

A locally built app isn't signed with a paid Apple Developer certificate, so the first time you open it from `/Applications` macOS may refuse. **Right-click the app ▸ Open**, then confirm — or approve it in **System Settings ▸ Privacy & Security**. You only do this once. Proper signing and notarization need a paid Apple Developer account and are out of scope.

## Using it

**Pins** can be typed into Settings — four fields, `Pin 1` through `Pin 4`, filled in any order — or created straight from the panel by clicking the pin button on any recent clip, which drops it into the first free slot. Clicking a filled pin button un-pins. There is no "choose a slot" dialog anywhere in the app. Empty slots are never shown, and set pins collapse upward with no gaps. Edits save to `UserDefaults` immediately, so quitting, relaunching, or updating never loses them.

**Clipboard history** starts empty and fills as you use the machine. Set the cap (3–12) in Settings, or clear it there or from the panel's `Clear` button. Pins are never touched by clearing history.

**Screenshots** default to whichever radio option is selected. Turn on *Ask me the first time, then remember my choice* and the next capture shows a small Copy / Save prompt; after you answer, ClipMate never asks again. Change the remembered answer any time by picking a different radio, or flip the toggle off and on to be asked once more.

**Both hotkeys** are recorded in Settings and apply the moment you set them.

## Permissions

ClipMate is built to ask for as little as possible.

| Permission | Needed? | Why |
|---|---|---|
| **Accessibility** | ❌ No | Both hotkeys use Carbon's hotkey API, which doesn't require it. |
| **Notifications** | ❌ No | Confirmations appear inside the panel instead. |
| **Full Disk Access** | ❌ No | Nothing is read outside the app's own preferences. |
| **Screen Recording** | ⚠️ Once | Only the first time you take a screenshot. macOS shows the prompt itself; ClipMate never asks up front. |

Nothing ever leaves your machine — there is no network code in this app at all.

## How it works

- **Storage** is `UserDefaults`, a handful of keys: `clipmate.pins`, `clipmate.history`, `clipmate.historySize`, `clipmate.screenshotToClipboard`, `clipmate.screenshotAskFirst`, `clipmate.screenshotChoiceRemembered`.
- **Capture** polls `NSPasteboard.changeCount` once a second — a single integer comparison; the pasteboard is only read when something actually changed. Watching the pasteboard rather than keystrokes is what makes ⌘X work for free, and is why no Accessibility permission is needed.
- **History is de-duplicated** — re-copying an old clip promotes it to the top instead of adding a second row.
- **Copy-to-clipboard screenshots** use `screencapture -ic`, which hands the image to the clipboard without ever touching disk. The Desktop path deletes its target file if the capture doesn't succeed, so a cancelled capture leaves nothing behind.
- **Reduce Transparency** is honoured — the vibrancy layers fall back to a solid background.

## Non-goals

No iCloud sync, no image or file clips, no accounts, no telemetry, no auto-updater. One third-party dependency ([KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts)) and nothing else. Keeping it small is the point.

## Contributing

Issues and pull requests are welcome — especially bug reports, design tweaks, and accessibility improvements. Please keep the dependency count at one.

## License

MIT — see [LICENSE](LICENSE).
