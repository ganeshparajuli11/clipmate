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
- **Files as well as text** — copy files or folders in Finder and they land in the history with their real Finder icons. Click one to put it back on the clipboard, then **⌘V to copy** or **⌥⌘V to move** it wherever you are.
- **Catches cuts too** — ClipMate watches the pasteboard, so ⌘X is captured exactly like ⌘C, from any app.
- **Optional Windows-style cut in Finder** — turn on one setting and ⌘X cuts files, ⌘V moves them. Off by default; it's the only feature that asks for Accessibility.
- **Pin from the panel** — one click on a clip's pin button files it into the first free slot. Click again to un-pin. No slot picker, no trip to Settings.
- **Starts completely empty** — no sample pins, no fake clips. Nothing appears until you actually copy something.
- **Screenshot** — drag-select any region. Save a timestamped PNG to the Desktop, or copy it straight to the clipboard with no file written at all.
- **Ask once, then remember** — optionally have ClipMate ask Copy-or-Save the first time, then silently reuse your answer forever.
- **Two global hotkeys** — show/hide the panel (⌘2 by default) and take a screenshot without opening the panel first (⌘F1). Both re-recordable.
- **Launch at login** — one toggle.
- **Knows when files go missing** — a copied file that has since been deleted or moved is shown struck through and refuses to paste a dead reference.

## Screenshots

> _TODO: add screenshots here._
>
> - `docs/panel.png` — the panel open in the menu bar
> - `docs/settings.png` — the Settings window

## Install

### Download

