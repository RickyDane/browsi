import SwiftUI

/// "Sign in with Apple" as a native sheet: Apple's page floats in a compact glass card over the
/// dimmed site, with a Touch ID fill for the saved Apple ID.
struct AppleSignInSheet: View {
    @Environment(BrowserState.self) private var browser
    let sheet: AppleSignInState
    @State private var keyMonitor: Any?

    var body: some View {
        let tab = sheet.tab
        ZStack {
            // Native Cipher already darkens the page by 30%; don't stack another dimming veil.
            Color.black.opacity(browser.calmRipple?.tabID == sheet.source.id ? 0 : 0.32)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture {}   // the page underneath stays inert while signing in
                .transition(.opacity)

            VStack(spacing: 0) {
                header
                ZStack(alignment: .top) {
                    Rectangle().fill(.background)
                    WebViewHost(tab: tab, claim: browser.appleSignIn?.id == sheet.id)
                    ProgressGlow(progress: tab.progress, isLoading: tab.isLoading, tint: .white)
                }
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .padding([.horizontal, .bottom], 8)
            }
            .frame(width: 540)
            .frame(maxHeight: 700)
            .glassEffect(.regular, in: .rect(cornerRadius: 22, style: .continuous))
            .shadow(color: .black.opacity(0.35), radius: 40, y: 18)
            .padding(.vertical, 44)
            .padding(.leading, browser.sidebarVisible ? Preferences.shared.sidebarWidth : 0)
            .transition(BlurScaleTransition(scale: 0.9, blur: 10).combined(with: .offset(y: 24)))
        }
        .onAppear(perform: installKeys)
        .onDisappear { if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }; keyMonitor = nil }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "apple.logo")
                .font(.system(size: 18, weight: .medium))
                .frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 0) {
                Text("Sign in with Apple").font(.system(size: 13, weight: .semibold))
                Text(siteName.map { "Continue to \($0)" } ?? "Apple Account")
                    .font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            if sheet.canFill {
                Button { AppleSignInBridge.shared.fillFromSheet() } label: {
                    Label("Fill with Touch ID", systemImage: "touchid")
                }
                .buttonStyle(.glass)
                .disabled(sheet.isFilling)
                .help("Fill your saved Apple ID after Touch ID or your password")
            }
            Button { browser.cancelAppleSignIn() } label: { Image(systemName: "xmark").frame(width: 14, height: 14) }
                .buttonStyle(.glass)
                .help("Cancel (Esc)")
        }
        .padding(.horizontal, 14)
        .frame(height: 52)
    }

    /// The site asking for the sign-in (the tab under the sheet, before it navigated to Apple).
    private var siteName: String? {
        if sheet.mode == .popup { return sheet.source.url?.host() }
        let host = sheet.source.controller?.webView.backForwardList.backItem?.url.host()
        return AppleSignIn.isAppleHost(host) ? nil : host
    }

    /// Esc cancels — handled here because the web view is first responder.
    private func installKeys() {
        let browser = browser
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let code = event.keyCode
            let handled = MainActor.assumeIsolated { () -> Bool in
                guard browser.appleSignIn != nil, code == 53 else { return false }
                browser.cancelAppleSignIn()
                return true
            }
            return handled ? nil : event
        }
    }
}
