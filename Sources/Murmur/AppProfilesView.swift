import AppKit
import Speech
import SwiftUI

// MARK: - App Profiles
//
// Redesigned per the "Main" canvas (AppProfiles.dc.html): same
// `GlassPanelPage` shell as the other redesigned pages, warm palette
// instead of the shared dynamic `Palette`. Functionally unchanged — one
// page answering one question: "what happens when I dictate into this
// app?" Style and Templates each used to own half the answer on separate
// pages, with an undocumented rule that the template half silently won.
// Both halves still live on one row here, and the row still spells out
// the result.

struct AppProfilesPage: View {
    @ObservedObject var app: AppDelegate
    @Binding var page: Page

    @State private var profiles: [String: AppProfile] = AppProfileStore.profiles
    @State private var templates: [NoteTemplate] = NoteTemplateStore.all()
    /// The broad, unrestricted locale list (same one Settings' own language
    /// picker falls back to for the Apple engine) — loaded once, reused as
    /// the language-override options for any profile whose effective engine
    /// doesn't narrow the list further. See `localeOptions(for:)`.
    @State private var supportedLocaleIDs: [String] = []
    @State private var addingRule = false
    @State private var addRuleMode: AddRuleMode = .app
    @State private var draftBundleID = ""
    /// A site rule's match pattern — a plain substring checked against the
    /// active browser tab's URL (e.g. "mail.google.com"), not a full URL or
    /// regex. Also doubles as the profile's own display name in the list.
    @State private var draftSitePattern = ""
    /// Snapshotted when the add row opens rather than read in `body`:
    /// `NSWorkspace.runningApplications` scans every process, and the add
    /// row reads the list three times per render.
    @State private var runningApps: [(bundleID: String, name: String)] = []
    /// Lifted out of `ProfileRow` (rather than a local `@State` there) so a
    /// hovering row can also suppress the hairline divider on *both* of its
    /// sides — see `profileList`'s own note on why.
    @State private var hoveredBundleID: String?
    /// Which profile's full editor sheet is open, if any. A small
    /// `Identifiable` wrapper around the bundle ID rather than a bare
    /// `String?` bound straight to `.sheet(isPresented:)` — `.sheet(item:)`
    /// is what lets the sheet's own content reference *which* profile
    /// without a second piece of state to keep in sync.
    @State private var editingProfile: EditingProfile?
    private struct EditingProfile: Identifiable { let id: String }

