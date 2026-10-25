import SwiftUI

struct SettingsView: View {
    @AppStorage("settingsTab") private var tab = "general"

    var body: some View {
        TabView(selection: $tab) {
            GeneralSettings().tabItem { Label("General", systemImage: "gearshape") }.tag("general")
            PasswordsSettingsView().tabItem { Label("Passwords", systemImage: "key.fill") }.tag("passwords")
            PrivacySettings().tabItem { Label("Privacy", systemImage: "hand.raised.fill") }.tag("privacy")
        }
        .frame(width: 620, height: 460)
    }
}

private struct GeneralSettings: View {
    @Bindable private var prefs = Preferences.shared

    var body: some View {
        Form {
            Picker("Search engine", selection: $prefs.searchEngine) {
                ForEach(SearchEngine.allCases) { Text($0.name).tag($0) }
            }
            Picker("Suspend background tabs after", selection: $prefs.suspendAfterMinutes) {
                Text("5 minutes").tag(5)
                Text("10 minutes").tag(10)
                Text("30 minutes").tag(30)
                Text("1 hour").tag(60)
                Text("Never").tag(0)
            }
            Text("Suspended tabs release their memory and wake up instantly when selected.")
                .font(.caption).foregroundStyle(.secondary)
            Toggle("Animated background", isOn: $prefs.animatedBackground)
        }
        .formStyle(.grouped)
    }
}

private struct PrivacySettings: View {
    @Bindable private var prefs = Preferences.shared

    var body: some View {
        Form {
            Section("Content blocking") {
                Toggle("Block ads and trackers", isOn: $prefs.contentBlockingEnabled)
                if !prefs.blockerAllowlist.isEmpty {
                    ForEach(prefs.blockerAllowlist.sorted(), id: \.self) { host in
                        HStack {
                            Text(host)
                            Spacer()
                            Button("Remove") { prefs.blockerAllowlist.remove(host) }
                        }
                    }
                } else {
                    Text("No sites are excluded from blocking.").foregroundStyle(.secondary)
                }
            }
            Section("Passwords") {
                Toggle("Offer to save passwords", isOn: $prefs.offerToSavePasswords)
                if !prefs.neverSavePasswordHosts.isEmpty {
                    ForEach(prefs.neverSavePasswordHosts.sorted(), id: \.self) { host in
                        HStack {
                            Text("Never save: \(host)")
                            Spacer()
                            Button("Remove") { prefs.neverSavePasswordHosts.remove(host) }
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}
