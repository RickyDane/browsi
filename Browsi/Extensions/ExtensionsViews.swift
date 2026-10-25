import SwiftUI
import UniformTypeIdentifiers
import WebKit

/// Extension buttons as their own section at the trailing end of the address bar.
/// Shows up to `maxVisible` icons; the rest live in an overflow menu.
struct ExtensionBarSection: View {
    @Environment(BrowserState.self) private var browser
    @State private var manager = ExtensionManager.shared
    var maxVisible = 3

    var body: some View {
        let ids = manager.records.filter { $0.enabled && manager.contexts[$0.id] != nil }.map(\.id)
        if !ids.isEmpty {
            HStack(spacing: 2) {
                Rectangle().fill(.primary.opacity(0.15)).frame(width: 1, height: 16).padding(.horizontal, 4)
                ForEach(ids.prefix(maxVisible), id: \.self) { id in ExtensionActionButton(id: id) }
                if ids.count > maxVisible {
                    Menu {
                        ForEach(ids.dropFirst(maxVisible), id: \.self) { id in
                            Button(manager.displayName(id)) { manager.performAction(id) }
                        }
                        Divider()
                        Button("Manage Extensions…") { SettingsPane.open(.extensions) }
                    } label: {
                        Image(systemName: "ellipsis").font(.system(size: 11, weight: .semibold))
                    }
                    .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
                    .foregroundStyle(.secondary)
                    .help("More extensions")
                }
            }
            .transition(.opacity.combined(with: .scale(scale: 0.8, anchor: .trailing)))
        }
    }
}

private struct ExtensionActionButton: View {
    @Environment(BrowserState.self) private var browser
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
            Button("Manage Extensions…") { SettingsPane.open(.extensions) }
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
                    if let v = ext?.displayVersion { Text(v).font(.caption).foregroundStyle(.tertiary) }
                }
                if let err = manager.loadErrors[record.id] {
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
