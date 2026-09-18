import Foundation

// Compile with the real formatter, learning store and Harper wrapper, but
// substitute storage so this suite can never read or change personal data.
enum AppPaths {
    static let supportDirectory: URL = {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("murmur-corrections-" + UUID().uuidString)
        try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()
}

enum SnippetStore {
    struct Snippet { let trigger: String }
    static func load() -> [Snippet] { [] }
}

@main struct CorrectionsHarness {
    static func main() throws {
        defer { try? FileManager.default.removeItem(at: AppPaths.supportDirectory) }
        var passed = TextFormatter.runSelfTest()
        if !LearnedStore.runSelfTest() { passed = false }
        if !HarperChecker.runSelfTest() { passed = false }
        func check(_ ok: Bool, _ label: String) {
            if !ok { passed = false }
            print("\(ok ? "PASS" : "FAIL"): \(label)")
        }

        // Explicit teaching must still support real pronunciation errors
        // that happen to be ordinary words. Exercise storage and application.
        LearnedStore.add(heard: "team", intended: "theme")
        check(LearnedStore.load().corrections.contains { $0.heard == "team" && $0.intended == "theme" },
              "explicit Voice Training still stores a common-word mapping")
        check(LearnedStore.apply(in: "The team is clear.") == "The theme is clear.",
              "explicit mapping still applies")

        let legacy = LearnedData(corrections: [LearnedCorrection(heard: "there", intended: "here")])
        LearnedStore.save(legacy)
        check(LearnedStore.load().corrections == legacy.corrections,
              "existing saved corrections are preserved")
        check(LearnedStore.apply(in: "Put it there today.") == "Put it here today.",
              "existing saved corrections still apply")
        check(LearnedStore.learn(original: "The team is ready.", corrected: "The theme is ready.") == 0,
              "automatic learning refuses a common-word substitution")
        check(LearnedStore.load().corrections == legacy.corrections,
              "rejected automatic learning does not modify existing mappings")

        // Follow the production vocabulary path, testing sources separately.
        LearnedStore.save(LearnedData(terms: ["Supabase"]))
        let sentence = "I set up the the database using Supabase yesterday."
        let learnedResult = HarperChecker.fix(
            TextFormatter(dictionary: [:]).format(sentence), vocabulary: LearnedStore.biasTerms())
        check(learnedResult.contains("Supabase") && !learnedResult.contains("the the"),
              "learned vocabulary reaches Harper without disabling grammar fixes")

        LearnedStore.save(LearnedData())
        try JSONEncoder().encode(["super base": "Supabase"]).write(to: TextFormatter.dictionaryURL)
        let dictionaryResult = HarperChecker.fix(sentence, vocabulary: LearnedStore.biasTerms())
        check(dictionaryResult.contains("Supabase") && !dictionaryResult.contains("the the"),
              "dictionary vocabulary reaches Harper without disabling grammar fixes")

        // Component timing only; no brittle timing assertion in the test suite.
        for vocabulary in [[], ["Supabase"]] as [[String]] {
            _ = HarperChecker.fix(sentence, vocabulary: vocabulary)
            let start = ProcessInfo.processInfo.systemUptime
            for _ in 0..<10 { _ = HarperChecker.fix(sentence, vocabulary: vocabulary) }
            let ms = (ProcessInfo.processInfo.systemUptime - start) * 100
            print("Harper mean ms, vocabulary count \(vocabulary.count): \(ms)")
        }
        exit(passed ? 0 : 1)
    }
}
