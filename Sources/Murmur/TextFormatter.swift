import Foundation

/// Rule-based cleanup of raw transcripts: filler removal, spoken layout
/// commands, full-restart commands ("scratch that"), spacing/
/// capitalization fixes, and personal-dictionary substitutions. Mirrors
/// Wispr Flow's "AI edits" with local rules.
struct TextFormatter {

    /// Filler words removed when they appear as standalone tokens.
    static let fillers: Set<String> = [
        "um", "umm", "uh", "uhh", "uhm", "er", "erm", "ehm", "mhm", "hmm",
    ]

    var dictionary: [String: String]

    init(dictionary: [String: String] = TextFormatter.loadDictionary()) {
        self.dictionary = dictionary
    }

    static var dictionaryURL: URL {
        AppPaths.supportDirectory.appendingPathComponent("dictionary.json")
    }

    static func loadDictionary() -> [String: String] {
        guard let data = try? Data(contentsOf: dictionaryURL),
              let dict = try? JSONDecoder().decode([String: String].self, from: data)
        else { return [:] }
        return dict
    }

    func format(_ raw: String) -> String {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty { return "" }

        text = applyRestartCommands(to: text)
        text = removeFillers(from: text)
        text = applySpokenCommands(to: text)
        text = applyDictionary(to: text)
        text = tidyWhitespaceAndPunctuation(in: text)
        text = capitalizeSentences(in: text)
        text = ensureTerminalPunctuation(in: text)
        return text
    }

    // MARK: - Passes

    /// A full verbal restart — "scratch that," "forget that" — where the
    /// user abandons everything said so far in this dictation and starts
    /// over. Keeps only the text after the *last* such phrase; if nothing
    /// follows it (the dictation ends right on the trigger), leaves the
    /// text untouched rather than returning empty — the user still said
    /// something real, and silently erasing all of it is a worse failure
    /// than leaving an unresolved "scratch that" in the output for them to
    /// delete themselves.
    ///
    /// This is the free, zero-latency slice of what Wispr Flow calls
    /// "Backtrack" — deliberately narrow: each phrase must be its own
    /// clause, followed by a comma/sentence-ending punctuation or the end
    /// of the dictation, so "I need to scratch that itch" or "don't forget
    /// that meeting" (the phrase followed directly by a noun, no clause
    /// boundary) are left alone. What this can't do — an in-place swap
    /// like "5pm, actually 6" → "6pm," or judging whether an unpunctuated
    /// "actually" is a filler or a real correction — needs actual language
    /// understanding, which is what `RewriteEngine`'s rewrite pass is for,
    /// not a regex.
    private static let restartPhrases = [
        "scratch that", "forget that", "disregard that", "ignore that",
        "never mind that",
    ]

    private func applyRestartCommands(to text: String) -> String {
        let escaped = Self.restartPhrases
            .map { NSRegularExpression.escapedPattern(for: $0) }
            .joined(separator: "|")
        let pattern = "(?i)\\b(?:\(escaped))\\b\\s*(?:[,.!?]|$)"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }

        let nsText = text as NSString
        let matches = regex.matches(
            in: text, range: NSRange(location: 0, length: nsText.length))
        guard let last = matches.last else { return text }

