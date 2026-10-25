# Browsi

Native macOS 26 browser: vertical tab sidebar with Spaces, Liquid Glass UI, command palette, Keychain-backed passwords, tracker blocking and tab suspension.

```sh
brew install xcodegen
scripts/build.sh          # generate project + build
scripts/build.sh test     # run unit tests
open build/Build/Products/Debug/Browsi.app
```

Shortcuts: ⌘T new tab (palette) · ⌘L edit address · ⌘K palette · ⌘W close · ⌘⇧T reopen · ⌘S sidebar · ⌘D bookmark · ⌘1–9 tabs · ⌃1–9 spaces · ⌘⌥←/→ spaces (or two-finger swipe on the sidebar).

Passwords are stored as `kSecClassInternetPassword` items labelled `Browsi`. When ad-hoc signed the login keychain is used; sign with a team to use the data-protection keychain and optional iCloud sync.
