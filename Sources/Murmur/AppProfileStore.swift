import Foundation

/// What Murmur does when you dictate into one particular app.
///
/// This replaces two separate per-app rule systems (`StyleSettings.overrides`
/// and `TemplateSettings.overrides`) that were both keyed by bundle ID and
/// both edited on different pages. Splitting them meant "what happens when I
/// dictate into Slack?" was one question with its answer scattered across
/// two screens — and, worse, a template rule silently suppressed a style
/// rule for the same app with nothing in the UI saying so.
struct AppProfile: Codable, Equatable {
    var appName: String
    /// `nil` inherits the global default tone rather than pinning one, so a
    /// profile created purely to attach a template doesn't have to make a
    /// tone decision it didn't ask to make.
    var style: WritingStyle?
    /// `nil` means no template is auto-applied in this app.
    var templateID: UUID?
    /// `nil` means this profile can only be reached by dictating into the
    /// app itself. Set, it also force-starts a dictation resolved against
    /// this profile from anywhere, via `ProfileHotkeyMonitor`.
    var hotkeySlot: ProfileHotkeySlot?

    /// A profile with none of the three set does nothing; used to prune
    /// empties. A hotkey-only profile (style/template both nil) is still
    /// meaningful — pressing it forces resolution to this bundle ID, which
    /// without a style/template override just falls back to the global
    /// defaults — so it must survive pruning just like the other two halves.
    var isEmpty: Bool { style == nil && templateID == nil && hotkeySlot == nil }
}

enum AppProfileStore {
    private static let defaults = UserDefaults.standard
    private static let key = "appProfiles"
    private static let migratedKey = "appProfilesMigrated"

    /// bundleID → profile.
    static var profiles: [String: AppProfile] {
        get {
            migrateIfNeeded()
            guard let data = defaults.data(forKey: key),
                  let decoded = try? JSONDecoder().decode(
                    [String: AppProfile].self, from: data)
            else { return [:] }
            return decoded
        }
        set {
            // Drop profiles that no longer say anything, so deleting both
            // halves of a rule removes the row instead of leaving a ghost.
            let pruned = newValue.filter { !$0.value.isEmpty }
            if let data = try? JSONEncoder().encode(pruned) {
                defaults.set(data, forKey: key)
            }
        }
    }

    static func profile(forBundleID bundleID: String?) -> AppProfile? {
        guard let bundleID else { return nil }
        return profiles[bundleID]
    }

    /// The tone to use for an app: its own override, else the global default.
    static func style(forBundleID bundleID: String?) -> WritingStyle {
        profile(forBundleID: bundleID)?.style ?? StyleSettings.defaultStyle
    }

    /// The template to auto-apply in an app, resolved against the current
    /// template list (a profile can outlive the template it points at).
    static func template(forBundleID bundleID: String?) -> NoteTemplate? {
        guard let templateID = profile(forBundleID: bundleID)?.templateID
        else { return nil }
        return NoteTemplateStore.all().first { $0.id == templateID }
    }

    // MARK: - Migration

    /// Folds the two legacy rule dictionaries into one profile map, once.
    /// Both are keyed by bundle ID, so an app with a style rule *and* a
    /// template rule becomes a single profile carrying both — which is
    /// exactly the combination the old pipeline couldn't honour.
    private static func migrateIfNeeded() {
        guard !defaults.bool(forKey: migratedKey) else { return }
        defaults.set(true, forKey: migratedKey)

        var styleRules: [String: AppStyleRule] = [:]
        if let data = defaults.data(forKey: "styleOverrides"),
           let legacy = try? JSONDecoder().decode(
            [String: AppStyleRule].self, from: data) {
            styleRules = legacy
        }

        var templateRules: [String: AppTemplateRule] = [:]
        if let data = defaults.data(forKey: "templateOverrides"),
           let legacy = try? JSONDecoder().decode(
            [String: AppTemplateRule].self, from: data) {
            templateRules = legacy
        }

        let merged = merge(styleRules: styleRules, templateRules: templateRules)
        guard !merged.isEmpty else { return }
        if let data = try? JSONEncoder().encode(merged) {
            defaults.set(data, forKey: key)
        }
    }

