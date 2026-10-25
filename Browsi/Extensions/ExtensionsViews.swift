import SwiftUI
import UniformTypeIdentifiers
import WebKit

/// One puzzle-piece button in the address bar; extensions live in the popup it opens.
struct ExtensionBarSection: View {
    @Environment(BrowserState.self) private var browser
    @State private var manager = ExtensionManager.shared
    @State private var open = false
    @State private var anchor: CGRect = .zero

    var body: some View {
        let ids = manager.records.filter { $0.enabled && manager.contexts[$0.id] != nil }.map(\.id)
        let badges = ids.compactMap { manager.contexts[$0]?.action(for: browser.selectedTab?.controller)?.badgeText }
            .filter { !$0.isEmpty }
        Button { open.toggle() } label: {
            Image(systemName: ids.isEmpty ? "puzzlepiece.extension" : "puzzlepiece.extension.fill")
                .foregroundStyle(open ? AnyShapeStyle(browser.selectedSpace.color) : AnyShapeStyle(.secondary))
                .overlay(alignment: .topTrailing) {
                    if !badges.isEmpty {
                        Circle().fill(browser.selectedSpace.color).frame(width: 6, height: 6).offset(x: 3, y: -2)
                    }
                }
                .symbolEffect(.bounce, value: open)
        }
        .buttonStyle(SquishButtonStyle()).padding(-5)
        .help("Extensions")
        .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .global) }) { anchor = $0 }
        .popover(isPresented: $open, arrowEdge: .bottom) {
            ExtensionsPopup(ids: ids) { id in
                // Close ours first, then let the extension present its own popup from the same spot.
                manager.actionAnchors[id] = anchor
                open = false
                Task {
                    try? await Task.sleep(for: .milliseconds(180))
                    manager.performAction(id)
                }
            }
            .environment(browser)
        }
    }
}

/// The extensions popup: one row per extension (icon, name, badge); click runs its action.
private struct ExtensionsPopup: View {
    @Environment(BrowserState.self) private var browser
    let ids: [UUID]
    let run: (UUID) -> Void
    @State private var manager = ExtensionManager.shared
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Extensions").font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
                .padding(.horizontal, 14).padding(.top, 12).padding(.bottom, 6)
            if ids.isEmpty {
                Text("No extensions turned on.").font(.system(size: 12)).foregroundStyle(.secondary)
                    .padding(.horizontal, 14).padding(.vertical, 8)
            }
            ForEach(ids, id: \.self) { id in ExtensionPopupRow(id: id) { run(id) } }
            Divider().padding(.vertical, 6)
            Button {
                SettingsPane.open(.extensions, with: openSettings)
            } label: {
                Label("Manage Extensions…", systemImage: "gearshape").frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(SquishButtonStyle())
            .padding(.horizontal, 8).padding(.bottom, 8)
        }
        .frame(width: 260)
    }
}

private struct ExtensionPopupRow: View {
    @Environment(BrowserState.self) private var browser
    let id: UUID
    let action: () -> Void
    @State private var manager = ExtensionManager.shared
    @State private var hovering = false

    var body: some View {
        let _ = manager.actionRevision
        let context = manager.contexts[id]
        let act = context?.action(for: browser.selectedTab?.controller)
        let icon = act?.icon(for: CGSize(width: 20, height: 20)) ?? context?.webExtension.icon(for: CGSize(width: 20, height: 20))
        Button(action: action) {
            HStack(spacing: 10) {
                Group {
                    if let icon { Image(nsImage: icon).resizable().interpolation(.high) }
                    else { Image(systemName: "puzzlepiece.extension.fill").foregroundStyle(.secondary) }
                }
                .frame(width: 20, height: 20)
                Text(manager.displayName(id)).font(.system(size: 13)).lineLimit(1)
                Spacer(minLength: 6)
                if let badge = act?.badgeText, !badge.isEmpty {
                    Text(badge).font(.system(size: 10, weight: .bold)).foregroundStyle(.white)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(browser.selectedSpace.color, in: .capsule)
                }
            }
            .padding(.horizontal, 10).frame(height: 34)
            .background(RoundedRectangle(cornerRadius: 8).fill(.primary.opacity(hovering ? 0.08 : 0)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 4)
        .opacity(act?.isEnabled == false ? 0.5 : 1)
        .onHover { hovering = $0 }
        .contextMenu {
            if context?.optionsPageURL != nil { Button("Options…") { manager.openOptions(id) } }
            Button("Turn Off") { manager.setEnabled(id, false) }
        }
    }
}

private struct ExtensionActionButton: View {
    @Environment(BrowserState.self) private var browser
    @Environment(\.openSettings) private var openSettings
    let id: UUID
    @State private var manager = ExtensionManager.shared

    var body: some View {
        let _ = manager.actionRevision
        let context = manager.contexts[id]
        let action = context?.action(for: browser.selectedTab?.controller)
        let icon = action?.icon(for: CGSize(width: 18, height: 18))
            ?? context?.webExtension.icon(for: CGSize(width: 18, height: 18))
        Button { manager.performAction(id) } label: {
            ZStack(alignment: .topTrailing) {
                Group {
                    if let icon { Image(nsImage: icon).resizable().interpolation(.high) }
                    else { Image(systemName: "puzzlepiece.extension.fill").foregroundStyle(.secondary) }
                }
                .frame(width: 15, height: 15)
                .opacity(action?.isEnabled == false ? 0.4 : 1)
                if let badge = action?.badgeText, !badge.isEmpty {
                    Text(badge).font(.system(size: 8, weight: .bold)).foregroundStyle(.white)
                        .padding(.horizontal, 3).frame(minWidth: 12, minHeight: 12)
                        .background(browser.selectedSpace.color, in: .capsule)
                        .offset(x: 6, y: -5)
                }
            }
        }
        .buttonStyle(SquishButtonStyle())
        .padding(-4)
        .help(action?.label.isEmpty == false ? action!.label : manager.displayName(id))
        .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .global) }) { manager.actionAnchors[id] = $0 }
        .contextMenu {
            if context?.optionsPageURL != nil { Button("Options…") { manager.openOptions(id) } }
            Button("Manage Extensions…") { SettingsPane.open(.extensions, with: openSettings) }
            Divider()
            Button("Turn Off") { manager.setEnabled(id, false) }
        }
    }
}

