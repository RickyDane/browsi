# AGENTS.md

Guidance for AI coding agents and contributors working on Browsi. Read [INFO.md](INFO.md) for the architecture first.

## Build & test

```sh
scripts/build.sh          # xcodegen generate + xcodebuild build (filtered output)
scripts/build.sh test     # build + Swift Testing run; look for "Test run with N tests … passed"
```

- **Never edit `Browsi.xcodeproj`.** It is generated and git-ignored. Add files under `Browsi/` or `BrowsiTests/` and they are picked up automatically; change build settings in `project.yml`.
- Build output goes to `./build` (DerivedData). Launch with `open build/Build/Products/Debug/Browsi.app`.
- Long builds and test runs should run as a background task so failures are noticed.
- A change is done when the build has **no errors and no new warnings** and all tests pass.

## Swift conventions

- Swift 6, `SWIFT_STRICT_CONCURRENCY=complete`, **default actor isolation is `MainActor`** for both targets.
  - Pure logic that must be callable anywhere (parsers, ranking, keychain, Codable snapshots) is marked `nonisolated` (see `URLInputParser`, `PaletteSearch`, `KeychainStore`, `SessionSnapshot`).
  - KVO/timer/dispatch callbacks hop back with `MainActor.assumeIsolated` (they fire on main).
  - Prefer the `async` variants of WebKit delegate methods.
- State uses `@Observable` classes; there is one `BrowserState`, injected with `.environment(browser)`. Mutate tabs and spaces **through `BrowserState`** so animation, session saving (`scheduleSave()`) and suspension stay consistent.
- `Tab.controller == nil` means suspended. Call `browser.activate(tab)` before touching `tab.controller` on a tab that may be asleep.
- Settings go in `Preferences` (UserDefaults-backed, `didSet` persistence).

## UI & motion

- Use the shared `Motion.snappy / .bouncy / .smooth` animations and `BlurScaleTransition`. Don't hard-code springs. They already honour Reduce Motion.
- Glass: `.glassEffect(...)`, `.buttonStyle(.glass / .glassProminent)`. Keep glass for floating or chrome elements; the web content card stays opaque.
- Custom icon buttons use `SquishButtonStyle`.
- Only the selected tab's `WKWebView` may be in the view hierarchy (`WebViewHost`). Don't render multiple web views.

## Security rules (passwords)

- Secrets only go to a frame whose `securityOrigin` host matches the stored item, and only over HTTPS (or localhost).
- The bridge lives in the isolated `.defaultClient` content world. Don't expose it to the page world.
- Reading a password for fill or reveal must go through `BiometricGate`.
- Keychain items carry the `Browsi` label. Tests use unique labels and clean up with `deleteAll()`.
- Never log credentials.

## Tests

- Swift Testing (`import Testing`, `@Test`, `#expect`), files in `BrowsiTests/`.
- Keep logic testable by putting it in pure `nonisolated` types. UI isn't unit tested.
- Use `BrowserState(library: LibraryStore(inMemory: true), restore: false)` in tests. Never touch the user's session file.

## Content blocker

- Add hosts to `Browsi/Resources/blocklist.txt` (one per line, optional `/path`).
- **Bump `ContentBlocker.identifier`** whenever the list or rule generation changes, otherwise WebKit serves the stale compiled list.

## Git

- Small, focused commits with descriptive messages. Don't commit `build/` or the generated project.
- Update `INFO.md` (status/limitations) and `README.md` (features/shortcuts) when behaviour changes.
