<p align="center"><img src="Design/logo-1024.png" width="160" alt="Browsi logo"></p>

# Browsi

A native macOS browser built with SwiftUI and WebKit: vertical tabs, Spaces, Liquid Glass, spring animations, and passwords kept in the macOS Keychain.

> Requires **macOS 26+** (Liquid Glass APIs) and **Xcode 26+**.

## Features

- **Home page** (always at the top of the sidebar, ⌘⇧H): a clock, an AI search bar and a grid of live web pages ("modules") you can drag, resize, zoom and rearrange; other modules make room as you move one. The clock + search bar block can be moved and resized on the same grid. Links navigate inside their module; ⌘-click or middle-click opens them as a tab.
- **Smart answers**: the home search bar answers questions with Apple Intelligence's on-device model, which can search the web, read pages and look through your history, and cites its sources ([1], [2]…). The bar shows the same suggestions as the command palette (↑/↓, ↩); ⇧↩ searches your search engine, ⌘↩ asks Apple Intelligence.
- **Download queue**: a floating glass downloads button appears top right when a download starts (and hides after 30 s idle; toggle with ⌘J). It shows progress, and files fly into it from where you clicked. The queue offers open, reveal, cancel, retry, rename, undo rename and **Smart Rename** (Apple Intelligence) per file.
- **Vertical tab sidebar**: pinned tiles, drag to reorder, drop a tab on the space header to pin it, hover the left edge to peek a hidden sidebar.
- **Spaces**: each with its own colour, icon and animated mesh-gradient tint. Switch with ⌃1–9, ⌘⌥←/→ or a two-finger swipe on the sidebar.
- **Floating video**: leave a tab that's playing a video and the video pops out into a floating window you can drag and resize (double-click it to go back to the tab).
- **Link Peek**: ⇧-click a link to preview it in a glass modal. ⌘↩ opens it as a tab, Esc closes it.
- **Middle-click**: middle-click a link to open it in a background tab (⇧ for foreground); middle-click a tab in the sidebar to close it.
- **Smart-rename downloads**: unclear names like `file_8f3a2c91.pdf` are renamed by Apple Intelligence's on-device model (Foundation Models) from the source page and the file's text, e.g. `Acme Invoice 8823 2026-10.pdf`.
- **Wave impact**: clicking "Sign in with Apple" or a passkey button makes the page ripple like water from the click (Metal shader), with shockwave rings, sparks, a flash and a short card shake. Toned down for Reduce Motion; toggle in Settings › Appearance.
- **Passkeys**: full WebAuthn via WebKit (iCloud Keychain, password-manager apps, iPhone via QR code, security keys, passkey autofill), once the build carries Apple's browser passkey entitlement (see below).
- **Command palette** (⌘T / ⌘L / ⌘K): fuzzy search across open tabs, bookmarks, history and commands, with URL-or-search fallback.
- **Keychain passwords**: captures logins, offers to save them as Keychain items, autofills behind Touch ID, and has a password manager in Settings.
- **Extensions**: install Chrome Web Store extensions (paste a link, use "Add" on the store page, or pick one in Settings › Extensions) or load a .crx / .zip / unpacked folder. Runs on WebKit's web extension engine (MV2 + MV3): content scripts, declarativeNetRequest, background workers, toolbar buttons with popups, options pages. Popular picks: uBlock Origin Lite, Dark Reader, SponsorBlock, Return YouTube Dislike, Bitwarden.
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
| Edit address | ⌘L |
| New tab (palette) / Home / Command palette | ⌘T / ⌘⇧H / ⌘K |
| Close tab / Reopen closed tab | ⌘W (pinned tabs stay pinned, just unloaded) / ⌘⇧T |
| Toggle sidebar | ⌘S |
| Bookmark page / Pin tab | ⌘D / ⌘⇧P |
| Back / Forward / Reload | ⌘[ / ⌘] (or mouse thumb buttons) / ⌘R |
| Select tab 1–9 / Next–previous tab | ⌘1–9 / ⌃Tab, ⌘⇧] ⌘⇧[ |
| Select space 1–9 / Next–previous space | ⌃1–9 / ⌘⌥→ ⌘⌥← |
| New space | ⌘⇧N |
| Link Peek / open peek as tab / close | ⇧-click / ⌘↩ / Esc |
| Open link in new tab / close tab | Middle-click link / middle-click tab |
| Downloads | ⌘J |
| Zoom | ⌘+ / ⌘- / ⌘0 |

## Passwords & signing

Logins are stored as `kSecClassInternetPassword` items labelled `Browsi`. An ad-hoc-signed build (the default) uses the login keychain. If you sign with an Apple Development team, Browsi switches to the data-protection keychain automatically, and the *Sync via iCloud Keychain* toggle takes effect. Browsi cannot read Safari's or the Passwords app's entries.

## Passkeys

Browsi ships its **own passkey authenticator**, so passkeys work without anything from Apple: when a site
asks to create or use a passkey, Browsi generates a P-256 key, stores it in your macOS Keychain and asks
for Touch ID (or your login password) every time. Registration and sign-in are verified end to end
against [webauthn.io](https://webauthn.io) in the test suite. Manage saved passkeys in
Settings › Passwords › Passkeys.

Limits of the built-in authenticator: its passkeys live only in Browsi (not in iCloud Keychain), you
can't use passkeys saved by Safari / the Passwords app or sign in with your iPhone, passkey autofill
(conditional UI) isn't offered, and sites that demand hardware attestation may refuse it.

For full system passkeys, Browsi needs Apple's **Web Browser Public Key Credential** entitlement
(`com.apple.developer.web-browser.public-key-credential`). Once a build carries it, Browsi switches to
the system automatically and stops injecting its own authenticator.

To enable passkeys:

1. **Request the entitlement** for your team via the request form linked from Apple's [Passkey use in web browsers](https://developer.apple.com/documentation/authenticationservices/passkey-use-in-web-browsers) documentation (sign in with your developer account; macOS browser, bundle id `dev.perlick.browsi`).
2. Once Apple grants it, in *Certificates, Identifiers & Profiles*:
   - register the App ID `dev.perlick.browsi` and enable the **Web Browser Public Key Credential** capability;
   - make sure you have an **Apple Development** (and later **Developer ID Application**) certificate;
   - create a **macOS App Development** provisioning profile for that App ID that includes your Mac, name it e.g. `Browsi Passkeys Development`, download it and double-click to install.
3. `cp Config/Signing.local.xcconfig.example Config/Signing.local.xcconfig` and adjust the team / profile name (the file is git-ignored).
4. `scripts/build.sh`, launch, then Settings › Passwords › Passkeys › **Allow…**. macOS then lists Browsi under
   System Settings › Privacy & Security › Passkeys Access for Web Browsers. Clicking a passkey button on a site also prompts.
5. For distribution, use a Developer ID profile with the same capability and `CODE_SIGN_IDENTITY = Developer ID Application`, then notarize.

Team signing also moves saved passwords to the data-protection keychain and makes the iCloud sync toggle work.

## Further reading

- [INFO.md](INFO.md): architecture, data flow, status and roadmap.
- [AGENTS.md](AGENTS.md): conventions for contributors and coding agents.
