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
| `App/AppUpdater.swift` | Sparkle `SPUStandardUpdaterController` wrapper (`@Observable`), feed = appcast on the latest GitHub release; menu item in `AppCommands`, toggles in Settings › General. Not started under tests. |
| `Web/PageAssistant.swift` | Page summary + Q&A: reads the page's text (isolated content world), splits it into numbered passages (`PageText`, pure), picks passages within the model's context budget (question-matching ones first), streams answers; one `PageAssistant` per tab in `BrowserState`. UI in `UI/PageAssistantPanel.swift`. |
| `Web/FindInPage.swift`, `UI/FindBar.swift` | ⌘F find (`WKWebView.find` + a match count from the page text) and ⌘⇧F ask mode: page passages → `@Generable FindAnswer` (answer + passage numbers) → glow highlight via `PageScripts.highlight`. `PageFind` (pure) has keyword fallback and validation. One `FindInPage` in `BrowserState`. |
| `Web/FormFill/`, `Resources/formfill.js` | Smart form fill: the script (isolated world) spots address/contact forms and shows a "My Card" dropdown; `FormFillBridge` loads the card (`MeCard`, Contacts), classifies fields with `FormFieldClassifier` (pure: autocomplete, then multilingual keywords) and asks `FormFieldModel` (`@Generable`) about the rest; `FormFillPlanner` (pure) adapts to the layout (separate house number, "Vorname"/"Name"). HTTPS only, user-initiated. |
| `Web/PageTranslator.swift` | Per-tab translation: language detection (`NLLanguageRecognizer` + `lang`), text-node collection/apply/restore in the isolated world, batches through a `TranslationSession` handed out by the window's `.translationTask(browser.translationConfig)`. |
| `Web/PageActions.swift`, `UI/PageActionSheet.swift` | ⌘K page actions: `EventDraft` → `ICS` (.ics opened in Calendar), `<table>` extraction or `TableDraft` → `CSV`, `ComparisonDraft` for several tabs. Pure `ICS`/`CSV`/`PageCompare` are unit tested. |
| `Web/PageWatcher.swift`, `UI/Settings/WatchedPagesPane.swift` | Watched pages (`watches.json`): 60 s scheduler, `HeadlessPage` (off-screen WKWebView, default data store), `PageDiff` line diff, `ChangeReport` significance check, `UNUserNotificationCenter` notifications that open the page. |
| `Web/PageScripts.swift` | Shared isolated-world JS: main text, passage glow highlight, match counting. |
| `Web/SmartTitles.swift` | Smart tab titles: `SmartTitler` (pure heuristics + validation) and `SmartTitleService` (cache, debounce, one model call at a time). `TabRow` calls `refresh` whenever a tab's title changes. |
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
| `Passwords/PasskeySupport.swift` | Checks the browser passkey entitlement (`SecTask`) and drives `ASAuthorizationWebBrowserPublicKeyCredentialManager` authorization. WebKit performs the WebAuthn ceremonies. |
| `Web/LoginImpactBridge.swift` | Isolated-world detector for trusted clicks on "Sign in with Apple" / passkey buttons (EN + DE patterns). |
| `UI/Effects/ImpactOverlay.swift` + `Ripple.metal` | Wave-impact: `browsiRipple` layer shader over a page snapshot, Canvas rings/sparks/flash, `ImpactShake` keyframes. |
| `Config/Signing.xcconfig` | Default ad-hoc signing; includes optional git-ignored `Signing.local.xcconfig` for team + passkey entitlement. |
| `Home/HomeView.swift` | Home page: clock, AI search bar + answer card, draggable/resizable module grid with live reflow preview. |
| `Home/GridLayout.swift` | Pure 12-column grid engine: push-down on overlap + vertical compaction (unit tested). |
| `Home/HomeStore.swift`, `HomeWebCache.swift` | Module persistence (`home.json`) and one cached WKWebView per module (purged under memory pressure while hidden). |
| `Home/SmartSearch.swift` | Foundation Models session with tools `searchWeb` (DuckDuckGo HTML), `readWebPage`, `searchMyHistory`; streams answers with numbered citations. |
| `UI/Downloads/DownloadsView.swift` | Downloads button, queue popover, arc flight animation (`ArcFlight`). |
| `Passwords/PasskeyAuthenticator.swift`, `Resources/webauthn.js` | Built-in WebAuthn platform authenticator (ES256, "none" attestation, Keychain storage, Touch ID per ceremony); page-world script overrides `navigator.credentials` for `publicKey` requests. Origin comes from WKFrameInfo; RP ID validated against it. |
| `Extensions/ExtensionManager.swift` | `WKWebExtensionController` + contexts: install (Chrome Web Store CRX → ZIP, files, folders), grant requested permissions on install, persist `extensions.json`, controller delegate (tabs, options, permission prompts, action popups) and tab/window adapters. |
| `UI/Settings/ProfileCard.swift`, `MacInfo.swift` | Settings › Profile card (cursor-tracking tilt, parallax horizon) and Mac hardware lookup (IORegistry `product-name`, sysctl). |
| `Extensions/ExtensionsViews.swift` | Sidebar extension toolbar, Settings › Extensions pane. |
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
- Watched pages: `Application Support/Browsi/watches.json` (includes each page's last text as the diff baseline)
- Preferences: `UserDefaults` (`searchEngine`, `suspendAfterMinutes`, `contentBlockingEnabled`, `blockerAllowlist`, …)
- Passwords: Keychain, label `Browsi`

## Status

**Done:** everything listed under Features in the README; unit tests for the parser, palette ranking, keychain, blocker rules and suspension logic.

**Notes:**
- Closing tabs skips unloaded pinned tiles when choosing the next tab, falling back to Home when no open tabs remain.
- Settings › Appearance offers 21 app icons in three switchable collections (Space, Exploration, Galaxy), with a current-icon summary, default reset and compact four-column grid. Collection 04 remains concept artwork only. Pulsar is the bundled icon and default preference; saved alternate choices remain unchanged and apply to the running app's Dock icon.
- The default Dock icon is also applied explicitly from its image asset, avoiding stale macOS bundle-icon caches after updates.
- Tab switches are deliberately un-animated: one persistent `WebViewHost` swaps web views, and `.transaction { $0.animation = nil }` keeps springs from leaking in.
- The traffic lights fade out while the sidebar is collapsed and return when it is shown or peeked.
- Many web settings (JS, autoplay, pop-ups, HTTPS upgrade, fraud warnings, min font, zoom, inspector) apply to newly created tabs.

**Not yet verified manually:** find/ask bar, page translation, ⌘K page actions and watched-page notifications in the running app (their page scripts were checked against a live Wikipedia page and their logic is unit tested), the end-to-end autofill/Touch ID flow, floating video on major sites (YouTube, Netflix, Twitch), Google sign-in, swipe gestures, drag-and-drop, and blocker effectiveness on real sites.

- Page assistant and smart titles generate plain text with `.permissiveContentTransformations` guardrails: guided generation refused harmless news headlines in testing.

**Known limitations**
- The page assistant reads at most ~5,000 characters per request (on-device context window), so long pages are summarized from their opening; questions pull in the passages that match them. PDFs shown in a tab have no readable text yet.
- Single window; no private-browsing window yet.
- No dedicated history UI (history is searchable via the palette).
- Find, translation and page actions read the main frame only (not iframes). Translation covers the text present when it runs; content the page adds later stays untranslated until you translate again.
- ⌘F replaces the Edit menu's text-editing group (Find, Spelling and Substitutions submenus) so web pages get Browsi's find bar.
- Watched pages are only checked while Browsi is running; pages that change their text on every load (live tickers) depend on the model to filter noise.
- iCloud password sync needs signing with an Apple Development team.
- The block list is a small curated domain list (~100 hosts), not full EasyList.
- Release builds from CI are ad-hoc signed and not notarized (no Developer ID secrets yet). Saved passwords in the file-based keychain may ask for access again after an update because the ad-hoc signature changes.
- History writes run on the main context (batched); move to a `@ModelActor` if it shows up in profiles.

## Roadmap ideas

1. Private windows.
2. Import passwords from CSV; passkeys via `ASAuthorization`.
3. Larger/updatable filter lists, with blocked-request counts.
4. Split view, tab previews on hover, per-space website data stores (profiles).
5. Instruments pass: memory with 20+ tabs before/after suspension.
