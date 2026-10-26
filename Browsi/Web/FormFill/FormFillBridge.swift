import AppKit
import Contacts
import FoundationModels
import WebKit

/// Reads the user's "My Card" from Contacts.
nonisolated enum MeCard {
    static var isAuthorized: Bool { CNContactStore.authorizationStatus(for: .contacts) == .authorized }
    static var canAsk: Bool { CNContactStore.authorizationStatus(for: .contacts) == .notDetermined }

    /// Asks for Contacts access the first time; nil when denied or there is no "My Card".
    static func load() async -> ContactProfile? {
        if canAsk {
            guard (try? await CNContactStore().requestAccess(for: .contacts)) == true else { return nil }
        }
        guard isAuthorized else { return nil }
        return await Task.detached(priority: .userInitiated) { () -> ContactProfile? in
            let keys: [CNKeyDescriptor] = [
                CNContactGivenNameKey, CNContactFamilyNameKey, CNContactOrganizationNameKey, CNContactJobTitleKey,
                CNContactEmailAddressesKey, CNContactPhoneNumbersKey, CNContactPostalAddressesKey,
            ] as [CNKeyDescriptor] + [CNContactFormatter.descriptorForRequiredKeys(for: .fullName)]
            guard let c = try? CNContactStore().unifiedMeContactWithKeys(toFetch: keys) else { return nil }
            return profile(from: c)
        }.value
    }

    static func profile(from c: CNContact) -> ContactProfile {
        func preferred<T>(_ values: [CNLabeledValue<T>], _ labels: [String]) -> T? {
            labels.lazy.compactMap { l in values.first { $0.label == l }?.value }.first ?? values.first?.value
        }
        let address = preferred(c.postalAddresses, [CNLabelHome, CNLabelWork])
        let phone = preferred(c.phoneNumbers, [CNLabelPhoneNumberMobile, CNLabelPhoneNumberiPhone, CNLabelHome])
        let email = preferred(c.emailAddresses, [CNLabelHome, CNLabelWork, CNLabelOther]) as String?
        var countries: [String] = []
        if let address {
            countries.append(address.country)
            let code = address.isoCountryCode.uppercased()
            if !code.isEmpty {
                countries.append(Locale(identifier: "en_US").localizedString(forRegionCode: code) ?? "")
                countries.append(Locale.current.localizedString(forRegionCode: code) ?? "")
                countries.append(code)
            }
        }
        return ContactProfile(
            givenName: c.givenName, familyName: c.familyName,
            fullName: CNContactFormatter.string(from: c, style: .fullName) ?? "",
            email: email ?? "", phone: phone?.stringValue ?? "",
            organization: c.organizationName, jobTitle: c.jobTitle,
            street: address?.street ?? "", city: address?.city ?? "", region: address?.state ?? "",
            postalCode: address?.postalCode ?? "", countries: countries)
    }
}

@Generable(description: "Which contact card value each web form field asks for")
nonisolated struct FormFieldGuesses {
    @Guide(description: "One entry per numbered form field in the list")
    var fields: [FormFieldGuess]
}

@Generable
nonisolated struct FormFieldGuess {
    @Guide(description: "The number of the form field")
    var number: Int
    @Guide(description: "The contact value the field asks for, or none if it asks for something else", .anyOf(FormFieldModel.kinds))
    var kind: String
}

/// Asks the on-device model about fields the keyword rules couldn't place (unusual labels, other languages).
nonisolated enum FormFieldModel {
    static let kinds = ProfileField.allCases.map(\.rawValue) + ["none"]

    static let instructions = """
    You map fields of a web form to values from the user's contact card. For each numbered field, look at its \
    label, name and placeholder and pick the contact value it asks for. Answer "none" when the field asks for \
    anything else (a message, a search, a date, a password, a code, a quantity, a choice) or when you are unsure. \
    Never guess a value for a field that isn't clearly about the person's name, contact details or address.
    """

    static var isAvailable: Bool { SystemLanguageModel.default.availability == .available }

    static func prompt(_ fields: [FormFieldInfo], context: String) -> String {
        var lines = ["Page: \(context.prefix(120))", "Form fields:"]
        for f in fields {
            var parts: [String] = []
            if !f.label.isEmpty { parts.append("label \"\(f.label.prefix(80))\"") }
            if !f.placeholder.isEmpty { parts.append("placeholder \"\(f.placeholder.prefix(60))\"") }
            if !f.name.isEmpty { parts.append("name \"\(f.name.prefix(40))\"") }
            if !f.id.isEmpty, f.id != f.name { parts.append("id \"\(f.id.prefix(40))\"") }
            if f.tag == "select" { parts.append("options: \(f.options.prefix(6).joined(separator: ", "))") }
            lines.append("\(f.index). \(f.tag) \(parts.joined(separator: ", "))")
        }
        return lines.joined(separator: "\n")
    }

    /// Guesses for the given fields; empty on failure or after `timeout`, so filling never hangs.
    static func guess(_ fields: [FormFieldInfo], context: String, timeout: Duration = .seconds(6)) async -> [Int: ProfileField] {
        guard isAvailable, !fields.isEmpty else { return [:] }
        let valid = Set(fields.map(\.index))
        return await withTaskGroup(of: [Int: ProfileField]?.self) { group in
            group.addTask {
                let session = LanguageModelSession(instructions: instructions)
                do {
                    let r = try await session.respond(to: prompt(fields, context: context), generating: FormFieldGuesses.self,
                                                      options: GenerationOptions(temperature: 0))
                    var out: [Int: ProfileField] = [:]
                    for g in r.content.fields where valid.contains(g.number) {
                        if let kind = ProfileField(rawValue: g.kind) { out[g.number] = kind }
                    }
                    return out
                } catch {
                    debugLog("form fill model failed: \(error)")
                    return [:]
                }
            }
            group.addTask { try? await Task.sleep(for: timeout); return nil }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first ?? [:]
        }
    }
}