    var body: some View {
        GlassPanelPage {
            // `ThinScrollView`, not a plain `ScrollView` — see
            // ScratchpadView.swift's own note on why: a bare
            // `.scrollIndicators(.hidden)` doesn't reliably suppress
            // macOS's native scroller by itself.
            ThinScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    header

                    tipBanner("Everything without a profile uses your default tone "
                              + "(\(StyleSettings.defaultStyle.displayName)) and no template. "
                              + "A profile can set either half, or both.")
                        .padding(.top, 18)

                    if let note = app.rewriteEngine.availabilityNote {
                        tipBanner(note).padding(.top, 12)
                    }

                    profileList
                        .padding(.top, 16)

                    if addingRule {
                        addRow.padding(.top, 10)
                    } else {
                        addProfileButton.padding(.top, 10)
                    }

                    relatedLink
                        .padding(.top, 14)
                }
            }
        }
        .onAppear {
            templates = NoteTemplateStore.all()
            loadLocales()
        }
        .sheet(item: $editingProfile) { editing in
            if let profile = profiles[editing.id] {
                ProfileEditorSheet(
                    bundleID: editing.id,
                    profile: profile,
                    templates: templates,
                    globalEngine: app.engine,
                    globalModel: globalModel(forEngine:),
                    globalLocaleID: app.localeID,
                    localeOptions: localeOptions(for: profile),
                    onChange: { updated in applyChange(bundleID: editing.id, updated) },
                    onDelete: { deleteProfile(bundleID: editing.id) })
            }
        }
    }

    /// Shared by both the sheet and (for the hotkey-conflict check) nowhere
    /// else now that the row itself no longer edits fields directly — kept
    /// as its own function anyway since `.sheet(item:)`'s closure re-reads
    /// `profiles[editing.id]` fresh on every change, and needs a single
    /// place to write back to both the local `@State` mirror and the store.
    private func applyChange(bundleID: String, _ updated: AppProfile) {
        // Single-owner: assigning a hotkey slot already held by a different
        // profile silently takes it from that profile — matches the
        // store's own house style of silent conflict handling (e.g.
        // pruning empties below) rather than a blocking-validation UI.
        if let slot = updated.hotkeySlot {
            for key in profiles.keys where key != bundleID {
                if profiles[key]?.hotkeySlot == slot {
                    profiles[key]?.hotkeySlot = nil
                }
            }
        }
        profiles[bundleID] = updated
        AppProfileStore.profiles = profiles
    }

    private func deleteProfile(bundleID: String) {
        profiles.removeValue(forKey: bundleID)
        AppProfileStore.profiles = profiles
    }

    private func loadLocales() {
        Task {
            let locales = await SpeechTranscriber.supportedLocales
            supportedLocaleIDs = sortedByLocalizedName(locales.map { $0.identifier(.bcp47) })
        }
    }

    private func sortedByLocalizedName(_ ids: [String]) -> [String] {
        ids.sorted {
            (Locale.current.localizedString(forIdentifier: $0) ?? $0)
            < (Locale.current.localizedString(forIdentifier: $1) ?? $1)
        }
    }

    /// The languages to offer a profile's language-override picker — those
    /// supported by whichever engine this profile would actually use (its
    /// own override, or else the global default), same rule Settings' own
    /// language picker follows for the global case. Falls back to the
    /// broad Apple-engine list when the effective engine doesn't narrow it
    /// (Apple itself, or an engine/model combo `supportedLanguageIDs`
    /// doesn't restrict).
    private func localeOptions(for profile: AppProfile) -> [String] {
        let effectiveEngine = profile.engine ?? app.engine
        // Each `xModel` param only actually matters when `effectiveEngine`
        // is that engine — but a profile's own `model` override should
        // still narrow the language list correctly in that case, not just
        // whatever the *global* model for that engine happens to be.
        let effectiveModel = profile.model ?? globalModel(forEngine: effectiveEngine)
        let restricted = AppDelegate.supportedLanguageIDs(
            engine: effectiveEngine,
            whisperModel: effectiveEngine == "whisper" ? effectiveModel : app.whisperModel,
            whisperCppModel: effectiveEngine == "whispercpp" ? effectiveModel : app.whisperCppModel,
            parakeetModel: effectiveEngine == "parakeet" ? effectiveModel : app.parakeetModel,
            sherpaModel: effectiveEngine == "sherpa" ? effectiveModel : app.sherpaModel)
        return sortedByLocalizedName(restricted ?? supportedLocaleIDs)
    }

    /// The globally-configured model for a given engine — `Settings
    /// .whisperModel`/`.whisperCppModel`/`.parakeetModel`/`.sherpaModel`
    /// depending on which, empty for Apple (no model concept). Mirrors
    /// `AppProfileStore.model(forBundleID:)`'s own per-engine switch.
    private func globalModel(forEngine engine: String) -> String {
        switch engine {
        case "whisper": return app.whisperModel
        case "whispercpp": return app.whisperCppModel
        case "parakeet": return app.parakeetModel
        case "sherpa": return app.sherpaModel
        default: return ""
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("App Profiles")
                .font(.manrope(22, .medium))
                .tracking(-0.33)
                .foregroundStyle(Palette.warmInk)
            Text("What Murmur does when you dictate into a particular app — or website.")
                .font(.manrope(12.5))
                .foregroundStyle(Palette.warmInkFaint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func tipBanner(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            MurmurIconView(icon: .help)
                .frame(width: 13, height: 13)
                .foregroundStyle(Palette.warmInkSoft)
                .padding(.top, 1)
            Text(text)
                .font(.manrope(12.5))
                .lineSpacing(3)
                .foregroundStyle(Palette.warmInkSoft)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    @ViewBuilder
    private var profileList: some View {
        if profiles.isEmpty && !addingRule {
            Text("No profiles yet — every app and site uses your defaults.")
                .font(.manrope(12.5))
                .italic()
                .foregroundStyle(Palette.warmInkFaint)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        } else {
            let sorted = profiles.sorted { $0.value.appName < $1.value.appName }
            VStack(spacing: 0) {
                ForEach(Array(sorted.enumerated()), id: \.element.key) { index, item in
                    profileRow(bundleID: item.key, profile: item.value)
                    // A divider sits on the boundary between two different
                    // row backgrounds, so it can never be color-matched
                    // away on both sides at once once either neighbor is
                    // hover-tinted — omitting it there (rather than always
                    // showing it) is the only fully seamless option; it
                    // stays everywhere else, between two plain rows.
                    if index != sorted.count - 1 {
                        let nextKey = sorted[index + 1].key
                        if hoveredBundleID != item.key && hoveredBundleID != nextKey {
                            Rectangle().fill(Palette.warmRowBorder).frame(height: 1)
                        }
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
    }

    // MARK: Rows

    private func profileRow(bundleID: String, profile: AppProfile) -> some View {
        CompactProfileRow(
            bundleID: bundleID,
            profile: profile,
            summary: summary(for: bundleID, profile: profile),
            isHovering: hoveredBundleID == bundleID,
            onHoverChange: { inside in
                hoveredBundleID = inside
                    ? bundleID
                    : (hoveredBundleID == bundleID ? nil : hoveredBundleID)
            },
            onOpen: { editingProfile = EditingProfile(id: bundleID) })
    }

    private var addProfileButton: some View {
        Button {
            draftBundleID = ""
            draftSitePattern = ""
            addRuleMode = .app
            runningApps = RunningApps.list
            addingRule = true
        } label: {
            HStack(spacing: 8) {
                MurmurIconView(icon: .plus).frame(width: 13, height: 13)
                Text("Add a profile").font(.manrope(12.5, .semibold))
            }
            .foregroundStyle(Palette.warmInkSoft)
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Radius.sm)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                    .foregroundStyle(Palette.warmDivider))
            .contentShape(Rectangle())
        }
        .buttonStyle(PressScaleButtonStyle(scale: 0.98))
    }

    /// A profile normally binds to an app (bundle ID); a site rule instead
    /// binds to a plain substring match against the frontmost browser's
    /// active tab URL, checked only when a supported browser (the same
    /// five `MeetingDetector` already knows: Chrome/Safari/Edge/Arc/Brave)
    /// is actually frontmost and at least one site rule exists — see
    /// `AppProfileStore.siteProfileKey(forURL:)`.
    private enum AddRuleMode { case app, site }

    private var addRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("", selection: $addRuleMode) {
                Text("App").tag(AddRuleMode.app)
                Text("Website").tag(AddRuleMode.site)
            }
            .pickerStyle(.segmented)
            .frame(width: 160)
            .labelsHidden()

            HStack(spacing: 8) {
                if addRuleMode == .app {
                    WarmFieldSelect(
                        options: [""] + runningApps.map(\.bundleID),
                        label: { id in
                            id.isEmpty
                                ? "Choose a running app…"
                                : (runningApps.first { $0.bundleID == id }?.name ?? id)
                        },
                        selection: $draftBundleID)
                } else {
                    TextField("e.g. mail.google.com", text: $draftSitePattern)
                        .textFieldStyle(.plain)
                        .font(.manrope(12.5))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .frame(width: 220)
                        .background(Color.white, in: RoundedRectangle(cornerRadius: Radius.sm))
                        .overlay(RoundedRectangle(cornerRadius: Radius.sm)
                            .stroke(Palette.warmRowBorder, lineWidth: 1))
                }
                IconButton(icon: .check, help: "Save") {
                    switch addRuleMode {
                    case .app:
                        if let appInfo = runningApps.first(where: { $0.bundleID == draftBundleID }) {
                            // Starts with the current default tone made
                            // explicit, so the new row does something
                            // visible immediately.
                            profiles[appInfo.bundleID] = AppProfile(
                                appName: appInfo.name,
                                style: StyleSettings.defaultStyle,
                                templateID: nil)
                            AppProfileStore.profiles = profiles
                        }
                    case .site:
                        let pattern = draftSitePattern.trimmingCharacters(in: .whitespaces)
                        if !pattern.isEmpty {
                            profiles[AppProfileStore.siteKey(forPattern: pattern)] = AppProfile(
                                appName: pattern,
                                style: StyleSettings.defaultStyle,
                                templateID: nil)
                            AppProfileStore.profiles = profiles
                        }
                    }
                    addingRule = false
                    draftBundleID = ""
                    draftSitePattern = ""
                }
                .disabled(addRuleMode == .app
                    ? draftBundleID.isEmpty
                    : draftSitePattern.trimmingCharacters(in: .whitespaces).isEmpty)
                IconButton(icon: .plus, rotated: true, help: "Cancel") {
                    addingRule = false
                    draftBundleID = ""
                    draftSitePattern = ""
                }
                Spacer()
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 9)
    }

    private var relatedLink: some View {
        HStack(spacing: 4) {
            Text("Want to reshape text on demand instead of automatically?")
                .font(.manrope(12))
                .foregroundStyle(Palette.warmInkSoft)
            Button { page = .transforms } label: {
                Text("Transforms")
                    .font(.manrope(12, .medium))
                    .foregroundStyle(Palette.sunsetDeep)
            }
            .buttonStyle(.plain)
            Text("run when you trigger them.")
                .font(.manrope(12))
                .foregroundStyle(Palette.warmInkSoft)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    /// A middot-joined list of just this profile's *active* overrides — the
    /// whole reason the engine override was easy to miss before is that it
    /// lived behind a chevron with nothing on the always-visible row
    /// hinting it was even set. Every override that actually does
    /// something appears here now, not just tone/template.
    private func summary(for bundleID: String, profile: AppProfile) -> String {
        var parts: [String] = []
        if let tone = profile.style?.displayName { parts.append(tone) }
        if let templateID = profile.templateID,
           let name = templates.first(where: { $0.id == templateID })?.name {
            parts.append(name)
        }
        if let engine = profile.engine { parts.append(AppProfilesPage.engineDisplayName(engine)) }
        if let model = profile.model {
            parts.append(AppProfilesPage.modelDisplayName(model, engine: profile.engine ?? app.engine))
        }
        if let localeID = profile.localeIdentifier {
            parts.append(Locale.current.localizedString(forIdentifier: localeID) ?? localeID)
        }
        if profile.autoPaste == false { parts.append("No auto-paste") }
        if let hotkey = profile.hotkeySlot { parts.append(hotkey.label) }
        return parts.isEmpty ? "Uses your defaults" : parts.joined(separator: " · ")
    }

    /// Shared by the row summary above and `ProfileEditorSheet`'s own
    /// engine picker, so the same engine id always reads the same way.
    static func engineDisplayName(_ id: String) -> String {
        switch id {
        case "whisper": return "Whisper"
        case "whispercpp": return "whisper.cpp"
        case "parakeet": return "Parakeet"
        case "sherpa": return "sherpa-onnx"
        default: return "Apple"
        }
    }

    /// The model choices for a given engine — empty for Apple, which has
    /// no model concept. Shared by `ProfileEditorSheet`'s model picker so
    /// it never has to know each engine's own `availableModels` type.
    static func modelOptions(forEngine engine: String) -> [(id: String, label: String)] {
        switch engine {
        case "whisper": return WhisperEngine.availableModels
        case "whispercpp": return WhisperCppEngine.availableModels
        case "parakeet": return ParakeetEngine.availableModels
        case "sherpa": return SherpaOnnxEngine.availableModels
        default: return []
        }
    }

    /// A model's own short name within a given engine — just the name,
    /// dropping the " — size/description" suffix every engine's own
    /// `availableModels` label carries (e.g. "FunASR Nano — LLM-backed,
    /// English only, ~1 GB" → "FunASR Nano"). Those full labels were
    /// written for Settings' own dedicated, full-width picker row; reused
    /// as-is here they made the picker trigger wide enough to squeeze this
    /// sheet's fixed-width row layout into wrapping its *own* label
    /// character-by-character — a real, reproduced layout bug, not a
    /// hypothetical one. Falls back to the raw id if the engine's
    /// `availableModels` doesn't list it (e.g. a hidden model like
    /// Zipformer/Moonshine, still reachable by id even though it's not
    /// offered in the picker — see `SherpaOnnxEngine`'s own doc comment on
    /// why those stay hidden, not deleted).
    static func modelDisplayName(_ id: String, engine: String) -> String {
        let fullLabel = modelOptions(forEngine: engine).first { $0.id == id }?.label ?? id
        return fullLabel.components(separatedBy: " — ").first ?? fullLabel
    }
}

// MARK: - Row

/// The always-visible row: name, a middot-joined summary of whatever's
/// actually overridden, and nothing else — tapping anywhere on the row
/// opens `ProfileEditorSheet`, which is where every setting actually lives
/// now. Replaces the old row that tried to fit up to seven pickers inline
/// (four visible, three behind a chevron) — engine specifically was one of
/// the three behind it, easy to set and then never see confirmed anywhere.
private struct CompactProfileRow: View {
    let bundleID: String
    let profile: AppProfile
    let summary: String
    let isHovering: Bool
    let onHoverChange: (Bool) -> Void
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(profile.appName)
                            .font(.manrope(13, .semibold))
                            .foregroundStyle(Palette.warmInk)
                        // No dedicated "site" icon exists in `MurmurIcon`
                        // — a plain text badge distinguishes a website
                        // rule from an app one without needing a new
                        // glyph, same weight as the "Recommended"-style
                        // pills used elsewhere.
                        if AppProfileStore.isSiteKey(bundleID) {
                            Text("Website")
                                .font(.manrope(9.5, .semibold))
                                .foregroundStyle(Palette.warmInkFaint)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Palette.warmRowBorder, in: Capsule())
                        }
                    }
                    Text(summary)
                        .font(.manrope(11))
                        .foregroundStyle(Palette.warmInkSoft)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                MurmurIconView(icon: .caret)
                    .frame(width: 9, height: 9)
                    .foregroundStyle(Palette.warmInkFainter)
                    .opacity(isHovering ? 1 : 0.5)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 13)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(
            RoundedRectangle(cornerRadius: Radius.sm)
                .fill(isHovering ? Palette.warmRowBorder.opacity(0.55) : Color.clear))
        // See HomeView.swift's historyRow for why this is needed: a .clear
        // background makes SwiftUI treat the row's empty space as outside
        // the hoverable region until this forces the whole padded frame to
        // count, regardless of what's actually drawn there.
        .contentShape(Rectangle())
        .onHover(perform: onHoverChange)
    }
}

// MARK: - Editor sheet

/// Everything one profile can set, in three labeled sections — Style,
/// Recognition, Behavior — each row at equal visual weight. Nothing here
/// is progressively disclosed: the whole point of replacing the old inline
/// row is that a setting you can't see isn't a setting you remember you
/// set. Each field writes through `onChange` immediately on selection, the
/// same instant-apply behavior the old row had — "Done" just closes the
/// sheet, it isn't a separate save step.
private struct ProfileEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    let bundleID: String
    let profile: AppProfile
    let templates: [NoteTemplate]
    let globalEngine: String
    /// The globally-configured model for a given engine id — mirrors
    /// `AppProfilesPage.globalModel(forEngine:)`. A closure rather than one
    /// flat value: the model picker's own "Default" label needs whichever
    /// engine is actually in effect (this profile's own override, or else
    /// `globalEngine`), not always `globalEngine`'s.
    let globalModel: (String) -> String
    let globalLocaleID: String
    /// Languages to offer in the language-override picker — already
    /// narrowed to whichever engine this profile would actually use; see
    /// `AppProfilesPage.localeOptions(for:)`.
    let localeOptions: [String]
    let onChange: (AppProfile) -> Void
    let onDelete: () -> Void

    @State private var showingDeleteConfirm = false

    private func set<T>(_ keyPath: WritableKeyPath<AppProfile, T>, _ value: T) {
        var updated = profile
        updated[keyPath: keyPath] = value
        onChange(updated)
    }

    /// `nil` first so "inherit the default" is the top choice rather than
    /// something buried under five concrete tones.
    private var styleOptions: [WritingStyle?] {
        [nil] + WritingStyle.allCases.map { Optional($0) }
    }

    /// What "Default tone" actually resolves to for this app — plain
    /// global default everywhere, except a recognized terminal, which
    /// `AppProfileStore.style(forBundleID:)` auto-defaults to Raw. Stated
    /// rather than left to look up, same as developer vocabulary below.
    private var defaultStyleLabel: String {
        DeveloperVocabulary.terminalBundleIDs.contains(bundleID)
            ? "Default (Raw)" : "Default (\(StyleSettings.defaultStyle.displayName))"
    }

    private var templateOptions: [UUID?] { [nil] + templates.map { Optional($0.id) } }

    private var engineOptions: [String?] { [nil, "apple", "whisper", "whispercpp", "parakeet", "sherpa"] }

    private func engineLabel(_ id: String?) -> String {
        guard let id else { return "Default (\(AppProfilesPage.engineDisplayName(globalEngine)))" }
        return AppProfilesPage.engineDisplayName(id)
    }

    /// Whichever engine this profile would actually use — its own
    /// override if set, else the global default. The model picker below
    /// is keyed to this, not always `globalEngine`, so switching the
    /// engine picker immediately offers that engine's own models.
    private var effectiveEngine: String { profile.engine ?? globalEngine }

    private var modelOptions: [String?] {
        [nil] + AppProfilesPage.modelOptions(forEngine: effectiveEngine).map { Optional($0.id) }
    }

    private func modelLabel(_ id: String?) -> String {
        guard let id else { return "Default (\(AppProfilesPage.modelDisplayName(globalModel(effectiveEngine), engine: effectiveEngine)))" }
        return AppProfilesPage.modelDisplayName(id, engine: effectiveEngine)
    }

    private var localeSelectOptions: [String?] { [nil] + localeOptions }

    private func localeLabel(_ id: String?) -> String {
        guard let id else {
            return "Default (\(Locale.current.localizedString(forIdentifier: globalLocaleID) ?? globalLocaleID))"
        }
        return Locale.current.localizedString(forIdentifier: id) ?? id
    }

    private var autoPasteOptions: [Bool?] { [nil, true, false] }

    private func autoPasteLabel(_ value: Bool?) -> String {
        switch value {
        case nil: return "Default (\(Settings.autoPasteEnabled ? "On" : "Off"))"
        case true?: return "On"
        case false?: return "Off"
        }
    }

    private var developerVocabularyOptions: [Bool?] { [nil, true, false] }

    private var autoDefaultLabel: String {
        DeveloperVocabulary.developerContextBundleIDs.contains(bundleID)
            ? "Auto (on for this app)" : "Auto (off for this app)"
    }

    private func developerVocabularyLabel(_ value: Bool?) -> String {
        switch value {
        case nil: return autoDefaultLabel
        case true?: return "On"
        case false?: return "Off"
        }
    }

    private var hotkeyOptions: [ProfileHotkeySlot?] { [nil] + ProfileHotkeySlot.allCases.map { Optional($0) } }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                HStack(spacing: 6) {
                    Text(profile.appName)
                        .font(.manrope(16, .semibold))
                        .foregroundStyle(Palette.warmInk)
                    if AppProfileStore.isSiteKey(bundleID) {
                        Text("Website")
                            .font(.manrope(9.5, .semibold))
                            .foregroundStyle(Palette.warmInkFaint)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Palette.warmRowBorder, in: Capsule())
                    }
                }
                Spacer()
                // Not `GhostButtonStyle()` — it pulls from `Palette.accent`,
                // the pre-warm-redesign accent color (a pale lime-green),
                // not this page's actual warm palette. Matches
                // `NotetakerHotkeyEditor`'s own "Done" button instead: a
                // solid dark pill, the established warm-sheet convention.
                Button {
                    dismiss()
                } label: {
                    Text("Done")
                        .font(.manrope(12.5, .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Palette.navActivePill, in: RoundedRectangle(cornerRadius: Radius.sm))
                }
                .buttonStyle(.plain)
            }
            .padding(.bottom, 18)

            sectionHeader("Style")
            sheetRow(label: "Tone") {
                WarmFieldSelect(
                    options: styleOptions, label: { $0?.displayName ?? defaultStyleLabel },
                    selection: Binding(get: { profile.style }, set: { set(\.style, $0) }))
            }
            sheetRow(label: "Template", isLast: true) {
                WarmFieldSelect(
                    options: templateOptions,
                    label: { id in
                        guard let id else { return "No template" }
                        return templates.first { $0.id == id }?.name ?? "No template"
                    },
                    selection: Binding(get: { profile.templateID }, set: { set(\.templateID, $0) }))
            }

            sectionHeader("Recognition").padding(.top, 20)
            sheetRow(label: "Engine") {
                WarmFieldSelect(
                    options: engineOptions, label: engineLabel,
                    selection: Binding(
                        get: { profile.engine },
                        set: { newValue in
                            // A model id only means something within the
                            // engine it belongs to — clear a stale one
                            // rather than carry, say, a Whisper model id
                            // into a freshly-switched-to Parakeet override.
                            var updated = profile
                            updated.engine = newValue
                            updated.model = nil
                            onChange(updated)
                        }))
            }
            // Apple has no model concept — nothing to pick.
            if effectiveEngine != "apple" {
                sheetRow(label: "Model") {
                    WarmFieldSelect(
                        options: modelOptions, label: modelLabel,
                        selection: Binding(get: { profile.model }, set: { set(\.model, $0) }))
                }
            }
            sheetRow(label: "Language", isLast: true) {
                WarmFieldSelect(
                    options: localeSelectOptions, label: localeLabel,
                    selection: Binding(get: { profile.localeIdentifier }, set: { set(\.localeIdentifier, $0) }))
            }

            sectionHeader("Behavior").padding(.top, 20)
            sheetRow(label: "Auto-paste") {
                WarmFieldSelect(
                    options: autoPasteOptions, label: autoPasteLabel,
                    selection: Binding(get: { profile.autoPaste }, set: { set(\.autoPaste, $0) }))
            }
            sheetRow(label: "Developer vocabulary") {
                WarmFieldSelect(
                    options: developerVocabularyOptions, label: developerVocabularyLabel,
                    selection: Binding(get: { profile.developerVocabulary }, set: { set(\.developerVocabulary, $0) }))
            }
            sheetRow(label: "Hotkey", isLast: true) {
                WarmFieldSelect(
                    options: hotkeyOptions, label: { $0?.label ?? "No hotkey" },
                    selection: Binding(get: { profile.hotkeySlot }, set: { set(\.hotkeySlot, $0) }))
            }

            Button {
                showingDeleteConfirm = true
            } label: {
                Text("Delete profile")
                    .font(.manrope(12, .medium))
                    .foregroundStyle(Palette.warmInkFaint)
            }
            .buttonStyle(.plain)
            .padding(.top, 22)
        }
        .padding(22)
        .frame(width: 420)
        .environment(\.colorScheme, .light)
        .confirmationDialog(
            "Delete this profile?", isPresented: $showingDeleteConfirm, titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                onDelete()
                dismiss()
            }
        } message: {
            Text("\(profile.appName) goes back to using your defaults.")
        }
    }

    private func sectionHeader(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.manrope(10.5, .semibold))
            .tracking(0.6)
            .foregroundStyle(Palette.sunsetDeep)
            .padding(.bottom, 8)
    }

    private func sheetRow<Content: View>(
        label: String, isLast: Bool = false, @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(spacing: 0) {
            HStack {
                // `.lineLimit(1)` is the actual fix, not just tidiness: an
                // over-wide sibling (the picker trigger button next to
                // this, `.fixedSize()`'d to whatever its label text needs)
                // can squeeze this row's own remaining width toward zero —
                // reproduced for real with a long model label ("Model"
                // wrapped one letter per line). Capped at one line, an
                // over-squeeze truncates with an ellipsis instead, which
                // is recoverable-looking rather than broken-looking.
                Text(label)
                    .font(.manrope(12.5))
                    .foregroundStyle(Palette.warmInkSoft)
                    .lineLimit(1)
                Spacer()
                content()
            }
            .padding(.vertical, 9)
            if !isLast {
                Rectangle().fill(Palette.warmRowBorder).frame(height: 1)
            }
        }
    }
}

