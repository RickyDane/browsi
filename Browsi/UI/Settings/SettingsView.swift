import SwiftUI
import WebKit

enum SettingsPane: String, CaseIterable, Identifiable {
    case general, appearance, tabs, privacy, passwords, extensions, websites, downloads, advanced
    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: "General"
        case .appearance: "Appearance"
        case .tabs: "Tabs & Spaces"
        case .privacy: "Privacy & Security"
        case .passwords: "Passwords"
        case .extensions: "Extensions"
        case .websites: "Websites"
        case .downloads: "Downloads"
        case .advanced: "Advanced"
        }
    }

    var symbol: String {
        switch self {
        case .general: "gearshape.fill"
        case .appearance: "paintbrush.fill"
        case .tabs: "square.stack.fill"
        case .privacy: "hand.raised.fill"
        case .passwords: "key.fill"
        case .extensions: "puzzlepiece.extension.fill"
        case .websites: "globe"
        case .downloads: "arrow.down.circle.fill"
        case .advanced: "wrench.and.screwdriver.fill"
        }
    }

    /// Opens the Settings window on this pane.
    @MainActor static func open(_ pane: SettingsPane) {
        UserDefaults.standard.set(pane.rawValue, forKey: "settingsTab")
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    }

    var color: Color {
        switch self {
        case .general: .gray
        case .appearance: .indigo
        case .tabs: .purple
        case .privacy: .blue
        case .passwords: .orange
        case .extensions: .cyan
        case .websites: .teal
        case .downloads: .green
        case .advanced: .pink
        }
    }
}

/// System-Settings-style preferences window.
struct SettingsView: View {
    @AppStorage("settingsTab") private var selection = SettingsPane.general.rawValue

    var body: some View {
        NavigationSplitView {
            List(SettingsPane.allCases, selection: Binding(
                get: { SettingsPane(rawValue: selection) ?? .general },
                set: { selection = $0?.rawValue ?? SettingsPane.general.rawValue })
            ) { pane in
                Label {
                    Text(pane.title)
                } icon: {
                    Image(systemName: pane.symbol)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 22, height: 22)
                        .background(pane.color.gradient, in: .rect(cornerRadius: 6, style: .continuous))
                }
                .tag(pane)
            }
            .navigationSplitViewColumnWidth(210)
        } detail: {
            Group {
                switch SettingsPane(rawValue: selection) ?? .general {
                case .general: GeneralPane()
                case .appearance: AppearancePane()
                case .tabs: TabsPane()
                case .privacy: PrivacyPane()
                case .passwords: PasswordsPane()
                case .extensions: ExtensionsPane()
                case .websites: WebsitesPane()
                case .downloads: DownloadsPane()
                case .advanced: AdvancedPane()
                }
            }
            .formStyle(.grouped)
            .navigationTitle((SettingsPane(rawValue: selection) ?? .general).title)
        }
        .frame(width: 780, height: 580)
    }
}

/// Footnote shown under settings that only affect newly opened tabs.
private struct NewTabsNote: View {
    var body: some View {
        Text("Applies to newly opened and reloaded tabs.").font(.caption).foregroundStyle(.secondary)
    }
}

// MARK: - General

private struct GeneralPane: View {
    @Bindable private var prefs = Preferences.shared
    @State private var isDefault = false