        let remainder = nsText
            .substring(from: last.range.location + last.range.length)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return remainder.isEmpty ? text : remainder
    }

    private func removeFillers(from text: String) -> String {
        var result = text
        for filler in Self.fillers {
            // Filler optionally followed by a comma, as its own word.
            let pattern = "(?i)(^|\\s)\(filler)[,.]?(?=\\s|$)"
            result = result.replacingOccurrences(
                of: pattern, with: "$1", options: .regularExpression)
        }
        return result
    }

    private func applySpokenCommands(to text: String) -> String {
        var result = text
        let commands: [(pattern: String, replacement: String)] = [
            ("(?i)[,.]?\\s*\\bnew paragraph[,.]?\\s*", "\n\n"),
            ("(?i)[,.]?\\s*\\bnew ?line[,.]?\\s*", "\n"),
        ]
        for command in commands {
            result = result.replacingOccurrences(
                of: command.pattern, with: command.replacement,
                options: .regularExpression)
        }
        return result
    }

    private func applyDictionary(to text: String) -> String {
        var result = text
        for (spoken, replacement) in dictionary {
            let escaped = NSRegularExpression.escapedPattern(for: spoken)
            result = result.replacingOccurrences(
                of: "(?i)\\b\(escaped)\\b", with: replacement,
                options: .regularExpression)
        }
        return result
    }

    private func tidyWhitespaceAndPunctuation(in text: String) -> String {
        var result = text
        // Collapse runs of spaces/tabs (not newlines).
        result = result.replacingOccurrences(
            of: "[ \\t]+", with: " ", options: .regularExpression)
        // No space before closing punctuation.
        result = result.replacingOccurrences(
            of: " +([,.;:!?])", with: "$1", options: .regularExpression)
        // Collapse duplicate punctuation like ",." or ".." left by edits —
        // but not ".," specifically: an abbreviation's period ("p.m.,")
        // immediately followed by a real, separate comma starting the next
        // clause is not a duplicate to clean up, and the old broader
        // pattern (any of ,.;:!? followed by either , or .) silently
        // deleted that comma. Found because it broke self-correction
        // detection downstream: "5pm, no, actually 6pm" needs that comma
        // to read as one corrected utterance rather than two sentences —
        // collapsing it to "5pm. No, actually 6pm" made the correction
        // pass in RewritePlan treat "No, actually..." as an unrelated new
        // sentence and leave both halves in the output.
        result = result.replacingOccurrences(
            of: ",\\.", with: ".", options: .regularExpression)
        result = result.replacingOccurrences(
            of: "\\.{2,}", with: ".", options: .regularExpression)
        // Trim each line.
        result = result
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .joined(separator: "\n")
        // At most one blank line in a row.
        result = result.replacingOccurrences(
            of: "\n{3,}", with: "\n\n", options: .regularExpression)
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func capitalizeSentences(in text: String) -> String {
        guard !text.isEmpty else { return text }
        var characters = Array(text)
        var capitalizeNext = true
        for index in characters.indices {
            let character = characters[index]
            if capitalizeNext, character.isLetter {
                characters[index] = Character(character.uppercased())
                capitalizeNext = false
            } else if ".!?\n".contains(character) {
                capitalizeNext = true
            } else if !character.isWhitespace, !"\"'([{".contains(character) {
                capitalizeNext = false
            }
        }
        return String(characters)
    }

    private func ensureTerminalPunctuation(in text: String) -> String {
        guard let last = text.last else { return text }
        if last.isLetter || last.isNumber {
            return text + "."
        }
        return text
    }

    // MARK: - Self test

    static func runSelfTest() -> Bool {
        let formatter = TextFormatter(dictionary: ["jira": "Jira", "claude code": "Claude Code"])
        let cases: [(input: String, expected: String)] = [
            ("um hello world", "Hello world."),
            ("this is, uh, a test", "This is, a test."),
            ("first line new line second line", "First line\nSecond line."),
            ("intro new paragraph details here", "Intro\n\nDetails here."),
            ("file a ticket in jira today", "File a ticket in Jira today."),
            ("i use claude code daily", "I use Claude Code daily."),
            ("hello world. this is fine", "Hello world. This is fine."),
            ("  spaced   out   words ", "Spaced out words."),
            ("already punctuated!", "Already punctuated!"),
            ("", ""),
            ("Let's meet at 5pm, no, actually let's do 6pm.",
             "Let's meet at 5pm, no, actually let's do 6pm."),
            ("Wait,. let me think", "Wait. Let me think."),
            ("Sorry.. let me think", "Sorry. Let me think."),
            ("Let's meet Tuesday. Scratch that, Wednesday works better.",
             "Wednesday works better."),
            ("Testing testing, forget that. Let's start over with the real message.",
             "Let's start over with the real message."),
            ("First idea. Scratch that. Second idea. Scratch that. Third idea.",
             "Third idea."),
            ("I need to scratch that itch before we start.",
             "I need to scratch that itch before we start."),
            ("Don't forget that meeting tomorrow.",
             "Don't forget that meeting tomorrow."),
            ("This is a test, actually scratch that",
             "This is a test, actually scratch that."),
        ]
        var passed = true
        for testCase in cases {
            let got = formatter.format(testCase.input)
            let ok = got == testCase.expected
            if !ok { passed = false }
            print("\(ok ? "PASS" : "FAIL"): \"\(testCase.input)\" -> \"\(got)\"" +
                  (ok ? "" : " (expected \"\(testCase.expected)\")"))
        }
        return passed
    }
}
