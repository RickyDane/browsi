import SwiftUI

/// Settings › Watched Pages: pages Browsi re-checks in the background, with their latest change.
struct WatchedPagesPane: View {
    @Environment(BrowserState.self) private var browser
    private let watcher = PageWatcher.shared

    var body: some View {
        Form {
            if watcher.watches.isEmpty {
                Section {
                    ContentUnavailableView {
                        Label("No watched pages", systemImage: "eye")
                    } description: {
                        Text("Open a page and choose **Watch Page for Changes…** in the command palette (⌘K) or the Page menu, then say what to watch for, like “price drops” or “back in stock”. Browsi checks it in the background and notifies you when that changes.")
                    }
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 30)
                }
            } else {
                Section {
                    ForEach(watcher.watches) { w in
                        WatchRow(watch: w, checking: watcher.checking.contains(w.id))
                    }
                } footer: {
                    Text("Pages are loaded in a hidden web view with your cookies, so pages you’re signed in to work too. Apple Intelligence decides whether a change matters (ignoring clocks, counters and ads) and summarizes it on this Mac.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }
}

private struct WatchRow: View {
    @Environment(BrowserState.self) private var browser
    let watch: PageWatch
    let checking: Bool
    @State private var focusDraft = ""
    @FocusState private var editingFocus: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Group {
                    if let icon = FaviconLoader.shared.cached(host: watch.url.host() ?? "") {
                        Image(nsImage: icon).resizable()
                    } else {
                        Image(systemName: "globe").foregroundStyle(.secondary)
                    }
                }
                .frame(width: 16, height: 16)
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 6) {
                        Text(watch.title).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                        if watch.unseen {
                            Circle().fill(Color.accentColor).frame(width: 7, height: 7).help("Changed since you last looked")
                        }
                    }
                    Text(watch.url.host()?.replacingOccurrences(of: "www.", with: "") ?? watch.url.absoluteString)
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                Picker("", selection: Binding(get: { watch.intervalMinutes },
                                              set: { PageWatcher.shared.setInterval($0, for: watch.id) })) {
                    ForEach(PageWatch.intervals, id: \.minutes) { Text($0.name).tag($0.minutes) }
                }
                .labelsHidden()
                .fixedSize()
                Menu {
                    Button("Open Page") { browser.open(url: watch.url, inNewTab: true); PageWatcher.shared.markSeen(watch.url) }
                    Button("Check Now") { Task { await PageWatcher.shared.check(watch.id) } }
                    Divider()
                    Button("Stop Watching", role: .destructive) { PageWatcher.shared.remove(watch.id) }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
            }
            TextField("Watch for", text: $focusDraft, prompt: Text("Any meaningful change"))
                .font(.system(size: 12))
                .focused($editingFocus)
                .onSubmit(commitFocus)
                .onChange(of: editingFocus) { if !$1 { commitFocus() } }
                .onAppear { focusDraft = watch.focus ?? "" }
                .help("What Browsi should notify you about, e.g. “price below $100”")
            if let summary = watch.lastSummary, let changed = watch.lastChanged {
                Label {
                    Text("\(summary)  \(Text("· \(changed.formatted(.relative(presentation: .named)))").foregroundStyle(.secondary))")
                } icon: {
                    Image(systemName: "sparkle").foregroundStyle(browser.selectedSpace.color)
                }
                .font(.system(size: 12))
            }
            HStack(spacing: 6) {
                if checking {
                    ProgressView().controlSize(.mini)
                    Text("Checking…")
                } else if let error = watch.lastError {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    Text(error)
                } else if let checked = watch.lastChecked {
                    Text("Checked \(checked.formatted(.relative(presentation: .named)))")
                } else {
                    Text("Waiting for the first check")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    private func commitFocus() {
        guard focusDraft.trimmingCharacters(in: .whitespacesAndNewlines) != (watch.focus ?? "") else { return }
        PageWatcher.shared.setFocus(focusDraft, for: watch.id)
    }
}