    var body: some View {
        Form {
            Section {
                HStack {
                    Image(systemName: isDefault ? "checkmark.seal.fill" : "safari")
                        .font(.title2).foregroundStyle(isDefault ? .green : .secondary)
                    VStack(alignment: .leading) {
                        Text(isDefault ? "Browsi is your default browser" : "Browsi is not your default browser")
                        Text("Links from other apps open in a new tab.").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if !isDefault {
                        Button("Make Default") {
                            Task {
                                try? await NSWorkspace.shared.setDefaultApplication(at: Bundle.main.bundleURL,
                                                                                     toOpenURLsWithScheme: "http")
                                refreshDefault()
                            }
                        }
                    }
                }
            }
            Section("Search") {
                Picker("Search engine", selection: $prefs.searchEngine) {
                    ForEach(SearchEngine.allCases) { Text($0.name).tag($0) }
                }
                Toggle(isOn: $prefs.homeSmartAnswers) {
                    Label("Smart answers on the home page (Apple Intelligence)", systemImage: "apple.intelligence")
                }
                .disabled(SmartRenamer.status != .available)
            }
            Section("Startup & Quit") {
                Toggle("Restore spaces and tabs from last session", isOn: $prefs.restoreSession)
                Toggle("Confirm before quitting with multiple tabs open", isOn: $prefs.confirmQuit)
            }
        }
        .onAppear(perform: refreshDefault)
    }

    private func refreshDefault() {
        let handler = NSWorkspace.shared.urlForApplication(toOpen: URL(string: "https://example.com")!)
        isDefault = handler?.standardizedFileURL == Bundle.main.bundleURL.standardizedFileURL
    }
}

// MARK: - Appearance

private struct AppearancePane: View {
    @Bindable private var prefs = Preferences.shared

