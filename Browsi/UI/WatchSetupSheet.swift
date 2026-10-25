import SwiftUI

/// "Watch This Page": say what to be notified about and how often to check (or edit/stop an existing watch).
struct WatchSetupSheet: View {
    @Environment(BrowserState.self) private var browser
    let setup: WatchSetup
    @State private var focus: String
    @State private var interval: Int
    @FocusState private var fieldFocused: Bool

    init(setup: WatchSetup) {
        self.setup = setup
        _focus = State(initialValue: setup.existing?.focus ?? "")
        _interval = State(initialValue: setup.existing?.intervalMinutes ?? 60)
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.28)
                .ignoresSafeArea()
                .onTapGesture { browser.closeWatchSetup() }

            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 10) {
                    Image(systemName: "eye.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(browser.selectedSpace.color)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(setup.existing == nil ? "Watch This Page" : "Edit Page Watch")
                            .font(.system(size: 14, weight: .semibold))
                        Text(setup.title).font(.system(size: 11.5)).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer()
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("What should Browsi watch for?").font(.system(size: 12.5, weight: .medium))
                    TextField("Any meaningful change", text: $focus, axis: .vertical)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13.5))
                        .lineLimit(1...3)
                        .focused($fieldFocused)
                        .onSubmit(save)
                        .padding(.horizontal, 12).padding(.vertical, 9)
                        .background(.primary.opacity(0.06), in: .rect(cornerRadius: 10, style: .continuous))
                    HStack(spacing: 6) {
                        ForEach(PageWatch.focusSuggestions, id: \.self) { s in
                            Button { focus = s } label: {
                                Text(s)
                                    .font(.system(size: 11, weight: .medium))
                                    .padding(.horizontal, 9).padding(.vertical, 5)
                                    .background(focus == s ? AnyShapeStyle(browser.selectedSpace.color.opacity(0.25))
                                                           : AnyShapeStyle(.primary.opacity(0.06)), in: .capsule)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    Text(SmartSearch.isAvailable
                         ? "For example “price below $100”, “tickets go on sale” or “a new chapter”. Apple Intelligence only notifies you about changes that match."
                         : "Turn on Apple Intelligence to filter by this; until then you’re notified about any change.")
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Picker("Check", selection: $interval) {
                    ForEach(PageWatch.intervals, id: \.minutes) { Text($0.name).tag($0.minutes) }
                }
                .fixedSize()

                HStack {
                    if setup.existing != nil {
                        Button("Stop Watching", role: .destructive) {
                            browser.stopWatching(setup.url)
                            browser.closeWatchSetup()
                        }
                        .buttonStyle(.glass)
                    }
                    Spacer()
                    Button("Cancel") { browser.closeWatchSetup() }
                        .buttonStyle(.glass)
                        .keyboardShortcut(.cancelAction)
                    Button(setup.existing == nil ? "Watch" : "Save", action: save)
                        .buttonStyle(.glassProminent)
                        .keyboardShortcut(.defaultAction)
                }
            }
            .padding(20)
            .frame(width: 480)
            .glassEffect(.regular, in: .rect(cornerRadius: 22, style: .continuous))
            .shadow(color: .black.opacity(0.3), radius: 40, y: 18)
            .padding(.leading, browser.sidebarVisible ? Preferences.shared.sidebarWidth : 0)
            .transition(BlurScaleTransition(scale: 0.9, blur: 8))
        }
        .onAppear { DispatchQueue.main.async { fieldFocused = true } }
    }

    private func save() {
        let watcher = PageWatcher.shared
        let trimmed = focus.trimmingCharacters(in: .whitespacesAndNewlines)
        if let existing = setup.existing {
            watcher.setFocus(trimmed, for: existing.id)
            watcher.setInterval(interval, for: existing.id)
            browser.showToast("eye.fill", "Watch updated")
        } else {
            watcher.add(url: setup.url, title: setup.title, focus: trimmed, intervalMinutes: interval)
            browser.showToast("eye.fill", trimmed.isEmpty ? "Watching for changes" : "Watching for: \(SmartTitler.clip(trimmed, to: 40))")
        }
        browser.closeWatchSetup()
    }
}
