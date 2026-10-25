import Testing
import Foundation
@testable import Browsi

struct ContentBlockerTests {
    @Test func generatesValidRules() throws {
        let json = ContentBlocker.rulesJSON(domains: ["doubleclick.net", "yandex.ru/ads"])
        let rules = try #require(try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [[String: Any]])
        #expect(rules.count == 3)
        let filter = (rules[0]["trigger"] as? [String: Any])?["url-filter"] as? String
        #expect(filter == #"^https?://([^/]+\.)?doubleclick\.net[:/]"#)
        let re = try Regex(filter!)
        #expect("https://ad.doubleclick.net/x".contains(re))
        #expect(!"https://notdoubleclick.network/".contains(re))
    }

    @Test func bundledListCompiles() async throws {
        let list = await ContentBlocker.shared.load()
        #expect(list != nil)
    }
}
