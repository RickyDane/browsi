import Foundation
import NaturalLanguage
import Observation
@preconcurrency import Translation
import WebKit

/// Pure language helpers for page translation (unit tested).
nonisolated enum TranslationLanguages {
    /// The dominant language of `sample`, falling back to the page's `lang` attribute.
    static func detect(sample: String, langAttribute: String?) -> String? {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(String(sample.prefix(4000)))
        if let lang = recognizer.dominantLanguage, lang != .undetermined,
           let confidence = recognizer.languageHypotheses(withMaximum: 1)[lang], confidence > 0.6 {
            return base(lang.rawValue)
        }
        if let attr = langAttribute?.trimmingCharacters(in: .whitespaces), !attr.isEmpty { return base(attr) }
        return nil
    }

    /// "en-US" → "en", "zh-Hant" stays "zh-Hant" (script matters for Chinese).
    static func base(_ code: String) -> String {
        let parts = code.replacingOccurrences(of: "_", with: "-").split(separator: "-").map(String.init)
        guard let first = parts.first?.lowercased() else { return code }
        if first == "zh", parts.count > 1, ["hant", "hans"].contains(parts[1].lowercased()) {
            return "zh-" + parts[1].capitalized
        }
        return first
    }

    /// Whether a page in `language` reads natively for someone with `preferred` languages.
    static func isForeign(_ language: String, preferred: [String]) -> Bool {
        let mine = Set(preferred.map { base($0).split(separator: "-").first.map(String.init) ?? $0 })
        let page = base(language).split(separator: "-").first.map(String.init) ?? language
        return !mine.contains(page)
    }

    /// Re-attaches the original's leading and trailing whitespace to a translated string.
    static func preservingWhitespace(original: String, translated: String) -> String {
        let lead = original.prefix { $0.isWhitespace }
        let trail = String(original.reversed().prefix { $0.isWhitespace }.reversed())
        return lead + translated.trimmingCharacters(in: .whitespacesAndNewlines) + trail
    }

    static func displayName(_ code: String) -> String {
        Locale.current.localizedString(forIdentifier: code) ?? code
    }
}

/// One tab's translation state: the detected language and whether the page is currently translated.
@Observable
final class PageTranslator {
    enum State: Equatable {
        case idle
        case translating(done: Int, total: Int)
        case translated
        case failed(String)
    }

    var state: State = .idle
    /// Detected page language (base code like "fr"); nil until detected or for native pages.
    private(set) var language: String?
    /// The page is in a language other than the user's and can be translated.
    private(set) var offersTranslation = false
    @ObservationIgnored private(set) var detectedURL: URL?

    var isTranslated: Bool { state == .translated }
    var isBusy: Bool { if case .translating = state { true } else { false } }

    static var targetLanguage: Locale.Language {
        Locale.Language(identifier: TranslationLanguages.base(Locale.preferredLanguages.first ?? "en"))
    }

    /// Detects the page's language after a navigation; the translated DOM is gone by then.
    func pageLoaded(_ tab: Tab) async -> Bool {
        state = .idle
        language = nil
        offersTranslation = false
        detectedURL = tab.url
        guard let webView = tab.controller?.webView, tab.url?.scheme?.hasPrefix("http") == true else { return false }
        let js = """
        return { lang: document.documentElement.lang || '', sample: (document.body ? document.body.innerText : '').slice(0, 4000) };
        """
        guard let info = try? await webView.callAsyncJavaScript(js, contentWorld: .defaultClient) as? [String: Any],
              let sample = info["sample"] as? String, sample.count > 80,
              let lang = TranslationLanguages.detect(sample: sample, langAttribute: info["lang"] as? String),
              tab.url == detectedURL else { return false }
        language = lang
        guard TranslationLanguages.isForeign(lang, preferred: Locale.preferredLanguages) else { return false }
        let status = await LanguageAvailability().status(from: Locale.Language(identifier: lang), to: Self.targetLanguage)
        offersTranslation = status != .unsupported
        return offersTranslation
    }

    // MARK: Page scripts