    /// Pure merge of the two legacy maps, split out so it can be tested
    /// without touching UserDefaults.
    static func merge(
        styleRules: [String: AppStyleRule],
        templateRules: [String: AppTemplateRule]
    ) -> [String: AppProfile] {
        var merged: [String: AppProfile] = [:]
        for (bundleID, rule) in styleRules {
            merged[bundleID] = AppProfile(
                appName: rule.appName, style: rule.style, templateID: nil)
        }
        for (bundleID, rule) in templateRules {
            if var existing = merged[bundleID] {
                existing.templateID = rule.templateID
                merged[bundleID] = existing
            } else {
                merged[bundleID] = AppProfile(
                    appName: rule.appName, style: nil, templateID: rule.templateID)
            }
        }
        return merged.filter { !$0.value.isEmpty }
    }

    // MARK: - Self test

    static func runSelfTest() -> Bool {
        var passed = true
        func check(_ ok: Bool, _ label: String) {
            if !ok { passed = false }
            print("\(ok ? "PASS" : "FAIL"): \(label)")
        }

        // An app configured on BOTH old pages must end up as one profile
        // carrying both halves — the combination the old pipeline dropped.
        let templateID = UUID()
        let merged = merge(
            styleRules: [
                "com.slack": AppStyleRule(appName: "Slack", style: .casual),
                "com.mail": AppStyleRule(appName: "Mail", style: .formal),
            ],
            templateRules: [
                "com.slack": AppTemplateRule(appName: "Slack", templateID: templateID),
                "com.notes": AppTemplateRule(appName: "Notes", templateID: templateID),
            ])
        check(merged.count == 3, "merge unions both maps (got \(merged.count), want 3)")
        check(merged["com.slack"]?.style == .casual
              && merged["com.slack"]?.templateID == templateID,
              "app in both maps keeps style AND template")
        check(merged["com.mail"]?.style == .formal
              && merged["com.mail"]?.templateID == nil,
              "style-only app migrates with no template")
        check(merged["com.notes"]?.style == nil
              && merged["com.notes"]?.templateID == templateID,
              "template-only app inherits default tone (style nil)")

        // Composition: a template must no longer silently discard the tone.
        let template = NoteTemplate(
            name: "T", icon: "", instructions: "STRUCTURE", isBuiltIn: true)
        check(RewritePlan.instructions(template: template, style: .none) == "STRUCTURE",
              "template only = template instructions")
        let both = RewritePlan.instructions(template: template, style: .formal)
        check(both?.contains("STRUCTURE") == true
              && both?.contains("formal") == true,
              "template + tone composes BOTH into one pass")

        // Raw means "don't touch my words at all" — the one case with
        // truly no rewrite pass, regardless of what else is set.
        check(RewritePlan.instructions(template: nil, style: .raw) == nil,
              "Raw never triggers a rewrite pass")
        check(RewritePlan.instructions(template: template, style: .raw) == nil,
              "Raw overrides even an app's own template")

        // Fast dictation skips AI; automatic cleanup remains an explicit opt-in.
        check(RewritePlan.instructions(template: nil, style: .none) == nil,
              "fast dictation skips automatic AI cleanup")
        let cleanupOnly = RewritePlan.instructions(template: nil, style: .none, automaticCleanup: true)
        check(cleanupOnly != nil, "automatic cleanup opt-in runs a cleanup pass")
        check(cleanupOnly?.contains("false starts") == true,
              "default pass targets what TextFormatter's regex can't")
        check(cleanupOnly?.localizedCaseInsensitiveContains("formal") == false
              && cleanupOnly?.localizedCaseInsensitiveContains("casual") == false,
              "cleanup-only pass carries no tone instructions")

        // A tone style still gets the cleanup baseline underneath it, not
        // just the tone instructions alone — the actual gap being closed.
        let toneOnly = RewritePlan.instructions(template: nil, style: .formal)
        check(toneOnly?.contains("false starts") == true
              && toneOnly?.contains(WritingStyle.formal.instructions ?? "\0") == true,
              "tone-only pass composes cleanup baseline + tone, not tone alone")

        // Voice profile colours an existing pass but never creates one.
        let voice = VoiceProfile(
            title: "Habit Architect", summary: "Detailed and precise.",
            traits: ["Detailed", "Frequent pauses"], wordCountAtGeneration: 100)
        check(RewritePlan.instructions(template: nil, style: .none, voice: voice) == nil,
              "voice profile alone does not enable AI in fast dictation")
        check(RewritePlan.instructions(template: template, style: .raw, automaticCleanup: true) == nil,
              "Raw still skips AI when automatic cleanup is enabled")
        check(RewritePlan.instructions(template: nil, style: .raw, voice: voice) == nil,
              "voice never overrides Raw into running a pass")
        let voiced = RewritePlan.instructions(
            template: nil, style: .formal, voice: voice)
        check(voiced?.contains("Detailed and precise.") == true
              && voiced?.contains("Frequent pauses") == true,
              "voice profile summary + traits reach the instructions")

        return passed
    }
}