/// Settings › Extensions.
struct ExtensionsPane: View {
    @Environment(BrowserState.self) private var browser
    @State private var manager = ExtensionManager.shared
    @State private var link = ""
    @State private var error: String?
    @State private var busy: String?
    @State private var storeQuery = ""

    var body: some View {
        Form {
            Section {
                HStack {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Search the Chrome Web Store", text: $storeQuery)
                        .textFieldStyle(.plain)
                        .onSubmit { manager.openStore(search: storeQuery) }
                    Button("Search") { manager.openStore(search: storeQuery) }
                        .disabled(storeQuery.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                Button {
                    manager.openStore()
                } label: {
                    Label("Open Chrome Web Store", systemImage: "bag.fill")
                }
            } header: {
                Text("Extension Store")
            } footer: {
                Text("Results open in a new tab. On an extension’s page, click “Add to Browsi”.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section {
                HStack {
                    TextField("Chrome Web Store link or extension ID", text: $link)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { install(link) }
                    Button("Install") { install(link) }.disabled(link.isEmpty || busy != nil)
                }
                HStack {
                    Button("Install from File or Folder…", action: pickFile)
                    Spacer()
                    if let busy { ProgressView().controlSize(.small); Text(busy).foregroundStyle(.secondary) }
                }
                if let error { Text(error).font(.caption).foregroundStyle(.red) }
            } header: {
                Text("Add Extensions")
            } footer: {
                Text("Browsi runs Chrome and Safari web extensions (Manifest V2 and V3) with WebKit. Some extensions rely on Chrome-only features and may not work fully.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section {
                let found = manager.safariExtensions
                if found.isEmpty {
                    Text("No Safari web extensions found in your Applications folders.").foregroundStyle(.secondary)
                }
                ForEach(found) { info in
                    let record = manager.record(forSafariExtension: info.path)
                    HStack(spacing: 10) {
                        Image(systemName: "safari.fill").frame(width: 22).foregroundStyle(.blue.gradient)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(info.name)
                            Text("from \(info.appName)").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if record?.enabled == true {
                            Label("On", systemImage: "checkmark").font(.caption).foregroundStyle(.green)
                        } else {
                            Button("Turn On") { enableSafari(info.path) }.disabled(busy != nil)
                        }
                    }
                }
                Button("Rescan") { manager.refreshSafariExtensions() }.buttonStyle(.borderless)
            } header: {
                Text("Safari Extensions on This Mac")
            } footer: {
                Text("Safari web extensions installed with their apps (for example from the Mac App Store) can run in Browsi. Features that talk to the extension’s own Mac app (native messaging) aren’t available. Safari content blockers and legacy Safari app extensions can only run in Safari.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Installed") {
                if manager.records.isEmpty {
                    Text("No extensions yet.").foregroundStyle(.secondary)
                }
                ForEach(manager.records) { record in InstalledRow(record: record) }
            }

            Section("Popular") {
                ForEach(ExtensionManager.featured, id: \.id) { item in
                    let installed = manager.records.contains { $0.storeID == item.id }
                    HStack(spacing: 10) {
                        Image(systemName: item.symbol).frame(width: 22).foregroundStyle(.tint)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(item.name)
                            Text(item.blurb).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if installed {
                            Label("Installed", systemImage: "checkmark").labelStyle(.titleAndIcon)
                                .font(.caption).foregroundStyle(.green)
                        } else {
                            Button("Get") { install(item.id) }.disabled(busy != nil)
                        }
                    }
                }
            }
        }
    }

    private func install(_ input: String) {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        error = nil
        busy = "Installing…"
        Task {
            defer { busy = nil }
            do {
                try await manager.install(from: trimmed)
                link = ""
            } catch let e as ExtensionInstallError where e == .cancelled {
            } catch {
                self.error = error.localizedDescription
            }
        }
    }

    private func enableSafari(_ path: String) {
        error = nil
        busy = "Turning on…"
        Task {
            defer { busy = nil }
            do { try await manager.installSafariExtension(at: path) }
            catch let e as ExtensionInstallError where e == .cancelled {}
            catch { self.error = error.localizedDescription }
        }
    }

    private func pickFile() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.zip, .folder, UTType(filenameExtension: "crx") ?? .data]
        panel.message = "Choose an extension (.crx, .zip or an unpacked folder with manifest.json)"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        error = nil
        busy = "Installing…"
        Task {
            defer { busy = nil }
            do { try await manager.installFile(url) }
            catch let e as ExtensionInstallError where e == .cancelled {}
            catch { self.error = error.localizedDescription }
        }
    }
}

private struct InstalledRow: View {
    let record: InstalledExtension
    @State private var manager = ExtensionManager.shared

    var body: some View {
        let context = manager.contexts[record.id]
        let ext = context?.webExtension
        HStack(spacing: 10) {
            Group {
                if let icon = ext?.icon(for: CGSize(width: 28, height: 28)) { Image(nsImage: icon).resizable() }
                else { Image(systemName: "puzzlepiece.extension.fill").resizable().scaledToFit().foregroundStyle(.secondary) }
            }
            .frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(ext?.displayName ?? (record.enabled ? "Loading…" : "Turned off")).font(.system(size: 13, weight: .medium))
                    if record.appexPath != nil {
                        Text("Safari").font(.system(size: 9, weight: .semibold)).padding(.horizontal, 5).padding(.vertical, 1)
                            .background(.blue.opacity(0.18), in: .capsule).foregroundStyle(.blue)
                    }
                    if let v = ext?.displayVersion { Text(v).font(.caption).foregroundStyle(.tertiary) }
                }
                if let err = manager.loadErrors[record.id] ?? context?.errors.first?.localizedDescription {
                    Text(err).font(.caption).foregroundStyle(.red).lineLimit(2)
                } else if let desc = ext?.displayShortName ?? ext?.displayDescription {
                    Text(desc).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer()
            if context?.optionsPageURL != nil {
                Button("Options") { manager.openOptions(record.id) }.buttonStyle(.borderless)
            }
            Toggle("", isOn: Binding(get: { record.enabled }, set: { manager.setEnabled(record.id, $0) }))
                .toggleStyle(.switch).labelsHidden().controlSize(.small)
            Button(role: .destructive) { manager.remove(record.id) } label: { Image(systemName: "trash") }
                .buttonStyle(.borderless)
                .help("Remove")
        }
    }
}

/// Floating "Add to Browsi" banner on Chrome Web Store extension pages.
struct StoreInstallBanner: View {
    @Environment(BrowserState.self) private var browser
    let storeID: String
    let title: String
    @State private var manager = ExtensionManager.shared
    @State private var installing = false

    var body: some View {
        let installed = manager.records.contains { $0.storeID == storeID }
        HStack(spacing: 12) {
            Image(systemName: "puzzlepiece.extension.fill")
                .font(.system(size: 18)).foregroundStyle(browser.selectedSpace.color.gradient)
            VStack(alignment: .leading, spacing: 1) {
                Text(installed ? "Installed in Browsi" : "Add this extension to Browsi")
                    .font(.system(size: 13, weight: .semibold))
                Text(title).font(.system(size: 11.5)).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 12)
            if installed {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).font(.system(size: 18))
                    .transition(.scale.combined(with: .opacity))
            } else if installing {
                ProgressView().controlSize(.small)
            } else {
                Button("Add to Browsi") { install() }
                    .buttonStyle(.glassProminent)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .frame(maxWidth: 460)
        .glassEffect(.regular, in: .rect(cornerRadius: 18, style: .continuous))
        .shadow(color: .black.opacity(0.2), radius: 20, y: 8)
        .animation(Motion.bouncy, value: installed)
        .animation(Motion.snappy, value: installing)
    }

    private func install() {
        installing = true
        Task {
            defer { installing = false }
            do { try await manager.installFromStore(storeID) }
            catch let e as ExtensionInstallError where e == .cancelled {}
            catch { browser.showToast("exclamationmark.triangle.fill", error.localizedDescription) }
        }
    }
}
