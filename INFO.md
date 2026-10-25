# Browsi: project info

## Overview

| | |
|---|---|
| Platform | macOS 26+ (Apple Silicon), single main window |
| Language | Swift 6 (strict concurrency, default `MainActor` isolation) |
| UI | SwiftUI + AppKit bridges (`NSViewRepresentable`, `NSAlert`, event monitors) |
| Engine | `WKWebView` (one per live tab) |
| Storage | SwiftData (history, bookmarks), JSON (session), UserDefaults (prefs), Keychain (passwords) |
| Project | XcodeGen (`project.yml`), bundle id `dev.perlick.browsi`, sandboxed, hardened runtime |
| Tests | Swift Testing in `BrowsiTests/` (16 tests) |

## Architecture

```
BrowsiApp ─► AppDelegate.browser (BrowserState, single instance)
               │
               ├─ spaces: [Space] ─► pinnedTabs / tabs: [Tab]
               │                         └─ controller: TabWebController? ─► WKWebView
               ├─ library: LibraryStore (SwiftData)
               ├─ suspender: TabSuspender
               └─ transient UI: palette, toast, pendingPasswordSave, sidebarVisible

MainWindowView
  ├─ MeshBackground (space hue)
  ├─ SidebarView ─ NavRow, URLBarView, PinnedTabsGrid, TabRow list, SpaceSwitcher
  ├─ ContentCard ─ WebViewHost(selected tab) + snapshot overlay + ProgressGlow
  └─ overlays: CommandPaletteView, SavePasswordBanner, ToastView
```

### Key types

| File | Responsibility |
|---|---|
| `Models/BrowserState.swift` | All tab/space mutations, navigation, session save, password-save resolution. Implements `TabEventsDelegate`. |
| `Models/Tab.swift`, `Space.swift` | `@Observable` state. A tab is *suspended* when `controller == nil`. |
| `Models/URLInputParser.swift` | Decides URL vs. search; `SearchEngine` URLs. |
| `Web/TabWebController.swift` | Owns the `WKWebView`; KVO → `Tab`; navigation/UI delegates, error page, popups, downloads. |
| `Web/WebConfigFactory.swift` | Per-tab `WKWebViewConfiguration` (own `WKUserContentController`, autofill script, rule list). |
| `Web/WebViewHost.swift` | Re-parents the selected tab's web view into the SwiftUI tree. |
| `Web/FloatingPlayer.swift` | Moves a playing tab's web view into a floating `NSPanel` and restyles the video (via JS in the isolated world) to fill it. |
| `UI/PeekOverlay.swift` | ⇧-click Link Peek modal; the peek tab is promoted to a real tab with `BrowserState.promotePeek()`. |
| `Persistence/Preferences.swift` | Every setting, plus `UserAgent` (claims the installed Safari version so Google sign-in accepts the engine). |
| `Web/LinkBridge.swift` | Isolated-world script that turns trusted middle-clicks on links into new tabs (WebKit doesn't navigate on middle-click). |
| `UI/Sidebar/MiddleClickCloser.swift` | App-wide monitor + hover tracking to close sidebar tabs with the middle button. |
| `Web/SmartRenamer.swift` | Foundation Models (`@Generable SmartFileName`) download renaming; PDF/text snippets via PDFKit; pure sanitising helpers. |
| `Web/TabSuspender.swift` | 30 s sweep + memory-pressure source; snapshot + `interactionState`, then release. |
| `Passwords/KeychainStore.swift` | `SecItem*` wrapper; probes the data-protection keychain, falls back to the login keychain. |
| `Passwords/PasswordBridge.swift` + `Resources/autofill.js` | JS ↔ native messages `accounts` / `fill` / `submit` in the isolated `.defaultClient` content world. |
| `Passwords/BiometricGate.swift` | `LAContext` gate with a 5-minute grace period. |
| `ContentBlocking/ContentBlocker.swift` | Builds rules from `blocklist.txt`, compiles/caches via `WKContentRuleListStore`, applies per host. |
| `Persistence/LibraryStore.swift` | History (frecency) & bookmarks, debounced saves. |
| `UI/CommandPalette/PaletteSearch.swift` | Pure ranking/fuzzy matching (unit tested). |
| `UI/Effects/Animations.swift` | `Motion` springs, `BlurScaleTransition`, `SquishButtonStyle`. |

## Data flow highlights

- **Navigation:** palette or URL bar → `BrowserState.open(…)` → `TabWebController.load` → KVO updates `Tab` → SwiftUI re-renders. `didFinish` records history and fetches the favicon.
- **Tab switch:** `select(_:)` snapshots the outgoing tab, updates `selectedTabID`, and calls `activate` (revives a suspended tab from its `interactionState` or URL).
- **Password save:** `autofill.js` catches the submit → `submit` message → origin check (HTTPS/localhost) → `pendingPasswordSave` → banner → `KeychainStore.save`.
- **Password fill:** focusing a login field sends `accounts`, which returns usernames only. Picking one sends `fill`, which runs Touch ID and then returns the password to the matching origin only.
- **Blocking:** the rule list is compiled once at startup. Each main-frame navigation re-applies it based on `Preferences.blockerAllowlist`.

## Persistence locations

- Session: `~/Library/Containers/dev.perlick.browsi/Data/Library/Application Support/Browsi/session.json`
- SwiftData store: default container location inside the sandbox
- Preferences: `UserDefaults` (`searchEngine`, `suspendAfterMinutes`, `contentBlockingEnabled`, `blockerAllowlist`, …)
- Passwords: Keychain, label `Browsi`

## Status

**Done:** everything listed under Features in the README; unit tests for the parser, palette ranking, keychain, blocker rules and suspension logic.

**Notes:**
- Tab switches are deliberately un-animated: one persistent `WebViewHost` swaps web views, and `.transaction { $0.animation = nil }` keeps springs from leaking in.
- The traffic lights fade out while the sidebar is collapsed and return when it is shown or peeked.
- Many web settings (JS, autoplay, pop-ups, HTTPS upgrade, fraud warnings, min font, zoom, inspector) apply to newly created tabs.

**Not yet verified manually:** the end-to-end autofill/Touch ID flow, floating video on major sites (YouTube, Netflix, Twitch), Google sign-in, swipe gestures, drag-and-drop, and blocker effectiveness on real sites.

**Known limitations**
- Single window; no private-browsing window yet.
- No find-in-page (⌘F), no dedicated history/downloads UI (history is searchable via the palette).
- iCloud password sync needs signing with an Apple Development team.
- The block list is a small curated domain list (~100 hosts), not full EasyList.
- History writes run on the main context (batched); move to a `@ModelActor` if it shows up in profiles.

## Roadmap ideas

1. Find in page, private windows, downloads popover.
2. Import passwords from CSV; passkeys via `ASAuthorization`.
3. Larger/updatable filter lists, with blocked-request counts.
4. Split view, tab previews on hover, per-space website data stores (profiles).
5. Instruments pass: memory with 20+ tabs before/after suspension.