    var body: some View {
        Form {
            Section("Theme") {
                Picker("Appearance", selection: $prefs.theme) {
                    ForEach(AppTheme.allCases) { Text($0.name).tag($0) }
                }
                .pickerStyle(.segmented)
            }
            Section("Sidebar") {
                LabeledContent("Width") {
                    HStack {
                        Slider(value: $prefs.sidebarWidth, in: 200...380, step: 4)
                        Text("\(Int(prefs.sidebarWidth)) pt").monospacedDigit().foregroundStyle(.secondary)
                            .frame(width: 50, alignment: .trailing)
                    }
                }
                Picker("Tab density", selection: $prefs.tabDensity) {
                    ForEach(TabDensity.allCases) { Text($0.name).tag($0) }
                }
                Toggle("Dim suspended tabs", isOn: $prefs.showSuspendedIndicator)
                Toggle("Show full URL in address bar", isOn: $prefs.showFullURL)
            }
            Section("Window") {
                Toggle("Animated space background", isOn: $prefs.animatedBackground)
                LabeledContent("Background intensity") {
                    Slider(value: $prefs.backgroundIntensity, in: 0.2...1)
                }
                Toggle("Edge-to-edge web content", isOn: $prefs.edgeToEdgeContent)
            }
            Section("Motion") {
                Toggle("Wave impact on “Sign in with Apple” and passkey buttons", isOn: $prefs.loginImpactAnimation)
                Toggle("Reduce animations", isOn: $prefs.reduceAnimations)
                Text("Browsi also follows the system “Reduce motion” accessibility setting.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Tabs

private struct TabsPane: View {
    @Bindable private var prefs = Preferences.shared

    var body: some View {
        Form {
            Section("New Tabs") {
                Picker("Open new tabs at", selection: $prefs.newTabPosition) {
                    ForEach(NewTabPosition.allCases) { Text($0.name).tag($0) }
                }
                Toggle("⌘-click opens links in the background", isOn: $prefs.commandClickOpensInBackground)
                Picker("After closing a tab, select", selection: $prefs.closeTabSelection) {
                    ForEach(CloseTabSelection.allCases) { Text($0.name).tag($0) }
                }
            }
            Section {
                Toggle("Link Peek: ⇧-click a link to preview it", isOn: $prefs.linkPeekEnabled)
                Toggle("Float playing videos when switching tabs", isOn: $prefs.floatingVideoEnabled)
            } header: {
                Text("Browsing")
            } footer: {
                Text("A playing video pops out into a window you can drag and resize. Select its tab again to bring it back.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section {
                Picker("Suspend background tabs after", selection: $prefs.suspendAfterMinutes) {
                    Text("5 minutes").tag(5)
                    Text("10 minutes").tag(10)
                    Text("30 minutes").tag(30)
                    Text("1 hour").tag(60)
                    Text("4 hours").tag(240)
                    Text("Never").tag(0)
                }
            } header: {
                Text("Performance")
            } footer: {
                Text("Suspended tabs release their memory and come back when selected. Tabs playing media are never suspended.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Privacy

private struct PrivacyPane: View {
    @Bindable private var prefs = Preferences.shared
    @Environment(BrowserState.self) private var browser
    @State private var siteCount: Int?
    @State private var confirmClear = false

    var body: some View {
        Form {
            Section("Tracking") {
                Toggle("Block ads and trackers", isOn: $prefs.contentBlockingEnabled)
                if prefs.contentBlockingEnabled {
                    if prefs.blockerAllowlist.isEmpty {
                        Text("No sites are excluded. Use the shield in the address bar to allow a site.")
                            .font(.caption).foregroundStyle(.secondary)
                    } else {
                        ForEach(prefs.blockerAllowlist.sorted(), id: \.self) { host in
                            LabeledContent("Allowed: \(host)") {
                                Button("Remove") { prefs.blockerAllowlist.remove(host) }
                            }
                        }
                    }
                }
            }
            Section {
                Toggle("Upgrade connections to HTTPS", isOn: $prefs.upgradeToHTTPS)
                Toggle("Warn when visiting fraudulent websites", isOn: $prefs.fraudWarnings)
                Toggle("Block pop-up windows", isOn: $prefs.blockPopups)
            } header: {
                Text("Security")
            } footer: {
                NewTabsNote()
            }
            Section("Browsing Data") {
                Toggle("Clear history when Browsi quits", isOn: $prefs.clearHistoryOnQuit)
                LabeledContent("History") {
                    Button("Clear History…") {
                        browser.library.clearHistory()
                        browser.showToast("trash", "History cleared")
                    }
                }
                LabeledContent("Cookies & website data") {
                    HStack {
                        if let siteCount { Text("\(siteCount) sites").foregroundStyle(.secondary) }
                        Button("Remove All…") { confirmClear = true }
                    }
                }
            }
        }
        .task { await countSites() }
        .confirmationDialog("Remove all cookies and website data?", isPresented: $confirmClear) {
            Button("Remove All", role: .destructive) {
                Task {
                    await WKWebsiteDataStore.default().removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(),
                                                                  modifiedSince: .distantPast)
                    await countSites()
                }
            }
        } message: {
            Text("You will be signed out of websites.")
        }
    }

    private func countSites() async {
        siteCount = await WKWebsiteDataStore.default().dataRecords(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes()).count
    }
}

// MARK: - Passwords

private struct PasswordsPane: View {
    @Bindable private var prefs = Preferences.shared
    @State private var showVault = false

    var body: some View {
        Form {
            Section {
                LabeledContent {
                    Button("Show Passwords…") { showVault = true }
                } label: {
                    Label("Saved passwords live in your macOS Keychain", systemImage: "lock.shield.fill")
                }
            }
            PasskeysSection()
            Section("AutoFill") {
                Toggle("Offer to save passwords", isOn: $prefs.offerToSavePasswords)
                Toggle("AutoFill saved passwords", isOn: $prefs.autofillPasswords)
                Toggle("Require Touch ID or password to AutoFill", isOn: $prefs.requireAuthToFill)
                Picker("Stay unlocked for", selection: $prefs.authGracePeriod) {
                    Text("Ask every time").tag(0)
                    Text("1 minute").tag(60)
                    Text("5 minutes").tag(300)
                    Text("15 minutes").tag(900)
                    Text("1 hour").tag(3600)
                }
            }
            Section {
                Toggle("Sync new passwords with iCloud Keychain", isOn: $prefs.syncPasswordsWithICloud)
            } footer: {
                Text("Syncing requires a build signed with an Apple Development team.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Never Saved") {
                if prefs.neverSavePasswordHosts.isEmpty {
                    Text("No excluded websites.").foregroundStyle(.secondary)
                }
                ForEach(prefs.neverSavePasswordHosts.sorted(), id: \.self) { host in
                    LabeledContent(host) {
                        Button("Remove") { prefs.neverSavePasswordHosts.remove(host) }
                    }
                }
            }
        }
        .sheet(isPresented: $showVault) {
            VStack(spacing: 0) {
                PasswordsSettingsView()
                Divider()
                HStack { Spacer(); Button("Done") { showVault = false }.keyboardShortcut(.defaultAction) }
                    .padding(12)
            }
            .frame(width: 640, height: 460)
        }
    }
}

// MARK: - Websites

private struct WebsitesPane: View {
    @Bindable private var prefs = Preferences.shared

    var body: some View {
        Form {
            Section {
                Picker("Default page zoom", selection: $prefs.defaultZoom) {
                    ForEach([0.75, 0.85, 0.9, 1.0, 1.1, 1.15, 1.25, 1.5], id: \.self) { z in
                        Text("\(Int(z * 100)) %").tag(z)
                    }
                }
                Picker("Minimum font size", selection: $prefs.minimumFontSize) {
                    Text("None").tag(0.0)
                    ForEach([9.0, 10, 11, 12, 14, 16, 18], id: \.self) { Text("\(Int($0)) pt").tag($0) }
                }
            } header: {
                Text("Display")
            } footer: {
                NewTabsNote()
            }
            Section {
                Picker("Autoplay", selection: $prefs.autoplay) {
                    ForEach(AutoplayPolicy.allCases) { Text($0.name).tag($0) }
                }
                Toggle("Enable JavaScript", isOn: $prefs.javaScriptEnabled)
            } header: {
                Text("Content")
            } footer: {
                NewTabsNote()
            }
        }
    }
}

// MARK: - Downloads

private struct DownloadsPane: View {
    @Bindable private var prefs = Preferences.shared

    var body: some View {
        Form {
            Section("Location") {
                LabeledContent("Save downloads to") {
                    HStack {
                        Label(DownloadManager.shared.folder.lastPathComponent, systemImage: "folder.fill")
                            .id(prefs.downloadFolderBookmark)
                        Button("Change…") { DownloadManager.shared.chooseFolder() }
                    }
                }
                Toggle("Ask where to save each file", isOn: $prefs.askWhereToSave)
            }
            Section {
                Toggle(isOn: $prefs.smartRenameDownloads) {
                    Label("Smart-rename downloads with Apple Intelligence", systemImage: "apple.intelligence")
                }
                .disabled(SmartRenamer.status != .available)
            } header: {
                Text("Smart Rename")
            } footer: {
                switch SmartRenamer.status {
                case .available:
                    Text("Unclear names like “file_8f3a2c.pdf” are renamed from the source page and the file’s contents, using the on-device model. Nothing leaves your Mac. Not applied when you choose the name yourself.")
                        .font(.caption).foregroundStyle(.secondary)
                case .unavailable(let reason):
                    Text(reason).font(.caption).foregroundStyle(.orange)
                }
            }
            Section("When Done") {
                Toggle("Show downloaded file in Finder", isOn: $prefs.revealDownloads)
            }
        }
    }
}

// MARK: - Advanced

private struct AdvancedPane: View {
    @Bindable private var prefs = Preferences.shared
    @State private var confirmReset = false

    var body: some View {
        Form {
            Section {
                Picker("Identify as", selection: $prefs.userAgentMode) {
                    ForEach(UserAgentMode.allCases) { Text($0.name).tag($0) }
                }
                if prefs.userAgentMode == .custom {
                    TextField("Custom user agent", text: $prefs.customUserAgent, axis: .vertical)
                        .lineLimit(2...4)
                }
                Text(UserAgent.current).font(.caption.monospaced()).foregroundStyle(.secondary).textSelection(.enabled)
            } header: {
                Text("User Agent")
            } footer: {
                Text("Keep “Safari” for best compatibility — Google sign-in may refuse other identities.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section {
                Toggle("Enable Web Inspector (right-click › Inspect Element)", isOn: $prefs.webInspectorEnabled)
            } header: {
                Text("Developer")
            } footer: {
                NewTabsNote()
            }
            Section {
                LabeledContent("Version") {
                    Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "–")
                }
                LabeledContent("WebKit") { Text("Safari \(UserAgent.safariVersion) engine") }
                LabeledContent("Reset") {
                    Button("Reset All Settings…", role: .destructive) { confirmReset = true }
                }
            } header: {
                Text("About")
            }
        }
        .confirmationDialog("Reset all settings to their defaults?", isPresented: $confirmReset) {
            Button("Reset", role: .destructive) { prefs.resetAll() }
        } message: {
            Text("Saved passwords, history, bookmarks and tabs are not affected.")
        }
    }
}

// MARK: - Passkeys

private struct PasskeysSection: View {
    @State private var support = PasskeySupport.shared

    var body: some View {
        Section {
            LabeledContent {
                switch support.status {
                case .notDetermined:
                    Button("Allow…") { Task { await support.requestAuthorizationIfNeeded() } }
                case .denied:
                    Button("Open System Settings") { support.openSystemSettings() }
                default:
                    EmptyView()
                }
            } label: {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Passkeys")
                        Text(support.status.summary).font(.caption).foregroundStyle(color)
                    }
                } icon: {
                    Image(systemName: support.status == .authorized ? "person.badge.key.fill" : "person.badge.key")
                        .foregroundStyle(color)
                        .symbolEffect(.bounce, value: support.status)
                }
            }
            if support.status == .missingEntitlement {
                if support.saved.isEmpty {
                    Text("No passkeys saved yet. Choose “Create a passkey” on a website to add one.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                ForEach(support.saved) { passkey in
                    HStack(spacing: 10) {
                        Image(systemName: "person.badge.key.fill").foregroundStyle(.purple.gradient)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(passkey.rpID).font(.system(size: 12.5, weight: .medium))
                            Text(passkey.label).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(passkey.created, format: .dateTime.day().month().year())
                            .font(.caption).foregroundStyle(.tertiary)
                        Button(role: .destructive) { confirmDelete(passkey) } label: { Image(systemName: "trash") }
                            .buttonStyle(.borderless)
                            .help("Delete passkey")
                    }
                }
            }
        } header: {
            Text("Passkeys")
        } footer: {
            Text(footer).font(.caption).foregroundStyle(.secondary)
        }
        .onAppear { support.refresh(); support.reloadSaved() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            support.refresh()
        }
    }

    private func confirmDelete(_ passkey: Passkey) {
        let alert = NSAlert()
        alert.messageText = "Delete the passkey for \(passkey.label) on \(passkey.rpID)?"
        alert.informativeText = "You won’t be able to sign in with it anymore. Remove it from the website’s security settings too."
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        alert.buttons.first?.hasDestructiveAction = true
        if alert.runModal() == .alertFirstButtonReturn { support.delete(passkey) }
    }

    private var color: Color {
        switch support.status {
        case .authorized: .green
        case .notDetermined: .orange
        case .missingEntitlement: .purple
        case .denied: .red
        }
    }

    private var footer: String {
        switch support.status {
        case .missingEntitlement:
            "Websites can create and use passkeys stored by Browsi in your Keychain, unlocked with Touch ID. They work only in Browsi: iCloud Keychain passkeys and iPhone sign-in need Apple’s browser entitlement (README › Passkeys)."
        case .notDetermined:
            "Websites can create and use passkeys from iCloud Keychain, your iPhone (QR code) and security keys once you allow access."
        case .authorized:
            "Websites can create and use passkeys from iCloud Keychain, password-manager apps, your iPhone (QR code) and security keys."
        case .denied:
            "Turn on Browsi under Privacy & Security › Passkeys Access for Web Browsers."
        }
    }
}