Grab **`ClipMate.dmg`** from the [latest release](https://github.com/ganeshparajuli11/clipmate/releases/latest), open it, and drag ClipMate into Applications. macOS 13 Ventura or later.

Because the app is signed with a self-signed certificate rather than an Apple Developer one, the first launch needs **right-click ▸ Open** — see [Gatekeeper](#gatekeeper) below.

### Build from source

1. Install **Xcode** from the Mac App Store (free).
2. Open `ClipMate.xcodeproj`.
3. Let Xcode resolve the `KeyboardShortcuts` package (it does this on its own).
4. Press **⌘R**. The icon appears in your menu bar.

To keep it around permanently:

5. **Product ▸ Archive ▸ Distribute App ▸ Copy App**, then drag `ClipMate.app` into `/Applications`.
6. Open Settings from the panel's gear button, add your pins, and turn on **Launch at login**.

From then on it just runs — no Xcode, no terminal.

### Signing (read this if the build fails)

The project is configured to sign with a local certificate named **`ClipMate Self-Signed`**, which won't exist on your machine. If you see *"No certificate matching 'ClipMate Self-Signed' found"*, pick one of these:

**Quickest — build ad-hoc.** In Xcode, select the ClipMate target ▸ *Signing & Capabilities* ▸ set Signing Certificate to **Sign to Run Locally**. Or from the command line:

```
xcodebuild -scheme ClipMate CODE_SIGN_IDENTITY="-" CODE_SIGN_STYLE=Automatic build
```

**Better if you'll rebuild often — make your own certificate.** Keychain Access ▸ *Certificate Assistant* ▸ *Create a Certificate…*, name it `ClipMate Self-Signed`, Identity Type **Self Signed Root**, Certificate Type **Code Signing**. No Apple ID needed.

Why bother? An ad-hoc signature's identity is just a hash of the binary, so **every rebuild looks like a brand-new app to macOS** and the Screen Recording permission resets each time. Signing with a stable certificate makes the identity survive rebuilds, so you grant permissions once. That is the only reason this setting exists.

### Gatekeeper

A locally built app isn't signed with a paid Apple Developer certificate, so the first time you open it from `/Applications` macOS may refuse. **Right-click the app ▸ Open**, then confirm — or approve it in **System Settings ▸ Privacy & Security**. You only do this once. Proper signing and notarization need a paid Apple Developer account and are out of scope.

## Using it

**Pins** can be typed into Settings — four fields, `Pin 1` through `Pin 4`, filled in any order — or created straight from the panel by clicking the pin button on any recent clip, which drops it into the first free slot. Clicking a filled pin button un-pins. There is no "choose a slot" dialog anywhere in the app. Empty slots are never shown, and set pins collapse upward with no gaps. Edits save to `UserDefaults` immediately, so quitting, relaunching, or updating never loses them.

**Clipboard history** starts empty and fills as you use the machine. Set the cap (3–12) in Settings, or clear it there or from the panel's `Clear` button. Pins are never touched by clearing history. Right-click any entry to remove just that one, or to reveal a copied file in Finder.

**Files.** macOS has no ⌘X for files — Finder deliberately omits it. The Mac equivalent is copy-then-move-on-paste, and ClipMate supports the whole flow: copy files in Finder (⌘C), pick them from ClipMate later, then in the destination folder press **⌘V** to copy or **⌥⌘V** ("Edit ▸ Move Item Here") to move. Multi-file selections are kept together as a single entry. Pins remain text-only, since a pin is a plain string.

**Finder cut & paste (optional).** If you'd rather have the Windows behaviour, Settings has a toggle: *Use ⌘X to cut and ⌘V to move files in Finder*. With it on, ⌘X marks the selection and ⌘V moves it into whatever folder you're viewing. Press **Escape** to abandon a pending cut.

The interception is deliberately narrow — it only takes over ⌘X/⌘V when Finder is frontmost and you are **not** renaming a file, so cutting text in a rename field still works, and every other app is untouched. ⌥⌘V keeps working as normal. On a name collision the moved file is renamed (`report 2.txt`); nothing is ever overwritten.

This is the one feature that needs **Accessibility** permission, because refusing to deliver a keystroke to Finder is only possible with an event tap, and macOS gates those behind Accessibility. It also asks for **Automation** access to Finder, to read the selection and the current folder. Leave the toggle off and neither is ever requested.

**Screenshots** default to whichever radio option is selected. Turn on *Ask me the first time, then remember my choice* and the next capture shows a small Copy / Save prompt; after you answer, ClipMate never asks again. Change the remembered answer any time by picking a different radio, or flip the toggle off and on to be asked once more.

**Both hotkeys** are recorded in Settings and apply the moment you set them.

## Permissions

ClipMate is built to ask for as little as possible.

| Permission | Needed? | Why |
|---|---|---|
| **Notifications** | ❌ No | Confirmations appear inside the panel instead. |
| **Full Disk Access** | ❌ No | Nothing is read outside the app's own preferences. |
| **Screen Recording** | ⚠️ Once | Only the first time you take a screenshot. macOS shows the prompt itself; ClipMate never asks up front. |
| **Accessibility** | ⚙️ Opt-in | Only if you switch on Finder cut & paste. The hotkeys use Carbon and never need it. |
| **Automation (Finder)** | ⚙️ Opt-in | Same feature only — used to read the Finder selection and the folder you're viewing. |

Nothing ever leaves your machine — there is no network code in this app at all.

## How it works

- **Storage** is `UserDefaults`, a handful of keys: `clipmate.pins`, `clipmate.history`, `clipmate.historySize`, `clipmate.screenshotToClipboard`, `clipmate.screenshotAskFirst`, `clipmate.screenshotChoiceRemembered`.
- **Capture** polls `NSPasteboard.changeCount` once a second — a single integer comparison; the pasteboard is only read when something actually changed. Watching the pasteboard rather than keystrokes is what makes ⌘X work for free, and is why no Accessibility permission is needed.
- **History is de-duplicated** — re-copying an old clip promotes it to the top instead of adding a second row.
- **File clips** are read with `readObjects(forClasses: [NSURL.self])` and checked *before* the plain-text branch, because a Finder copy also puts a text representation on the pasteboard. Writing them back uses `writeObjects`, which publishes both the file-URL type Finder needs and a text fallback. History is stored as JSON so a file clip keeps its full path list; older plain-`[String]` histories migrate automatically.
- **Copy-to-clipboard screenshots** use `screencapture -ic`, which hands the image to the clipboard without ever touching disk. The Desktop path deletes its target file if the capture doesn't succeed, so a cancelled capture leaves nothing behind.
- **Finder cut & paste** uses a `CGEventTap` that swallows the keystroke and then does the slow work asynchronously, because a tap callback that blocks for too long gets disabled by the system. It re-enables itself if macOS disables it. Finder's selection and insertion location come from AppleScript; the move is plain `FileManager`, with collision renaming rather than overwriting.
- **Reduce Transparency** is honoured — the vibrancy layers fall back to a solid background.

## Non-goals

No iCloud sync, no image clips, no accounts, no telemetry, no auto-updater. One third-party dependency ([KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts)) and nothing else. Keeping it small is the point.

## Contributing

Issues and pull requests are welcome — especially bug reports, design tweaks, and accessibility improvements. Please keep the dependency count at one.

## License

MIT — see [LICENSE](LICENSE).