// MARK: - Warm field select
//
// Same `Button` + `.popover` mechanics as the shared `FieldSelect` (Menu
// combined with `.menuStyle(.borderlessButton)` silently drops the custom
// background/border on this build — see that type's own note), reskinned
// in warm tokens throughout, including the popover's own list — the
// shared version bakes `Palette.ink`/`.cardHover` into that list with no
// override, so restyling only the trigger would leave a mismatched popover.

private struct WarmFieldSelect<T: Hashable>: View {
    let options: [T]
    let label: (T) -> String
    @Binding var selection: T
    @State private var isOpen = false

    var body: some View {
        Button {
            isOpen = true
        } label: {
            HStack(spacing: 6) {
                Text(label(selection))
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9, weight: .semibold))
            }
            .font(.manrope(12, .medium))
            .foregroundStyle(Palette.warmInkSoft)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.white, in: RoundedRectangle(cornerRadius: Radius.sm))
            .overlay(RoundedRectangle(cornerRadius: Radius.sm).stroke(Palette.warmRowBorder, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .fixedSize()
        .popover(isPresented: $isOpen, arrowEdge: .bottom) {
            WarmFieldSelectList(options: options, label: label, selection: $selection, isOpen: $isOpen)
        }
    }
}

private struct WarmFieldSelectList<T: Hashable>: View {
    let options: [T]
    let label: (T) -> String
    @Binding var selection: T
    @Binding var isOpen: Bool
    @State private var hovered: T?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(options, id: \.self) { option in
                Button {
                    selection = option
                    isOpen = false
                } label: {
                    Text(label(option))
                        .font(.manrope(12, .medium))
                        .foregroundStyle(option == selection ? Palette.warmInk : Palette.warmInkSoft)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(hovered == option ? Palette.warmRowBorder : Color.clear)
                }
                .buttonStyle(.plain)
                .onHover { inside in hovered = inside ? option : nil }
            }
        }
        .padding(.vertical, 4)
        .frame(minWidth: 160)
        .environment(\.colorScheme, .light)
    }
}

// MARK: - Shared

/// The user-facing apps currently running, for picking one to profile.
enum RunningApps {
    static var list: [(bundleID: String, name: String)] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .compactMap { application in
                guard let bundleID = application.bundleIdentifier,
                      let name = application.localizedName else { return nil }
                return (bundleID, name)
            }
            .sorted { $0.name < $1.name }
    }
}
