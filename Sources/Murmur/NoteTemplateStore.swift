import Foundation

/// Restructures a transcript into a specific document shape via the
/// on-device LLM — Murmur's take on Heidi Health's note templates
/// (record a conversation, pick a template, get a structured note).
struct NoteTemplate: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var icon: String
    var instructions: String
    var isBuiltIn = false
    /// Say this phrase at the very start of a dictation to apply the
    /// template automatically, with no clicks. Empty = manual only.
    var voiceTrigger: String = ""
    /// An optional worked input/output pair, appended to `instructions` as a
    /// concrete example. `instructions` states the output *shape* in the
    /// abstract (e.g. "omit Attendees if none are named") — a model can
    /// satisfy that in spirit while still drifting on the specific
    /// formatting; one worked example pins the exact shape down the way an
    /// abstract rule alone doesn't. Optional, not `String = ""`: Swift's
    /// synthesized `Decodable` only tolerates a *missing* JSON key when the
    /// property type is Optional, and `NoteTemplateStore.loadCustom()`
    /// swallows decode failures into an empty array — a non-Optional default
    /// here would silently wipe every custom template the first time it
    /// decoded a `templates.json` written before this field existed.
    var exampleInput: String? = nil
    var exampleOutput: String? = nil

    /// Empty unless both halves of the example are present, so a template
    /// with no example composes into `instructions` unchanged.
    var workedExampleBlock: String {
        guard let input = exampleInput, let output = exampleOutput,
              !input.isEmpty, !output.isEmpty else { return "" }
        return """


            Example — dictated input:
            \(input)

            Correct output:
            \(output)
            """
    }

    static let builtIns: [NoteTemplate] = [
        NoteTemplate(
            name: "Meeting Notes", icon: "person.2.wave.2",
            instructions: """
            Turn this transcript into structured meeting notes with clear \
            sections: Attendees (if named), Key Discussion Points, \
            Decisions Made, and Action Items (who owns what, if stated). \
            Use headings and bullet points. Do not invent information that \
            isn't in the transcript.
            """, isBuiltIn: true, voiceTrigger: "meeting notes",
            // Verified via a true before/after comparison (--edit
            // --template "Meeting Notes" on a no-attendees/no-decision
            // input, several runs each way): without this example the
            // on-device model fabricated an "Attendees" entry from the
            // phrase "nobody really decided anything" and smeared that
            // same phrase across Decisions Made and Action Items too, once
            // even in all three. With it, every run correctly omitted the
            // sections that didn't apply. A clear, reproducible win, not
            // an assumed one — contrast Task List below, which is not.
            exampleInput: """
            Okay so we went over the Q3 roadmap, the API work is going to \
            slip about two weeks because of the auth rewrite, and we \
            decided to just push the launch date instead of cutting scope. \
            Someone needs to update the customer-facing changelog before \
            we tell anyone.
            """,
            exampleOutput: """
            **Key Discussion Points**
            - Q3 roadmap review
            - API work is slipping ~2 weeks due to the auth rewrite

            **Decisions Made**
            - Push the launch date rather than cut scope

            **Action Items**
            - Update the customer-facing changelog before the delay is announced
            """),
        NoteTemplate(
            name: "Summary", icon: "text.line.first.and.arrowtriangle.forward",
            instructions: """
            Summarize this transcript into a short, clear paragraph \
            capturing only the main points. Aim for about a quarter of the \
            original length. No preamble like "This transcript discusses" —
            start directly with the content.
            """, isBuiltIn: true, voiceTrigger: "summarize this"),
        NoteTemplate(
            name: "Email Draft", icon: "envelope",
            instructions: """
            Rewrite this transcript as a clear, professional email. Infer a \
            reasonable subject line, a greeting, well-organized body \
            paragraphs, and a sign-off. Keep the original intent and facts; \
            don't add claims that weren't said.
            """, isBuiltIn: true, voiceTrigger: "email draft"),
        NoteTemplate(
            name: "Task List", icon: "checklist",
            instructions: """
            Extract every task, action item, or to-do mentioned in this \
            transcript into a checklist. One line per task, starting each \
            with "- [ ] ". Include an owner or deadline in parentheses if \
            one was mentioned. If nothing task-like is present, say so \
            plainly instead of inventing tasks.
            """, isBuiltIn: true, voiceTrigger: "task list"),
            // Deliberately no worked example here, unlike Meeting Notes
            // above — tried one (a 3-task input/output pair) and a real
            // before/after comparison (--edit --template "Task List",
            // several runs each way, two-task inputs) showed no
            // improvement: both versions dropped the second task about
            // as often, and the example version failed to apply any
            // checklist formatting at all in roughly half its runs, worse
            // than without it. The underlying two-item drop looks like a
            // pre-existing limitation of the on-device model on this
            // template, not something a worked example fixes — shipping
            // the example anyway would be assuming it helped rather than
            // having verified that it does.
        NoteTemplate(
            name: "Blog Post", icon: "doc.richtext",
            instructions: """
            Turn this transcript into a polished, readable blog-post-style \
            draft: a short engaging opening, organized body with \
            subheadings where natural, and a brief closing. Keep the \
            author's actual points and voice; don't invent new claims.
            """, isBuiltIn: true, voiceTrigger: "blog post"),
    ]
}

