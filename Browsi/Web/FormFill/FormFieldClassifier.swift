import Foundation

/// A value from the user's contact card that a web form can ask for.
nonisolated enum ProfileField: String, CaseIterable, Codable, Sendable {
    case fullName, givenName, familyName, email, phone, organization, jobTitle
    case streetAddress, addressLine1, addressLine2, streetName, houseNumber
    case city, region, postalCode, country
}

/// What the page tells us about one fillable form control (sent by `formfill.js`).
nonisolated struct FormFieldInfo: Equatable, Sendable {
    var index: Int
    var tag: String = "input"          // input, select, textarea
    var type: String = "text"
    var autocomplete: String = ""
    var name: String = ""
    var id: String = ""
    var label: String = ""
    var placeholder: String = ""
    var options: [String] = []

    init(index: Int, tag: String = "input", type: String = "text", autocomplete: String = "", name: String = "",
         id: String = "", label: String = "", placeholder: String = "", options: [String] = []) {
        self.index = index; self.tag = tag; self.type = type; self.autocomplete = autocomplete; self.name = name
        self.id = id; self.label = label; self.placeholder = placeholder; self.options = options
    }

    init?(_ dict: [String: Any]) {
        guard let index = (dict["i"] as? NSNumber)?.intValue else { return nil }
        func s(_ k: String) -> String { String((dict[k] as? String ?? "").prefix(120)) }
        self.init(index: index, tag: s("tag").lowercased(), type: s("type").lowercased(), autocomplete: s("ac").lowercased(),
                  name: s("name"), id: s("id"), label: s("label"), placeholder: s("ph"),
                  options: ((dict["opts"] as? [String]) ?? []).prefix(40).map { String($0.prefix(60)) })
    }

    /// Everything a human would read to know what the field wants, normalized for keyword matching.
    var descriptor: String { FormFieldClassifier.normalize([label, placeholder, name, id].joined(separator: " ")) }
}

