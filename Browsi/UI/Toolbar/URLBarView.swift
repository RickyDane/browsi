import SwiftUI

struct URLBarView: View {
    @Environment(BrowserState.self) private var browser
    @State private var hovering = false

    var body: some View {
        let tab = browser.selectedTab
        let host = tab?.isHome == true ? nil : tab?.url?.host()
        HStack(spacing: 6) {
            Image(systemName: tab?.isSecure == true ? "lock.fill" : tab?.url == nil ? "magnifyingglass" : "lock.open")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .contentTransition(.symbolEffect(.replace))
            Text(addressText(tab) ?? "Search or enter address")
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(host == nil ? .secondary : .primary)
                .lineLimit(1)
                .contentTransition(.numericText())
            Spacer(minLength: 0)
            if let storeID = tab?.url.flatMap({ ExtensionPackage.storeID(from: $0.absoluteString) }),
               !ExtensionManager.shared.records.contains(where: { $0.storeID == storeID }) {
                Button {
                    Task {
                        do { try await ExtensionManager.shared.installFromStore(storeID) }
                        catch let e as ExtensionInstallError where e == .cancelled {}
                        catch { browser.showToast("exclamationmark.triangle.fill", error.localizedDescription) }
                    }
                } label: {
                    Label("Add", systemImage: "puzzlepiece.extension.fill").labelStyle(.titleAndIcon)
                        .font(.system(size: 11, weight: .semibold))
                }
                .buttonStyle(.glassProminent).controlSize(.mini)
                .help("Add this extension to Browsi")
                .transition(.scale.combined(with: .opacity))
            }
            if host != nil {
                let blocking = ContentBlocker.shared.isEnabled(for: host)
                Button { browser.toggleBlockingForSelectedSite() } label: {
                    Image(systemName: blocking ? "shield.lefthalf.filled" : "shield.slash")
                        .foregroundStyle(blocking ? AnyShapeStyle(browser.selectedSpace.color) : AnyShapeStyle(.secondary))
                        .contentTransition(.symbolEffect(.replace))
                }
                .buttonStyle(SquishButtonStyle()).padding(-5)
                .help(blocking ? "Trackers blocked — click to allow on this site" : "Blocking paused on this site")

                let starred = browser.library.isBookmarked(tab?.url)
                Button { browser.toggleBookmarkForSelectedTab() } label: {
                    Image(systemName: starred ? "star.fill" : "star")
                        .foregroundStyle(starred ? AnyShapeStyle(.yellow) : AnyShapeStyle(.secondary))
                        .symbolEffect(.bounce, value: starred)
                        .contentTransition(.symbolEffect(.replace))
                }
                .buttonStyle(SquishButtonStyle()).padding(-5)
                .help("Bookmark (⌘D)")
            }
        }
        .font(.system(size: 11))
        .padding(.horizontal, 12)
        .frame(height: 34)
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 11, style: .continuous))
        .scaleEffect(hovering && !Motion.reduceMotion ? 1.015 : 1)
        .animation(Motion.bouncy, value: hovering)
        .onHover { hovering = $0 }
        .contentShape(Rectangle())
        .onTapGesture { withAnimation(Motion.bouncy) { browser.palette = .editCurrent } }
        .animation(Motion.snappy, value: host)
    }

    private func addressText(_ tab: Tab?) -> String? {
        guard let url = tab?.url, tab?.isHome == false else { return nil }
        if Preferences.shared.showFullURL { return url.absoluteString }
        return url.host()?.replacingOccurrences(of: "www.", with: "")
    }
}
