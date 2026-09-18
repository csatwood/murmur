import harper

/// Local grammar checking using the vendored Harper Rust library.
enum HarperChecker {
    /// Protect known vocabulary while applying grammar fixes. Vocabulary is
    /// supplied explicitly so tests do not read the user's dictionaries.
    static func fix(_ text: String, vocabulary: [String] = []) -> String {
        guard !text.isEmpty else { return text }
        let vocabularyText = vocabulary.joined(separator: "\n")
        guard let resultPtr = text.withCString({ textPtr in
            vocabularyText.withCString { vocabPtr in
                harper_fix_text(textPtr, vocabPtr)
            }
        }) else { return text }
        defer { harper_free_string(resultPtr) }
        let fixed = String(cString: resultPtr)
        return fixed.isEmpty ? text : fixed
    }

    /// Dictionary membership is a conservative automatic-learning guard,
    /// not proof that a word cannot also be a person's name or brand.
    static func isKnownEnglishWord(_ word: String) -> Bool {
        word.lowercased().withCString { harper_is_known_word($0) }
    }

    /// Exercises the actual archive linked into the app, including its ABI.
    static func runSelfTest() -> Bool {
        var passed = true
        func check(_ ok: Bool, _ label: String) {
            if !ok { passed = false }
            print("\(ok ? "PASS" : "FAIL"): \(label)")
        }
        let text = "I set up the the database using Supabase yesterday."
        let protected = fix(text, vocabulary: ["Supabase"])
        check(protected.contains("Supabase"), "Harper preserves supplied brand vocabulary")
        check(!protected.contains("the the"), "vocabulary protection retains grammar correction")
        check(fix("I opened Claude Code this morning.", vocabulary: ["Claude Code"])
            .contains("Claude Code"), "Harper protects multiword vocabulary")
        check(fix("").isEmpty, "Harper empty input stays empty")
        check(isKnownEnglishWord("team") && isKnownEnglishWord("TEAM"),
              "automatic learning guard recognizes ordinary words regardless of case")
        check(!isKnownEnglishWord("Supabase"), "unknown brand remains eligible for learning")
        return passed
    }
}
