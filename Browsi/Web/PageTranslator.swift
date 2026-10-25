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
        if original.allSatisfy(\.isWhitespace) { return original }
        let lead = original.prefix { $0.isWhitespace }
        let trail = String(original.reversed().prefix { $0.isWhitespace }.reversed())
        return lead + translated.trimmingCharacters(in: .whitespacesAndNewlines) + trail
    }

    /// At least two letters in a row from a script with words (excludes IPA marks, single letters, symbols).
    static func hasWords(_ text: String) -> Bool {
        text.contains(/\p{L}{2,}/) && !text.allSatisfy { $0.isWhitespace || $0.isPunctuation || $0.isSymbol || ("\u{0250}"..."\u{02FF}").contains($0) }
    }

    /// Re-joins adjacent translated nodes of a block where translation removed the word gap between them.
    /// French "de l'" + "Allemagne" has no space (elision), but English "of the" + "Germany" needs one.
    /// `nodes` are the final texts in page order; returns them with a space added at a node's end
    /// wherever two letters/digits would otherwise touch and the source had no hyphen or apostrophe there.
    static func fixWordGaps(_ nodes: [String], originals: [String]) -> [String] {
        var out = nodes
        for k in 0..<max(0, out.count - 1) {
            guard let a = out[k].last, let b = out[k + 1].first,
                  a.isLetter || a.isNumber, b.isLetter || b.isNumber else { continue }
            // Only where the original also ended in a separator-less join that elision explains (', ’),
            // or where the original had a space that translation dropped.
            let srcEnd = originals[k].last
            let srcStart = originals[k + 1].first
            let originalHadGap = srcEnd?.isWhitespace == true || srcStart?.isWhitespace == true
            let elision = srcEnd == "'" || srcEnd == "’"
            if originalHadGap || elision { out[k] += " " }
        }
        return out
    }

    /// One block of the page (a paragraph, heading, list item…) as a single string for the translator, with
    /// each text node wrapped in a numbered tag: `<t0>La </t0><t1>Forêt-Noire</t1><t2> est…</t2>`.
    /// Translating whole blocks keeps context ("Rhin" alone comes back as "Nose"); Apple's translator keeps
    /// the tags, so each node gets its own part of the translation and links and formatting survive.
    /// The node text goes in untrimmed, so the translator sees the spaces between words of adjacent nodes;
    /// `preservingWhitespace` then re-applies each original node's own leading and trailing whitespace.
    static func taggedSource(_ texts: [String]) -> String {
        texts.enumerated().map { i, t in "<t\(i)>\(escape(t))</t\(i)>" }.joined()
    }

    /// The translation of each tagged node (node index in the block → text). Nodes whose tag didn't survive are missing.
    /// The translator sometimes drops the very first opening tag or the very last closing tag
    /// (`The </t0><t1>…`, `…<t1>city.`); text before the first closing tag / after the last opening tag
    /// is attributed to those nodes.
    static func parseTagged(_ output: String, count: Int) -> [Int: String] {
        var result: [Int: String] = [:]
        for m in output.matches(of: /<t(\d{1,3})>(.*?)<\/t\1>/.dotMatchesNewlines()) {
            guard let i = Int(m.1), i < count, result[i] == nil else { continue }
            result[i] = unescape(String(m.2))
        }
        // A garbled reply (tags merged or nested) can leave tag fragments inside a node's text.
        // Those nodes are dropped so they get translated on their own instead of showing "</t9><t10>".
        result = result.filter { !$0.value.contains(/<\/?t\d/) }
        if result[0] == nil, let m = output.firstMatch(of: /^(?!\s*<t\d)(.*?)<\/t0>/.dotMatchesNewlines()) {
            let t = unescape(String(m.1))
            if !t.contains(/<\/?t\d/) { result[0] = t }
        }
        let last = count - 1
        if last > 0, result[last] == nil,
           let m = output.firstMatch(of: try! Regex("<t\(last)>((?:(?!</?t\\d).)*)\\s*$").dotMatchesNewlines()) {
            let t = unescape(String(m.output[1].substring ?? ""))
            if !t.contains(/<\/?t\d/) { result[last] = t }
        }
        return result
    }

    static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;")
    }

    static func unescape(_ s: String) -> String {
        s.replacingOccurrences(of: "&lt;", with: "<").replacingOccurrences(of: "&gt;", with: ">").replacingOccurrences(of: "&amp;", with: "&")
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

    /// Collects the page's translatable text nodes, grouped into blocks (the nearest non-inline ancestor:
    /// paragraph, heading, list item, cell…), visible blocks first, and remembers the originals.
    /// Returns `[[nodeIndex…], [text…]]` per block.
    static let collectJS = """
    const st = window.__browsiTx || (window.__browsiTx = { nodes: [], originals: [] });
    const skip = 'script,style,noscript,code,pre,kbd,samp,textarea,svg,math,[translate=no],.notranslate,[contenteditable=""],[contenteditable=true]';
    const inline = new Set(['A','ABBR','B','BDI','BDO','CITE','DATA','DFN','EM','FONT','I','INS','DEL','MARK','Q','S','SMALL',
      'SPAN','STRONG','SUB','SUP','TIME','U','VAR','LABEL','NOBR','WBR','BIG','TT','STRIKE']);
    const walker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT, { acceptNode(n) {
      if (n.__browsiTx !== undefined || !/\\p{L}/u.test(n.nodeValue)) return NodeFilter.FILTER_REJECT;
      const p = n.parentElement;
      if (!p || p.closest(skip)) return NodeFilter.FILTER_REJECT;
      return NodeFilter.FILTER_ACCEPT;
    }});
    const blocks = new Map();
    let n, count = 0;
    while ((n = walker.nextNode()) && count < 6000) {
      const i = st.nodes.length;
      n.__browsiTx = i;
      st.nodes.push(n); st.originals.push(n.nodeValue);
      count++;
      let b = n.parentElement;
      while (b.parentElement && inline.has(b.tagName)) b = b.parentElement;
      let list = blocks.get(b);
      if (!list) { list = []; blocks.set(b, list); }
      list.push(i);
    }
    // Order: visible main content first (what the reader is looking at), then other visible text
    // (navigation, sidebars), then main content further down, then the rest. Translation costs about
    // 2 s per paragraph on-device, so this decides what changes first.
    const mainSel = 'main,article,[role=main],#content,#main,#mw-content-text,.mw-parser-output,.main-content,.entry-content,.post-content';
    const hasMain = !!document.querySelector(mainSel);
    const units = [];
    for (const [el, ids] of blocks) {
      const r = el.getBoundingClientRect();
      const visible = r.bottom > -100 && r.top < innerHeight + 300 && r.width > 0;
      const inMain = hasMain ? !!el.closest(mainSel) : ids.reduce((n, i) => n + st.originals[i].length, 0) >= 80;
      // Within each group, running text (paragraphs, headings, list items) before table cells and the like.
      const prose = /^(P|H[1-6]|LI|BLOCKQUOTE|DD|DT|FIGCAPTION|SUMMARY)$/.test(el.tagName) ? 0 : 1;
      const prio = (visible ? (inMain ? 0 : 2) : (inMain ? 4 : 6)) + prose;
      // Very long blocks are split so one request stays small.
      let part = [], len = 0;
      const flush = () => { if (part.length) units.push({ v: prio, f: part[0], ids: part }); part = []; len = 0; };
      for (const i of ids) {
        const t = st.originals[i];
        if (part.length && (len + t.length > 1500 || part.length >= 40)) flush();
        part.push(i); len += t.length;
      }
      flush();
    }
    units.sort((a, b) => a.v - b.v || a.f - b.f);
    return units.map(u => [u.ids, u.ids.map(i => st.originals[i])]);
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
            let blocks: [(ids: [Int], texts: [String])] = raw.compactMap { unit in
                guard unit.count == 2, let texts = unit[1] as? [String], let rawIDs = unit[0] as? [Any] else { return nil }
                let ids = rawIDs.compactMap { ($0 as? Int) ?? ($0 as? NSNumber)?.intValue }
                return ids.count == texts.count && !ids.isEmpty ? (ids, texts) : nil
            }
            guard !blocks.isEmpty else { state = .translated; return }
            let total = blocks.reduce(0) { $0 + $1.ids.count }
            state = .translating(done: 0, total: total)
            let progress = Progress()
            // Results stream in block by block (~2 s per paragraph on-device) and are applied as they
            // arrive, visible blocks first, instead of waiting for a whole batch.
            for chunk in stride(from: 0, to: blocks.count, by: 40).map({ Array(blocks[$0..<min($0 + 40, blocks.count)]) }) {
                guard !Task.isCancelled, tab.url == url, isBusy else { return }
                progress.untagged = []   // nodes whose tags didn't survive
                try await Self.stream(chunk.enumerated().map {
                    (String($0.offset), TranslationLanguages.taggedSource($0.element.texts))
                }, on: session) { [weak self] key, text in
                    guard let self, !Task.isCancelled, tab.url == url, self.isBusy else { throw CancellationError() }
                    guard let key, let b = Int(key), chunk.indices.contains(b) else { return }
                    let block = chunk[b]
                    var pairs: [[Any]] = []
                    let parsed = TranslationLanguages.parseTagged(text, count: block.texts.count)
                    if parsed.isEmpty, block.texts.count == 1 {
                        pairs.append([block.ids[0], TranslationLanguages.preservingWhitespace(
                            original: block.texts[0], translated: Self.stripTags(text))])
                    } else {
                        // Keep untranslated nodes (lost tags) as they are for now; they're retried on their own.
                        var texts = block.texts
                        for (k, original) in block.texts.enumerated() {
                            if let t = parsed[k] {
                                texts[k] = TranslationLanguages.preservingWhitespace(original: original, translated: t)
                            } else {
                                progress.untagged.append((block.ids[k], original))
                            }
                        }
                        texts = TranslationLanguages.fixWordGaps(texts, originals: block.texts)
                        for k in block.texts.indices where parsed[k] != nil { pairs.append([block.ids[k], texts[k]]) }
                    }
                    _ = try? await webView.callAsyncJavaScript(Self.applyJS, arguments: ["pairs": pairs], contentWorld: .defaultClient)
                    progress.done += block.ids.count
                    self.state = .translating(done: progress.done, total: total)
                }
                let untagged = progress.untagged
                if !untagged.isEmpty {
                    // Fall back to translating those nodes on their own. Pure punctuation/symbols (": ", "/", "»")
                    // and IPA fragments are left as they are rather than sent to the translator.
                    let originals = Dictionary(uniqueKeysWithValues: untagged.map { (String($0.id), $0.text) })
                    let worthTranslating = untagged.filter { TranslationLanguages.hasWords($0.text) }
                    try await Self.stream(worthTranslating.map { (String($0.id), TranslationLanguages.taggedSource([$0.text])) },
                                          on: session) { key, text in
                        guard let key, let i = Int(key), let original = originals[key] else { return }
                        let t = TranslationLanguages.parseTagged(text, count: 1)[0] ?? Self.stripTags(text)
                        let pair: [Any] = [i, TranslationLanguages.preservingWhitespace(original: original, translated: t)]
                        _ = try? await webView.callAsyncJavaScript(Self.applyJS, arguments: ["pairs": [pair]], contentWorld: .defaultClient)
                    }
                }
            }
            state = .translated
        } catch is CancellationError {
            if isBusy { state = .idle }
        } catch {
            state = .failed(Self.describe(error))
        }
    }

    /// Mutable state shared with the streaming callbacks.
    private final class Progress {
        var done = 0
        var untagged: [(id: Int, text: String)] = []
    }

    private static func stripTags(_ text: String) -> String {
        TranslationLanguages.unescape(text.replacing(/<\/?t\d{1,3}>/, with: ""))
    }

    /// Streams translations through the session, calling `each` on the main actor as every result arrives.
    /// Requests are built here so nothing non-Sendable crosses actors.
    nonisolated private static func stream(_ texts: [(id: String, text: String)], on session: TranslationSession,
                                           each: @escaping @MainActor (String?, String) async throws -> Void) async throws {
        let requests = texts.map { TranslationSession.Request(sourceText: $0.text, clientIdentifier: $0.id) }
        for try await response in session.translate(batch: requests) {
            try await each(response.clientIdentifier, response.targetText)
        }
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