/// JS ↔ native bridge for filling address and contact forms from "My Card".
/// Lives in the isolated `.defaultClient` world, so pages can't ask for the card themselves; the script only
/// asks after the user picks the card in the dropdown.
final class FormFillBridge: NSObject, WKScriptMessageHandlerWithReply {
    static let handlerName = "browsiFormFill"
    static let shared = FormFillBridge()

    static func userScript() -> WKUserScript? {
        guard let url = Bundle.main.url(forResource: "formfill", withExtension: "js"),
              let src = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        return WKUserScript(source: src, injectionTime: .atDocumentEnd, forMainFrameOnly: false, in: .defaultClient)
    }

    static let contactsIconDataURL = AppIconDataURL.make(bundleIDs: ["com.apple.AddressBook"])

    private var cached: (profile: ContactProfile, at: Date)?

    private func profile() async -> ContactProfile? {
        if let cached, Date().timeIntervalSince(cached.at) < 120 { return cached.profile }
        guard let p = await MeCard.load() else { return nil }
        cached = (p, Date())
        return p
    }

    func userContentController(_ ucc: WKUserContentController, didReceive message: WKScriptMessage,
                               replyHandler: @escaping @MainActor @Sendable (Any?, String?) -> Void) {
        let origin = message.frameInfo.securityOrigin
        let host = origin.host.lowercased()
        let secure = origin.protocol == "https" || host == "localhost" || host == "127.0.0.1"
        guard secure, !host.isEmpty, Preferences.shared.smartFormFill,
              let body = message.body as? [String: Any], let type = body["type"] as? String else {
            replyHandler(nil, nil); return
        }

        switch type {
        case "card":
            // What the dropdown shows. Before access is granted we can only offer the card by name.
            if MeCard.canAsk {
                replyHandler(["label": "Fill with My Card", "detail": "From Contacts", "icon": Self.contactsIconDataURL], nil)
                return
            }
            guard MeCard.isAuthorized else { replyHandler(nil, nil); return }
            Task {
                guard let p = await profile() else { replyHandler(nil, nil); return }
                replyHandler(["label": p.displayName, "detail": p.summary, "icon": Self.contactsIconDataURL], nil)
            }

        case "fill":
            let fields = ((body["fields"] as? [[String: Any]]) ?? []).prefix(60).compactMap(FormFieldInfo.init)
            let context = [message.frameInfo.request.url?.host() ?? host, body["title"] as? String ?? ""].joined(separator: " – ")
            Task {
                guard let p = await profile() else { replyHandler(["fills": [Any](), "denied": true], nil); return }
                var kinds: [Int: ProfileField] = [:]
                var unknown: [FormFieldInfo] = []
                for f in fields {
                    switch FormFieldClassifier.classify(f) {
                    case .field(let kind): kinds[f.index] = kind
                    case .unknown: unknown.append(f)
                    case .excluded: break
                    }
                }
                if !unknown.isEmpty {
                    kinds.merge(await FormFieldModel.guess(unknown, context: context)) { a, _ in a }
                }
                let fills = FormFillPlanner.plan(fields, kinds: kinds, profile: p)
                debugLog("form fill \(host): \(fields.count) fields, \(unknown.count) asked the model, \(fills.count) filled")
                replyHandler(["fills": fills.map { ["i": $0.index, "v": $0.candidates] }], nil)
            }

        default:
            replyHandler(nil, "unknown")
        }
    }
}

/// An app's icon as a PNG data URL, so in-page dropdowns can look like the native AutoFill menu.
enum AppIconDataURL {
    static func make(bundleIDs: [String], size px: Int = 64) -> String {
        let ws = NSWorkspace.shared
        guard let app = bundleIDs.lazy.compactMap({ ws.urlForApplication(withBundleIdentifier: $0) }).first,
              let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px,
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return "" }
        let icon = ws.icon(forFile: app.path)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        icon.draw(in: NSRect(x: 0, y: 0, width: px, height: px))
        NSGraphicsContext.restoreGraphicsState()
        guard let png = rep.representation(using: .png, properties: [:]) else { return "" }
        return "data:image/png;base64," + png.base64EncodedString()
    }
}
