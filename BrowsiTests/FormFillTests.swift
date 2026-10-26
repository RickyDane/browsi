import Testing
@testable import Browsi

struct FormFillTests {
    private func kind(_ f: FormFieldInfo) -> FormFieldClassifier.Result { FormFieldClassifier.classify(f) }

    @Test func autocompleteWins() {
        #expect(kind(.init(index: 0, autocomplete: "shipping address-line1", name: "foo")) == .field(.addressLine1))
        #expect(kind(.init(index: 0, autocomplete: "given-name", label: "Last name")) == .field(.givenName))
        #expect(kind(.init(index: 0, tag: "textarea", autocomplete: "street-address")) == .field(.streetAddress))
        #expect(kind(.init(index: 0, autocomplete: "cc-number", label: "Name")) == .excluded)
        #expect(kind(.init(index: 0, autocomplete: "off", name: "postcode")) == .field(.postalCode))
    }

    @Test func englishAndGermanKeywords() {
        #expect(kind(.init(index: 0, name: "billingFirstName")) == .field(.givenName))
        #expect(kind(.init(index: 0, label: "Nachname")) == .field(.familyName))
        #expect(kind(.init(index: 0, label: "PLZ")) == .field(.postalCode))
        #expect(kind(.init(index: 0, label: "Straße und Hausnummer")) == .field(.addressLine1))
        #expect(kind(.init(index: 0, label: "Hausnr.")) == .field(.houseNumber))
        #expect(kind(.init(index: 0, label: "Ort")) == .field(.city))
        #expect(kind(.init(index: 0, label: "Email address")) == .field(.email))
        #expect(kind(.init(index: 0, label: "Company name")) == .field(.organization))
        #expect(kind(.init(index: 0, label: "Country/Region")) == .field(.country))
        #expect(kind(.init(index: 0, name: "address_2")) == .field(.addressLine2))
        #expect(kind(.init(index: 0, type: "tel", name: "x1")) == .field(.phone))
    }

    @Test func keepsContactDataOutOfOtherFields() {
        #expect(kind(.init(index: 0, name: "q")) == .excluded)
        #expect(kind(.init(index: 0, label: "Gutscheincode")) == .excluded)
        #expect(kind(.init(index: 0, label: "Coupon code")) == .excluded)
        #expect(kind(.init(index: 0, name: "username")) == .excluded)
        #expect(kind(.init(index: 0, type: "password", name: "name")) == .excluded)
        #expect(kind(.init(index: 0, tag: "textarea", label: "Your message")) == .excluded)
        #expect(kind(.init(index: 0, label: "Wie heißt Ihr Haustier?")) == .unknown)
    }

    @Test func countrySelectRecognizedByOptions() {
        let f = FormFieldInfo(index: 0, tag: "select", name: "sel3", options: ["Choose…", "Deutschland", "Österreich", "Schweiz"])
        #expect(kind(f) == .field(.country))
    }

    @Test func splitsStreetAndNumber() {
        #expect(ContactProfile.splitStreet("Musterstraße 12a") == ("Musterstraße", "12a"))
        #expect(ContactProfile.splitStreet("1 Infinite Loop") == ("Infinite Loop", "1"))
        #expect(ContactProfile.splitStreet("Am Markt 3-5") == ("Am Markt", "3-5"))
        #expect(ContactProfile.splitStreet("Hauptplatz") == ("Hauptplatz", ""))
    }

    @Test func planUsesFormLayout() {
        let p = ContactProfile(givenName: "Erika", familyName: "Mustermann", email: "erika@example.com",
                               street: "Musterstraße 12\n3. OG", city: "Berlin", postalCode: "10115",
                               countries: ["Germany", "Deutschland", "DE"])
        #expect(p.value(.fullName) == "Erika Mustermann")
        #expect(p.value(.addressLine2) == "3. OG")
        #expect(p.summary == "Musterstraße 12, Berlin")

        // German "Vorname" + "Name" + street with a separate house number box.
        let fields = (0..<5).map { FormFieldInfo(index: $0) }
        let kinds: [Int: ProfileField] = [0: .givenName, 1: .fullName, 2: .addressLine1, 3: .houseNumber, 4: .country]
        let plan = FormFillPlanner.plan(fields, kinds: kinds, profile: p)
        #expect(plan.map(\.field) == [.givenName, .familyName, .streetName, .houseNumber, .country])
        #expect(plan[2].candidates == ["Musterstraße"])
        #expect(plan[3].candidates == ["12"])
        #expect(plan[4].candidates == ["Germany", "Deutschland", "DE"])

        // Fields the card has no value for are skipped.
        let none = FormFillPlanner.plan([FormFieldInfo(index: 0)], kinds: [0: .organization], profile: p)
        #expect(none.isEmpty)
    }

    @Test func normalizesCamelCaseAndSeparators() {
        #expect(FormFieldClassifier.normalize("billingFirstName") == "billing first name")
        #expect(FormFieldClassifier.normalize("address_line-2") == "address line 2")
    }
}