// MARK: - Instruction composition

enum RewritePlan {
    /// The optional baseline pass for As spoken dictation. `TextFormatter` already strips a fixed list of standalone
    /// filler tokens ("um", "uh", …) deterministically before this ever
    /// runs — this covers what regex can't: phrasal filler ("you know",
    /// "like", "I mean"), false starts and self-corrections, stumbled or
    /// repeated words, actual grammar, and rambling that needs restructuring
    /// rather than just trimming. Previously "As spoken" meant *no* rewrite
    /// pass ran at all; this is what makes it mean "cleaned up, same
    /// register" instead — the gap between the deterministic formatter and
    /// an explicit Style/Template.
    private static let cleanupInstructions = """
        Clean up this dictated transcript: remove verbal filler and false \
        starts ("you know", "like", "I mean", self-corrections, stumbled or \
        repeated words), fix grammar and punctuation, and tighten rambling \
        or run-on phrasing into clear, well-formed sentences. Preserve the \
        speaker's meaning, facts, and intent exactly — do not add \
        information that wasn't said, and do not change their tone unless \
        instructed to below. This is light editing, not rewriting: keep the \
        same paragraph breaks as the original (do not add new ones, and do \
        not add quotation marks, headings, or any other formatting the \
        speaker didn't ask for), and output a plain continuation of their \
        sentences, never a description or restructuring of what they said.
        """

    /// Builds the single instruction string for a dictation's rewrite pass.
    ///
    /// The old pipeline ran template *or* style and never both: if an app
    /// had an auto-template, its style was quietly discarded. Composing the
    /// two into one instruction keeps both effects — the template governs
    /// structure, the style governs tone — without paying for a second
    /// round-trip through the model.
    ///
    /// Raw always skips AI. As spoken without a template also skips AI
    /// unless automatic cleanup is enabled. Explicit tones and templates
    /// retain their single combined rewrite pass.
    ///
    /// Template instructions are deliberately left as the sole primary
    /// instruction when a template is set, rather than layered under the
    /// cleanup baseline too — they already imply clean output as a side
    /// effect of restructuring into a specific shape, and demoting a
    /// carefully-worded template instruction to an "additionally" clause
    /// under a generic preamble risks the model weighting it less.
    ///
    /// `voice` is the user's generated Voice Profile. It never triggers a
    /// pass on its own — Raw is unaffected by it either way — it only
    /// colours a pass that was already going to happen.
    static func instructions(
        template: NoteTemplate?, style: WritingStyle, voice: VoiceProfile? = nil,
        automaticCleanup: Bool = false
    ) -> String? {
        guard !style.skipsAllProcessing else { return nil }

        let tone = style.instructions
        let base: String
        switch (template, tone) {
        case (nil, nil):
            guard automaticCleanup else { return nil }
            base = cleanupInstructions
        case (nil, let tone?):
            base = cleanupInstructions + """


                Additionally, apply this tone throughout: \(tone)
                """
        case (let template?, nil):
            base = template.instructions + template.workedExampleBlock
        case (let template?, let tone?):
            base = template.instructions + template.workedExampleBlock + """


                Additionally, apply this tone throughout, without changing \
                the structure described above: \(tone)
                """
        }

        guard let voice else { return base }
        // Deliberately subordinate to the instructions above: the profile
        // says *whose* voice to keep, not what tone to write in, so a
        // "Formal" rule can't be overridden by a casual-sounding persona.
        return base + """


            For context, the author habitually writes like this: \
            \(voice.voiceContext) Preserve their vocabulary and characteristic \
            phrasing where doing so doesn't conflict with the instructions above.
            """
    }
}
