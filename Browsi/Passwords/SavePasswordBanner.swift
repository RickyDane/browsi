import SwiftUI

struct SavePasswordBanner: View {
    @Environment(BrowserState.self) private var browser
    let offer: PendingPasswordSave
    @State private var keyTurn = false

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().fill(LinearGradient(colors: [.purple, .blue], startPoint: .topLeading, endPoint: .bottomTrailing))
                Image(systemName: "key.fill").foregroundStyle(.white).font(.system(size: 14, weight: .semibold))
                    .rotationEffect(.degrees(keyTurn ? 0 : -45))
            }
            .frame(width: 34, height: 34)

            VStack(alignment: .leading, spacing: 2) {
                Text(offer.isUpdate ? "Update saved password?" : "Save password to Keychain?")
                    .font(.system(size: 13, weight: .semibold))
                Text("\(offer.username.isEmpty ? "(no username)" : offer.username) · \(offer.host)")
                    .font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 12)
            Menu("Not Now") {
                Button("Never for This Website") { browser.resolvePasswordSave(.never) }
            } primaryAction: { browser.resolvePasswordSave(.notNow) }
                .menuStyle(.button).buttonStyle(.glass).fixedSize()
            Button(offer.isUpdate ? "Update" : "Save") { browser.resolvePasswordSave(.save) }
                .buttonStyle(.glassProminent)
                .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .frame(width: 480)
        .glassEffect(.regular, in: .rect(cornerRadius: 18, style: .continuous))
        .shadow(color: .black.opacity(0.18), radius: 20, y: 8)
        .onAppear { withAnimation(Motion.bouncy.delay(0.15)) { keyTurn = true } }
    }
}