/// Decides which contact value a form field wants, from `autocomplete`, the input type and
/// multilingual keywords (English, German, French, Spanish). Pure, so it is unit tested.
nonisolated enum FormFieldClassifier {
    enum Result: Equatable, Sendable {
        case field(ProfileField)
        /// Looks like a normal text field, but the keywords don't say what for: ask the model.
        case unknown
        /// Something that must never get contact data (search, password, card number, message…).
        case excluded
    }

    static func classify(_ f: FormFieldInfo) -> Result {
        let fillableTypes: Set<String> = ["", "text", "email", "tel", "number", "search", "url"]
        if f.tag == "input", !fillableTypes.contains(f.type) { return .excluded }

        // 1. autocomplete is the site telling us exactly. Tokens may carry a section ("shipping address-line1").
        let tokens = f.autocomplete.split(separator: " ").map(String.init)
        if let token = tokens.last(where: { $0 != "on" && $0 != "off" }) {
            if let field = autocompleteMap[token] {
                return .field(field == .addressLine1 && token == "street-address" && f.tag == "textarea" ? .streetAddress : field)
            }
            if token.hasPrefix("cc-") || excludedAutocomplete.contains(token) { return .excluded }
        }

        let text = f.descriptor
        if matches(exclusions, text) || f.type == "search" { return .excluded }
        if f.type == "email" { return .field(.email) }
        if f.type == "tel" { return .field(.phone) }

        for (pattern, field) in rules where matches(pattern, text) {
            // "Street and house number" is one box for the whole first address line.
            if field == .houseNumber, matches(streetWords, text) { return .field(.addressLine1) }
            if field == .addressLine1, f.tag == "textarea" { return .field(.streetAddress) }
            if field == .fullName, f.tag == "textarea" { return .unknown }
            return .field(field)
        }
        if f.tag == "select" {
            // A list of countries is recognizable by its options alone.
            let countries = ["germany", "deutschland", "united states", "france", "austria", "österreich", "switzerland", "schweiz"]
            if f.options.filter({ countries.contains($0.lowercased().trimmingCharacters(in: .whitespaces)) }).count >= 2 {
                return .field(.country)
            }
        }
        return text.isEmpty || f.tag == "textarea" ? .excluded : .unknown
    }

    /// Splits camelCase and separators so "billingFirstName" and "first_name" both read "billing first name".
    static func normalize(_ s: String) -> String {
        var out = ""
        var prev: Character = " "
        for ch in s {
            if ch.isUppercase, prev.isLowercase { out.append(" ") }
            out.append(ch.isLetter || ch.isNumber ? ch : " ")
            prev = ch
        }
        return out.lowercased().split(separator: " ").joined(separator: " ")
    }

    private static func matches(_ pattern: String, _ text: String) -> Bool {
        text.range(of: pattern, options: .regularExpression) != nil
    }

    private static let autocompleteMap: [String: ProfileField] = [
        "name": .fullName, "given-name": .givenName, "family-name": .familyName,
        "email": .email, "tel": .phone, "tel-national": .phone,
        "organization": .organization, "organization-title": .jobTitle,
        "street-address": .addressLine1, "address-line1": .addressLine1, "address-line2": .addressLine2,
        "address-level2": .city, "address-level1": .region, "postal-code": .postalCode,
        "country": .country, "country-name": .country,
    ]
    private static let excludedAutocomplete: Set<String> = [
        "username", "new-password", "current-password", "one-time-code", "webauthn", "bday", "bday-day",
        "bday-month", "bday-year", "sex", "url", "photo", "transaction-amount", "transaction-currency",
        "additional-name", "honorific-prefix", "honorific-suffix", "nickname", "impp", "language",
    ]

    private static let exclusions = #"\b(search|suche|query|q|captcha|coupon|promo|voucher|gutschein|rabatt|discount|card|karte|kreditkarte|cvv|cvc|csc|iban|bic|swift|password|passwort|user ?name|benutzername|login|otp|verification|code ?verification|message|nachricht|comment|kommentar|subject|betreff|url|website|homepage)\b|gutschein|rabatt|passwort|kennwort|kreditkarte|kartennummer"#

    private static let streetWords = #"\b(street|stra(ss|ß)e|strasse|rue|calle)\b"#

    /// Ordered: specific before generic ("first name" before "name", "email address" before "address").
    private static let rules: [(String, ProfileField)] = [
        (#"\b(full ?name|fullname|vollst[aä]ndiger name|nom complet|nombre completo)\b"#, .fullName),
        (#"\b(e ?mail|email address|courriel|correo)\b"#, .email),
        (#"\b(phone|telephone|tel|telefon|telefonnummer|mobile|mobil|mobilnummer|handy|cell|cellphone|t[eé]l[eé]phone|tel[eé]fono)\b"#, .phone),
        (#"\b(zip|zipcode|postal|post ?code|postcode|plz|postleitzahl|code postal|c[oó]digo postal)\b"#, .postalCode),
        (#"\b(address ?(line)? ?2|addr ?2|street ?2|line 2|apt|apartment|suite|unit|adresszusatz|zusatz|address ?supplement|compl[eé]ment)\b"#, .addressLine2),
        (#"\b(house ?(number|no|nr)|hausnummer|haus ?nr|hnr|street ?number|building ?number|nr)\b"#, .houseNumber),
        (#"\b(company|company name|organi[sz]ation|org|firma|firmenname|unternehmen|employer|soci[eé]t[eé]|empresa)\b"#, .organization),
        (#"\b(job ?title|jobtitle|berufsbezeichnung|beruf|position)\b"#, .jobTitle),
        (#"\b(first ?name|firstname|given ?name|fname|vorname|forename|pr[eé]nom|nombre)\b"#, .givenName),
        (#"\b(last ?name|lastname|surname|family ?name|lname|nachname|familienname|nom de famille|nom|apellidos?)\b"#, .familyName),
        (#"\b(country|countries|land|nation|pays|pa[ií]s)\b"#, .country),
        (#"\b(city|town|ort|stadt|wohnort|locality|suburb|ville|ciudad|localidad)\b"#, .city),
        (#"\b(state|province|region|county|bundesland|kanton|prefecture|provincia)\b"#, .region),
        (#"\b(street|street address|address|addr|address ?line ?1|line 1|stra(ss|ß)e|strasse|adresse|anschrift|rue|direcci[oó]n|calle)\b"#, .addressLine1),
        (#"\b(full ?name|fullname|your name|name|vollst[aä]ndiger name|nom complet|nombre completo)\b"#, .fullName),
    ]
}

/// The user's "My Card" from Contacts, reduced to the values forms ask for.
/// Each field holds candidates: the first is what text fields get, the rest help match `<select>` options
/// (country "Germany" / "DE" / "Deutschland").
nonisolated struct ContactProfile: Equatable, Sendable {
    var values: [ProfileField: [String]]

    init(values: [ProfileField: [String]]) {
        self.values = values.compactMapValues { list in
            let clean = list.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
            var seen = Set<String>()
            let unique = clean.filter { seen.insert($0.lowercased()).inserted }
            return unique.isEmpty ? nil : unique
        }
    }

    init(givenName: String = "", familyName: String = "", fullName: String = "", email: String = "", phone: String = "",
         organization: String = "", jobTitle: String = "", street: String = "", city: String = "", region: String = "",
         postalCode: String = "", countries: [String] = []) {
        let lines = street.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }
        let line1 = lines.first ?? ""
        let (streetName, number) = Self.splitStreet(line1)
        let name = fullName.isEmpty ? [givenName, familyName].filter { !$0.isEmpty }.joined(separator: " ") : fullName
        self.init(values: [
            .fullName: [name], .givenName: [givenName], .familyName: [familyName], .email: [email], .phone: [phone],
            .organization: [organization], .jobTitle: [jobTitle],
            .streetAddress: [lines.joined(separator: "\n")], .addressLine1: [line1],
            .addressLine2: [lines.dropFirst().joined(separator: ", ")],
            .streetName: [streetName], .houseNumber: [number],
            .city: [city], .region: [region], .postalCode: [postalCode], .country: countries,
        ])
    }

    func value(_ field: ProfileField) -> String? { values[field]?.first }

    /// "Musterstraße 12a" → ("Musterstraße", "12a"); "1 Infinite Loop" → ("Infinite Loop", "1").
    static func splitStreet(_ line: String) -> (street: String, number: String) {
        let s = line.trimmingCharacters(in: .whitespaces)
        if let m = s.wholeMatch(of: /(.+?)[ ,]+(\d+[ \-\/]?[a-zA-Z]?(?:[\-\/]\d+[a-zA-Z]?)?)/) {
            return (String(m.1), String(m.2))
        }
        if let m = s.wholeMatch(of: /(\d+[a-zA-Z]?)[ ,]+(.+)/) {
            return (String(m.2), String(m.1))
        }
        return (s, "")
    }

    /// One-line preview for the dropdown, e.g. "Musterstraße 12, Berlin".
    var summary: String {
        let parts = [value(.addressLine1), value(.city)].compactMap { $0 }
        return parts.isEmpty ? (value(.email) ?? value(.phone) ?? "") : parts.joined(separator: ", ")
    }

    var displayName: String { value(.fullName) ?? value(.email) ?? "My Card" }
}

/// Turns per-field classifications into the values to fill.
nonisolated enum FormFillPlanner {
    struct Fill: Equatable, Sendable {
        var index: Int
        var field: ProfileField
        var candidates: [String]
    }

    static func plan(_ fields: [FormFieldInfo], kinds: [Int: ProfileField], profile: ContactProfile) -> [Fill] {
        let present = Set(kinds.values)
        return fields.compactMap { f -> Fill? in
            guard var kind = kinds[f.index] else { return nil }
            // A separate house-number box means the street box wants the street name only.
            if kind == .addressLine1, present.contains(.houseNumber) { kind = .streetName }
            // A single "name" box next to a "last name" box usually means first name ("Name" / "Nachname").
            if kind == .fullName, present.contains(.familyName), !present.contains(.givenName) { kind = .givenName }
            // …and next to a "first name" box ("Vorname" / "Name") it means the family name.
            if kind == .fullName, present.contains(.givenName), !present.contains(.familyName) { kind = .familyName }
            guard let candidates = profile.values[kind] ?? fallback(kind, profile) else { return nil }
            return Fill(index: f.index, field: kind, candidates: candidates)
        }
    }

    private static func fallback(_ kind: ProfileField, _ p: ContactProfile) -> [String]? {
        switch kind {
        case .streetName: p.values[.addressLine1]
        case .streetAddress: p.values[.addressLine1]
        default: nil
        }
    }
}
