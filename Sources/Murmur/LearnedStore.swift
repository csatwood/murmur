import Foundation

struct LearnedCorrection: Codable, Identifiable, Equatable {
    var id = UUID()
    /// What the recognizer heard.
    var heard: String
    /// What the user actually said.
    var intended: String
    var timesSeen: Int = 1
}

struct LearnedData: Codable {
    var corrections: [LearnedCorrection] = []
    /// Words/phrases the user has taught (used for recognition biasing
    /// even when no correction mapping is needed).
    var terms: [String] = []
}

/// Murmur's pronunciation memory. Populated by the Voice Training page and
/// by corrections the user makes to transcripts in History. Used two ways:
/// 1. `apply(in:)` fixes known mishearings in every transcript.
/// 2. `biasTerms()` feeds the user's vocabulary into the speech model
///    before recognition (AnalysisContext contextual strings).
enum LearnedStore {
    static var fileURL: URL {
        AppPaths.supportDirectory.appendingPathComponent("learned.json")
    }

    static func load() -> LearnedData {
        guard let data = try? Data(contentsOf: fileURL),
              let learned = try? JSONDecoder().decode(LearnedData.self, from: data)
        else { return LearnedData() }
        return learned
    }

    static func save(_ learned: LearnedData) {
        if let data = try? JSONEncoder().encode(learned) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    // MARK: - Recording new knowledge

    /// Adds one mapping (merging duplicates) and remembers the intended term.
    static func add(heard: String, intended: String) {
        let heardTrimmed = normalizePhrase(heard)
        let intendedTrimmed = intended.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isUsefulMapping(heard: heardTrimmed, intended: intendedTrimmed) else {
            addTerm(intendedTrimmed)
            return
        }
        var learned = load()
        if let index = learned.corrections.firstIndex(where: {
            $0.heard.lowercased() == heardTrimmed.lowercased()
                && $0.intended == intendedTrimmed
        }) {
            learned.corrections[index].timesSeen += 1
        } else {
            learned.corrections.append(LearnedCorrection(
                heard: heardTrimmed, intended: intendedTrimmed))
        }
        if learned.corrections.count > 300 {
            learned.corrections.removeFirst(learned.corrections.count - 300)
        }
        appendTerm(intendedTrimmed, to: &learned)
        save(learned)
    }

    /// Remembers a term for recognition biasing without any mapping.
    static func addTerm(_ term: String) {
        let trimmed = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var learned = load()
        appendTerm(trimmed, to: &learned)
        save(learned)
    }

    private static func appendTerm(_ term: String, to learned: inout LearnedData) {
        guard !term.isEmpty,
              !learned.terms.contains(where: { $0.lowercased() == term.lowercased() })
        else { return }
        learned.terms.append(term)
        if learned.terms.count > 300 {
            learned.terms.removeFirst(learned.terms.count - 300)
        }
    }

    /// Learns from a user-corrected transcript: extracts word-level
    /// substitutions and stores each. Returns how many were learned.
    @discardableResult
    static func learn(original: String, corrected: String) -> Int {
        let pairs = extractCorrections(original: original, corrected: corrected)
        for pair in pairs {
            add(heard: pair.heard, intended: pair.intended)
        }
        return pairs.count
    }

    // MARK: - Using the knowledge

    /// Fixes known mishearings (case-insensitive whole phrases, longest
    /// first so overlapping mappings behave predictably) — the user's own
    /// taught corrections, plus Murmur's built-in `DeveloperVocabulary`
    /// ones when `includeDeveloperVocabulary` says this app should get
    /// them. This runs unconditionally after transcription, so unlike
    /// `biasTerms()` it doesn't depend on an ASR engine's prompt-biasing
    /// actually working: it's the one mechanism in this pipeline that can
    /// genuinely guarantee a specific known mishearing gets fixed every
    /// time, since it doesn't care what the model was confident about.
    /// Personal corrections come first so a tie in phrase length resolves
    /// in favor of something this specific user actually taught over a
    /// generic built-in guess.
    ///
    /// No default for `includeDeveloperVocabulary`: every call site has a
    /// bundle ID (or explicitly doesn't) to resolve
    /// `AppProfileStore.developerVocabularyEnabled(forBundleID:)` against,
    /// and a silent default is exactly how `Main.swift`'s CLI debug paths
    /// drifted from the real dictation pipeline once already (they used to
    /// skip Harper entirely) — forcing every caller to pass this
    /// explicitly is what keeps the next new post-processing step from
    /// doing the same.
    ///
    /// `DeveloperVocabulary.fuzzyCorrect(in:)` runs last, after every
    /// exact-phrase correction above: it catches mis-hearing spellings
    /// close enough to a term like "Supabase" to fuzzy-match even when
    /// they're not one of the specific spellings enumerated above, and
    /// running it second means an exact match already found by name isn't
    /// re-examined by the fuzzier, costlier check.
    static func apply(in text: String, includeDeveloperVocabulary: Bool) -> String {
        var result = text
        let personal = load().corrections.map { (heard: $0.heard, intended: $0.intended) }
        let builtIn = includeDeveloperVocabulary ? DeveloperVocabulary.corrections : []
        let corrections = (personal + builtIn)
            .sorted { $0.heard.count > $1.heard.count }
        for correction in corrections {
            let escaped = NSRegularExpression.escapedPattern(for: correction.heard)
            result = result.replacingOccurrences(
                of: "(?i)\\b\(escaped)\\b",
                with: NSRegularExpression.escapedTemplate(for: correction.intended),
                options: .regularExpression)
        }
        if includeDeveloperVocabulary {
            result = DeveloperVocabulary.fuzzyCorrect(in: result)
        }
        return result
    }

    /// Vocabulary handed to the speech model before recognition: Murmur's
    /// own built-in developer vocabulary (when `includeDeveloperVocabulary`
    /// says this app should get it), then taught terms, learned spellings,
    /// dictionary spellings, and snippet triggers — the last four are the
    /// user's own, so they're never gated: only the shared, one-size list
    /// built for coding contexts is.
    ///
    /// Built-in terms go *first*, ahead of the user's own — this is the
    /// opposite of the "personal data should win" instinct, but personal
    /// terms have a second safety net the built-in list doesn't: even a
    /// personal term that gets dropped here for space is still fixed
    /// after the fact by `apply(in:)`'s exact-phrase correction, once it's
    /// actually been learned. The built-in list has no such fallback — if
    /// it doesn't make it into the engine's prompt, it does nothing at
    /// all. Confirmed this mattered in practice: with built-in terms
    /// appended last, 74 raw personal terms+corrections alone already
    /// exceeded the `prefix(60)` cutoff `WhisperEngine`/`WhisperCppEngine`
    /// apply when building the actual prompt string — "Supabase" never
    /// reached Whisper at all, not because it mis-heard it.
    ///
    /// No default for `includeDeveloperVocabulary` — see `apply(in:)`'s
    /// matching note; the same drift risk applies here.
    static func biasTerms(includeDeveloperVocabulary: Bool) -> [String] {
        var terms: [String] = []
        var seen = Set<String>()
        func insert(_ term: String) {
            let trimmed = term.trimmingCharacters(in: .whitespacesAndNewlines)
            let key = trimmed.lowercased()
            guard !trimmed.isEmpty, trimmed.count > 1, !seen.contains(key)
            else { return }
            seen.insert(key)
            terms.append(trimmed)
        }
        if includeDeveloperVocabulary {
            DeveloperVocabulary.terms.forEach(insert)
        }
        let learned = load()
        learned.terms.forEach(insert)
        learned.corrections.map(\.intended).forEach(insert)
        TextFormatter.loadDictionary().values.forEach(insert)
        SnippetStore.load().map(\.trigger).forEach(insert)
        return Array(terms.prefix(300))
    }

    // MARK: - Diff extraction

    /// Word-level diff between the original transcript and the user's
    /// correction. Returns substituted runs (up to 4 words long) as
    /// heard → intended pairs.
    static func extractCorrections(
        original: String, corrected: String) -> [(heard: String, intended: String)] {
        let originalWords = tokenize(original)
        let correctedWords = tokenize(corrected)
        guard !originalWords.isEmpty, !correctedWords.isEmpty else { return [] }

        // Longest common subsequence over normalized tokens.
        let n = originalWords.count
        let m = correctedWords.count
        var lcs = [[Int]](repeating: [Int](repeating: 0, count: m + 1), count: n + 1)
        for i in stride(from: n - 1, through: 0, by: -1) {
            for j in stride(from: m - 1, through: 0, by: -1) {
                if originalWords[i].key == correctedWords[j].key {
                    lcs[i][j] = lcs[i + 1][j + 1] + 1
                } else {
                    lcs[i][j] = max(lcs[i + 1][j], lcs[i][j + 1])
                }
            }
        }

        var pairs: [(heard: String, intended: String)] = []
        var i = 0
        var j = 0
        while i < n, j < m {
            if originalWords[i].key == correctedWords[j].key {
                i += 1
                j += 1
                continue
            }
            // Collect one substituted run on each side.
            var removed: [String] = []
            var added: [String] = []
            while i < n, j < m, originalWords[i].key != correctedWords[j].key {
                if lcs[i + 1][j] >= lcs[i][j + 1] {
                    removed.append(originalWords[i].raw)
                    i += 1
                } else {
                    added.append(correctedWords[j].raw)
                    j += 1
                }
                // A pure insertion or deletion isn't a pronunciation fix.
                if i >= n || j >= m { break }
            }
            if !removed.isEmpty, !added.isEmpty,
               removed.count <= 4, added.count <= 4 {
                let heard = normalizePhrase(removed.joined(separator: " "))
                let intended = added.joined(separator: " ")
                    .trimmingCharacters(in: CharacterSet(charactersIn: " ,"))
                if isUsefulMapping(heard: heard, intended: intended) {
                    pairs.append((heard, intended))
                }
            }
        }
        return pairs
    }

    private static func tokenize(_ text: String) -> [(raw: String, key: String)] {
        text.split(whereSeparator: { $0.isWhitespace }).map { token in
            let raw = String(token)
            let key = raw.lowercased()
                .trimmingCharacters(in: .punctuationCharacters)
            return (raw, key)
        }
    }

    private static func normalizePhrase(_ phrase: String) -> String {
        phrase
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: ".,!?;:"))
    }

    /// Refuses to learn a correction whose *entire* trigger is one
    /// ordinary English word — found by auditing one real user's
    /// accumulated corrections and discovering `up → app`, `there → they`,
    /// `they → here` (the first two chained into `there` becoming
    /// `here`), `weight → white`, `tail → teal`, `whisper → Wispr`, and
    /// `team → theme` had all been learned, apparently from
    /// `extractCorrections` misattributing an edit made *elsewhere* in a
    /// correction round-trip to an unrelated short word it happened to
    /// land near in the diff. Once learned, `apply(in:)` runs
    /// unconditionally on every future dictation with no confidence gate
    /// at all — so a single bad learn silently breaks one of the most
    /// common words in the language, forever, until someone notices (the
    /// user only ever noticed "up").
    ///
    /// `HarperChecker.isKnownEnglishWord` — Harper's own dictionary — is
    /// the check, not a hand-kept list: a proper noun or brand name (the
    /// entire point of this feature) won't be in a general English
    /// dictionary, so genuine corrections pass through untouched, while
    /// real words the audit above found ("team", "whisper", ...) reliably
    /// don't. Confirmed against words this audit wasn't fully sure about
    /// too ("plaintiff", "fireworks", "germany") — all real dictionary
    /// words, all would have been silently corrupted the same way had
    /// they ever been mis-attributed as a correction. A multi-word
    /// `heard` phrase ("super base", "cloud code") doesn't carry this risk
    /// the same way — collision with a common *phrase* is far less likely
    /// than with a common single word — so only single words are checked.
    private static func isUsefulMapping(heard: String, intended: String) -> Bool {
        guard heard.count >= 2, !intended.isEmpty,
              heard.lowercased() != intended.lowercased()
        else { return false }
        if !heard.contains(" "), HarperChecker.isKnownEnglishWord(heard) {
            return false
        }
        return true
    }

    // MARK: - Self test

    static func runSelfTest() -> Bool {
        let cases: [(original: String, corrected: String,
                     expected: [(String, String)])] = [
            ("Send it to Soren today.", "Send it to Søren today.",
             [("Soren", "Søren")]),
            ("The base ten pipeline is fast.", "The Baseten pipeline is fast.",
             [("base ten", "Baseten")]),
            ("Hello world.", "Hello world.", []),
            ("I met so ren and Anna.", "I met Søren and Anna.",
             [("so ren", "Søren")]),
            // Regression case for the audit in `isUsefulMapping`'s doc
            // comment: a one-word diff against an ordinary English word
            // ("team") must not be learned as a correction, unlike the
            // proper-noun cases above.
            ("I need a new team.", "I need a new theme.", []),
        ]
        var passed = true
        for testCase in cases {
            let got = extractCorrections(
                original: testCase.original, corrected: testCase.corrected)
            let ok = got.count == testCase.expected.count
                && zip(got, testCase.expected).allSatisfy {
                    $0.0.heard == $0.1.0 && $0.0.intended == $0.1.1
                }
            if !ok { passed = false }
            print("\(ok ? "PASS" : "FAIL"): diff(\"\(testCase.original)\" → " +
                  "\"\(testCase.corrected)\") = \(got)")
        }
        return passed
    }
}
