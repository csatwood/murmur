import Foundation

struct Snippet: Codable, Identifiable, Equatable {
    var id = UUID()
    /// What you say during dictation.
    var trigger: String
    /// What gets inserted instead (exact casing preserved).
    var expansion: String
    /// How many times this snippet has actually expanded into a real
    /// dictation — incremented by `SnippetStore.expand(in:)`, shown on
    /// each row so a snippet's own real payoff (or lack of one) is
    /// visible, not just guessed at.
    var useCount: Int = 0

    init(id: UUID = UUID(), trigger: String, expansion: String, useCount: Int = 0) {
        self.id = id
        self.trigger = trigger
        self.expansion = expansion
        self.useCount = useCount
    }

    private enum CodingKeys: String, CodingKey { case id, trigger, expansion, useCount }

    /// `useCount` didn't exist before this field shipped — decode it
    /// leniently (defaulting to 0) rather than with the compiler's own
    /// synthesized `Decodable`, which requires every key to be present and
    /// would otherwise fail the *whole array's* decode the moment one
    /// saved snippet predates this field, silently losing every snippet
    /// rather than just starting their counts at zero.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        trigger = try container.decode(String.self, forKey: .trigger)
        expansion = try container.decode(String.self, forKey: .expansion)
        useCount = try container.decodeIfPresent(Int.self, forKey: .useCount) ?? 0
    }
}

/// Voice shortcuts: saying a trigger phrase mid-dictation inserts the saved
/// text block — like Wispr Flow's Snippets.
enum SnippetStore {
    static var fileURL: URL {
        AppPaths.supportDirectory.appendingPathComponent("snippets.json")
    }

    static func load() -> [Snippet] {
        guard let data = try? Data(contentsOf: fileURL),
              let snippets = try? JSONDecoder().decode([Snippet].self, from: data)
        else { return [] }
        return snippets
    }

    static func save(_ snippets: [Snippet]) {
        if let data = try? JSONEncoder().encode(snippets) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    /// Replaces spoken trigger phrases with their expansions, and records a
    /// use against every snippet that actually matched — longest triggers
    /// win so overlapping phrases behave predictably.
    static func expand(in text: String) -> String {
        var result = text
        let snippets = load()
            .filter { !$0.trigger.trimmingCharacters(in: .whitespaces).isEmpty }
            .sorted { $0.trigger.count > $1.trigger.count }
        var matchCounts: [UUID: Int] = [:]
        for snippet in snippets {
            let escaped = NSRegularExpression.escapedPattern(
                for: snippet.trigger.trimmingCharacters(in: .whitespaces))
            // Case-insensitive whole-phrase match; expansion keeps saved casing.
            let pattern = "(?i)\\b\(escaped)\\b"
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let fullRange = NSRange(result.startIndex..., in: result)
            let matches = regex.numberOfMatches(in: result, range: fullRange)
            guard matches > 0 else { continue }
            result = regex.stringByReplacingMatches(
                in: result, range: fullRange,
                withTemplate: NSRegularExpression.escapedTemplate(for: snippet.expansion))
            matchCounts[snippet.id] = matches
        }
        if !matchCounts.isEmpty { recordUsage(matchCounts) }
        return result
    }

    private static func recordUsage(_ matchCounts: [UUID: Int]) {
        var all = load()
        var changed = false
        for index in all.indices {
            if let matches = matchCounts[all[index].id] {
                all[index].useCount += matches
                changed = true
            }
        }
        guard changed else { return }
        save(all)
    }
}