enum NoteTemplateStore {
    static var fileURL: URL {
        AppPaths.supportDirectory.appendingPathComponent("templates.json")
    }

    static func loadCustom() -> [NoteTemplate] {
        guard let data = try? Data(contentsOf: fileURL),
              let templates = try? JSONDecoder().decode([NoteTemplate].self, from: data)
        else { return [] }
        return templates
    }

    static func saveCustom(_ templates: [NoteTemplate]) {
        if let data = try? JSONEncoder().encode(templates) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    /// Built-ins first, then the user's own templates.
    static func all() -> [NoteTemplate] {
        NoteTemplate.builtIns + loadCustom()
    }

    /// If `text` opens with a template's voice trigger phrase, returns that
    /// template plus the remaining text with the trigger stripped off.
    /// Requires a real word boundary after the phrase and at least two
    /// words left over, so ordinary sentences that merely start with a
    /// similar word ("Email John about...") don't misfire.
    static func matchVoiceTrigger(in text: String) -> (template: NoteTemplate, remainder: String)? {
        for template in all() {
            let trigger = template.voiceTrigger.trimmingCharacters(in: .whitespaces)
            guard !trigger.isEmpty else { continue }
            let escaped = NSRegularExpression.escapedPattern(for: trigger)
            let pattern = "(?i)^\\s*\(escaped)\\b\\s*[:,\\-—]?\\s*"
            guard let range = text.range(
                of: pattern, options: .regularExpression) else { continue }
            let remainder = String(text[range.upperBound...])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard remainder.split(whereSeparator: { $0.isWhitespace }).count >= 2
            else { continue }
            return (template, remainder)
        }
        return nil
    }

    // MARK: - Self test (matcher)

    static func runSelfTest() -> Bool {
        let cases: [(input: String, expectedName: String?, expectedRemainder: String?)] = [
            ("Meeting notes, we discussed the roadmap and Sarah owns the API work.",
             "Meeting Notes", "we discussed the roadmap and Sarah owns the API work."),
            ("Email draft: thanks for joining the call today, let's follow up Friday.",
             "Email Draft", "thanks for joining the call today, let's follow up Friday."),
            ("Summarize this - the launch moved to October because design slipped.",
             "Summary", "the launch moved to October because design slipped."),
            // Should NOT trigger: real sentence merely starting with a similar word.
            ("Email John about the pricing sheet before tomorrow.", nil, nil),
            // Should NOT trigger: bare trigger with no real content after it.
            ("Task list.", nil, nil),
            ("Just a normal sentence with no trigger phrase at all.", nil, nil),
        ]
        var passed = true
        for testCase in cases {
            let got = matchVoiceTrigger(in: testCase.input)
            let ok: Bool
            if let expectedName = testCase.expectedName {
                ok = got?.template.name == expectedName
                    && got?.remainder == testCase.expectedRemainder
            } else {
                ok = got == nil
            }
            if !ok { passed = false }
            print("\(ok ? "PASS" : "FAIL"): matchVoiceTrigger(\"\(testCase.input)\") " +
                  "= \(got.map { "\($0.template.name) -> \"\($0.remainder)\"" } ?? "nil")")
        }

        func check(_ ok: Bool, _ label: String) {
            if !ok { passed = false }
            print("\(ok ? "PASS" : "FAIL"): \(label)")
        }

        // A template with no example composes unchanged.
        let bare = NoteTemplate(name: "T", icon: "", instructions: "BODY")
        check(bare.workedExampleBlock.isEmpty, "no example -> empty block")
        check(bare.instructions + bare.workedExampleBlock == "BODY",
              "empty block leaves instructions untouched when composed")

        // A template with only one half set still composes as if it had none
        // — a dangling example half is worse than no example at all.
        let halfExample = NoteTemplate(
            name: "T", icon: "", instructions: "BODY", exampleInput: "only input")
        check(halfExample.workedExampleBlock.isEmpty,
              "example with only one half set -> still empty block")

        // Meeting Notes carries a worked example (verified to actually
        // change model behavior, not just assumed to), and it reaches the
        // composed instructions untouched.
        let meetingNotes = NoteTemplate.builtIns.first { $0.name == "Meeting Notes" }!
        check(meetingNotes.exampleInput != nil && meetingNotes.exampleOutput != nil,
              "Meeting Notes has a worked example")
        check((meetingNotes.instructions + meetingNotes.workedExampleBlock)
                .contains(meetingNotes.exampleOutput!),
              "Meeting Notes example output reaches the composed instructions")

        // Task List deliberately ships without one — tested and found not
        // to help (see the comment on its definition above) — so this
        // guards against one silently reappearing half-set later.
        let taskList = NoteTemplate.builtIns.first { $0.name == "Task List" }!
        check(taskList.exampleInput == nil && taskList.exampleOutput == nil,
              "Task List deliberately has no worked example")
        check(taskList.workedExampleBlock.isEmpty,
              "Task List composes with no example block")

        return passed
    }
}

/// Legacy per-app template rule. No longer written; retained so
/// `AppProfileStore` can decode and migrate rules saved by older builds.
struct AppTemplateRule: Codable, Equatable {
    var appName: String
    var templateID: UUID
}