    /// Collects the page's translatable text nodes (visible ones first) and remembers their originals.
    static let collectJS = """
    const st = window.__browsiTx || (window.__browsiTx = { nodes: [], originals: [] });
    const skip = 'script,style,noscript,code,pre,kbd,samp,textarea,svg,math,[translate=no],.notranslate,[contenteditable=""],[contenteditable=true]';
    const walker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT, { acceptNode(n) {
      if (n.__browsiTx !== undefined || !/\\p{L}/u.test(n.nodeValue)) return NodeFilter.FILTER_REJECT;
      const p = n.parentElement;
      if (!p || p.closest(skip)) return NodeFilter.FILTER_REJECT;
      return NodeFilter.FILTER_ACCEPT;
    }});
    const items = [];
    let n;
    while ((n = walker.nextNode()) && items.length < 5000) {
      const i = st.nodes.length;
      n.__browsiTx = i;
      st.nodes.push(n); st.originals.push(n.nodeValue);
      const r = n.parentElement.getBoundingClientRect();
      const visible = r.bottom > -100 && r.top < innerHeight + 300 && r.width > 0;
      items.push({ i, t: n.nodeValue, v: visible ? 0 : 1 });
    }
    items.sort((a, b) => a.v - b.v || a.i - b.i);
    return items.map(x => [x.i, x.t]);
    """

    static let applyJS = """
    const st = window.__browsiTx; if (!st) return 0;
    let n = 0;
    for (const [i, t] of pairs) { const node = st.nodes[i]; if (node) { node.nodeValue = t; n++; } }
    document.documentElement.setAttribute('data-browsi-translated', '1');
    return n;
    """

    static let restoreJS = """
    const st = window.__browsiTx; if (!st) return;
    st.nodes.forEach((node, i) => { node.nodeValue = st.originals[i]; delete node.__browsiTx; });
    window.__browsiTx = undefined;
    document.documentElement.removeAttribute('data-browsi-translated');
    """

    /// Translates the page in place with `session`, visible text first, applying each batch as it arrives.
    func translate(_ tab: Tab, with session: TranslationSession) async {
        guard let webView = tab.controller?.webView else { state = .idle; return }
        let url = tab.url
        do {
            guard let raw = try await webView.callAsyncJavaScript(Self.collectJS, contentWorld: .defaultClient) as? [[Any]] else {
                state = .failed("Couldn’t read this page.")
                return
            }
            let items: [(id: Int, text: String)] = raw.compactMap { pair in
                guard pair.count == 2, let text = pair[1] as? String else { return nil }
                let id = (pair[0] as? Int) ?? (pair[0] as? NSNumber)?.intValue
                return id.map { ($0, text) }
            }
            guard !items.isEmpty else { state = .translated; return }
            state = .translating(done: 0, total: items.count)
            var done = 0
            for chunk in stride(from: 0, to: items.count, by: 40).map({ Array(items[$0..<min($0 + 40, items.count)]) }) {
                guard !Task.isCancelled, tab.url == url, isBusy else { return }
                let responses = try await Self.run(chunk.map { (String($0.id), $0.text) }, on: session)
                let originals = Dictionary(uniqueKeysWithValues: chunk.map { (String($0.id), $0.text) })
                let pairs: [[Any]] = responses.compactMap { r in
                    guard let id = r.id, let original = originals[id], let i = Int(id) else { return nil }
                    return [i, TranslationLanguages.preservingWhitespace(original: original, translated: r.text)]
                }
                _ = try? await webView.callAsyncJavaScript(Self.applyJS, arguments: ["pairs": pairs], contentWorld: .defaultClient)
                done += chunk.count
                state = .translating(done: done, total: items.count)
            }
            state = .translated
        } catch is CancellationError {
            state = .idle
        } catch {
            state = .failed(Self.describe(error))
        }
    }

    /// One batch through the session; requests are built here so nothing non-Sendable crosses actors.
    nonisolated private static func run(_ texts: [(id: String, text: String)], on session: TranslationSession) async throws
        -> [(id: String?, text: String)] {
        let requests = texts.map {
            TranslationSession.Request(sourceText: $0.text.trimmingCharacters(in: .whitespacesAndNewlines), clientIdentifier: $0.id)
        }
        return try await session.translations(from: requests).map { ($0.clientIdentifier, $0.targetText) }
    }

    /// Puts the page's original text back.
    func restore(_ tab: Tab) {
        state = .idle
        guard let webView = tab.controller?.webView else { return }
        Task { _ = try? await webView.callAsyncJavaScript(Self.restoreJS, contentWorld: .defaultClient) }
    }

    private static func describe(_ error: Error) -> String {
        if let e = error as? TranslationError, let reason = e.failureReason ?? e.errorDescription { return reason }
        return "Couldn’t translate this page."
    }
}
