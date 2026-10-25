import SwiftUI

struct PasswordsSettingsView: View {
    @State private var unlocked = false
    @State private var items: [Credential] = []
    @State private var search = ""
    @State private var revealed: [String: String] = [:]
    private let prefs = Preferences.shared

    private var store: KeychainStore { KeychainStore(synchronizable: prefs.syncPasswordsWithICloud) }

    var body: some View {
        Group {
            if unlocked {
                VStack(spacing: 0) {
                    TextField("Search", text: $search).textFieldStyle(.roundedBorder)
                        .padding(12)
                    List {
                        ForEach(filtered) { c in
                            HStack(spacing: 10) {
                                Image(systemName: "key.fill").foregroundStyle(.purple.gradient)
                                VStack(alignment: .leading) {
                                    Text(c.host).font(.headline)
                                    Text(c.username.isEmpty ? "(no username)" : c.username).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(revealed[c.id] ?? "••••••••").font(.system(.body, design: .monospaced))
                                    .textSelection(.enabled)
                                    .contentTransition(.opacity)
                                Button { toggleReveal(c) } label: {
                                    Image(systemName: revealed[c.id] == nil ? "eye" : "eye.slash")
                                }.buttonStyle(.borderless)
                                Button { copy(c) } label: { Image(systemName: "doc.on.doc") }.buttonStyle(.borderless)
                                Button(role: .destructive) { delete(c) } label: { Image(systemName: "trash") }
                                    .buttonStyle(.borderless)
                            }
                            .padding(.vertical, 2)
                        }
                    }
                    .overlay { if filtered.isEmpty { ContentUnavailableView("No Passwords", systemImage: "key") } }
                }
            } else {
                VStack(spacing: 14) {
                    Image(systemName: "lock.shield.fill").font(.system(size: 48)).foregroundStyle(.purple.gradient)
                        .symbolEffect(.pulse)
                    Text("Passwords are locked").font(.title3.weight(.semibold))
                    Button("Unlock with Touch ID") { Task { await unlock() } }.buttonStyle(.glassProminent)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .animation(Motion.smooth, value: unlocked)
        .animation(Motion.snappy, value: revealed)
    }

    private var filtered: [Credential] {
        search.isEmpty ? items : items.filter {
            $0.host.localizedCaseInsensitiveContains(search) || $0.username.localizedCaseInsensitiveContains(search)
        }
    }

    private func unlock() async {
        guard await BiometricGate.shared.authenticate(reason: "view your saved passwords") else { return }
        items = store.accounts()
        unlocked = true
    }

    private func toggleReveal(_ c: Credential) {
        if revealed[c.id] != nil { revealed[c.id] = nil } else { revealed[c.id] = try? store.password(host: c.host, username: c.username) }
    }

    private func copy(_ c: Credential) {
        guard let pw = try? store.password(host: c.host, username: c.username) else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(pw, forType: .string)
    }

    private func delete(_ c: Credential) {
        try? store.delete(host: c.host, username: c.username)
        items = store.accounts()
    }
}
