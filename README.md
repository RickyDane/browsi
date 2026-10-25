# Browsi

A native macOS browser built with SwiftUI and WebKit: vertical tabs, Spaces, Liquid Glass, spring animations, and passwords kept in the macOS Keychain.

> Requires **macOS 26+** (Liquid Glass APIs) and **Xcode 26+**.

## Features

- **Vertical tab sidebar**: pinned tiles, drag to reorder, drop a tab on the space header to pin it, hover the left edge to peek a hidden sidebar.
- **Spaces**: each with its own colour, icon and animated mesh-gradient tint. Switch with ⌃1–9, ⌘⌥←/→ or a two-finger swipe on the sidebar.
- **Floating video**: leave a tab that's playing a video and the video pops out into a floating window you can drag and resize (double-click it to go back to the tab).
- **Link Peek**: ⇧-click a link to preview it in a glass modal. ⌘↩ opens it as a tab, Esc closes it.
- **Middle-click**: middle-click a link to open it in a background tab (⇧ for foreground); middle-click a tab in the sidebar to close it.
- **Smart-rename downloads**: unclear names like `file_8f3a2c91.pdf` are renamed by Apple Intelligence's on-device model (Foundation Models) from the source page and the file's text, e.g. `Acme Invoice 8823 2026-10.pdf`.
- **Command palette** (⌘T / ⌘L / ⌘K): fuzzy search across open tabs, bookmarks, history and commands, with URL-or-search fallback.
- **Keychain passwords**: captures logins, offers to save them as Keychain items, autofills behind Touch ID, and has a password manager in Settings.
- **Tracker & ad blocking**: a compiled WebKit content rule list, toggled per site from the shield in the address bar.
- **Performance**: only the visible tab is attached to the window; idle tabs are suspended (snapshot + state saved, web view released) after a timeout or under memory pressure.
- **Settings**: a System-Settings-style window with ~40 options across General, Appearance, Tabs & Spaces, Privacy & Security, Passwords, Websites, Downloads and Advanced.
- **History & bookmarks**: stored with SwiftData. Sessions (spaces and tabs) are restored on launch.
- **Glass & motion**: `.glassEffect`, morphing selection, a glowing progress bar, blur-scale transitions. Everything respects Reduce Motion.

## Getting started

```sh
brew install xcodegen
scripts/build.sh            # generate Browsi.xcodeproj + build
scripts/build.sh test       # run unit tests (Swift Testing)
open build/Build/Products/Debug/Browsi.app
```

To work in Xcode, run `xcodegen generate` and open `Browsi.xcodeproj`. The project file is generated and git-ignored; `project.yml` is the source of truth.

## Keyboard shortcuts

| Action | Shortcut |
|---|---|
| New tab (palette) / Edit address / Palette | ⌘T / ⌘L / ⌘K |
| Close tab / Reopen closed tab | ⌘W / ⌘⇧T |
| Toggle sidebar | ⌘S |
| Bookmark page / Pin tab | ⌘D / ⌘⇧P |
| Back / Forward / Reload | ⌘[ / ⌘] / ⌘R |
| Select tab 1–9 / Next–previous tab | ⌘1–9 / ⌃Tab, ⌘⇧] ⌘⇧[ |
| Select space 1–9 / Next–previous space | ⌃1–9 / ⌘⌥→ ⌘⌥← |
| New space | ⌘⇧N |
| Link Peek / open peek as tab / close | ⇧-click / ⌘↩ / Esc |
| Open link in new tab / close tab | Middle-click link / middle-click tab |
| Zoom | ⌘+ / ⌘- / ⌘0 |

## Passwords & signing

Logins are stored as `kSecClassInternetPassword` items labelled `Browsi`. An ad-hoc-signed build (the default) uses the login keychain. If you sign with an Apple Development team, Browsi switches to the data-protection keychain automatically, and the *Sync via iCloud Keychain* toggle takes effect. Browsi cannot read Safari's or the Passwords app's entries.

## Further reading

- [INFO.md](INFO.md): architecture, data flow, status and roadmap.
- [AGENTS.md](AGENTS.md): conventions for contributors and coding agents.
