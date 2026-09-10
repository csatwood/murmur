import AppKit
import Speech
import SwiftUI

// MARK: - Settings
//
// Redesigned per the "Main" canvas (Settings.dc.html): same `GlassPanelPage`
// shell as the other redesigned pages, warm palette instead of the shared
// dynamic `Palette`. Functionally unchanged — appearance, permissions,
// dictation key, and recognition engine, all still wired to the exact same
// `AppDelegate` state.
//
// The mockup's own "Software" section shows a version number plus an
// "Update available" pill — this app has no update-checking mechanism at
// all (no Sparkle, no appcast, nothing to compare against), so that pill
// would have to be invented from nothing rather than translated. Only the
// real, honest half — the actual running version, read from the bundle —
// is implemented here; the update-check itself is a real feature, not a
// restyle, and hasn't been asked for.

struct SettingsPage: View {
    @ObservedObject var app: AppDelegate
    @State private var supportedLocaleIDs: [String] = []
    @State private var handsFreeAutoStop = Settings.handsFreeAutoStop
    /// Which `AccentFieldSelect` (by its `id`) has its panel open, if any.
    /// Lifted up to the whole page rather than owned by each dropdown —
    /// see the panel-rendering `.overlayPreferenceValue` below for why.
    @State private var openDropdown: String?

    var body: some View {
        GlassPanelPage {
            // `ThinScrollView`, not a plain `ScrollView` — see
            // ScratchpadView.swift's own note on why: a bare
            // `.scrollIndicators(.hidden)` doesn't reliably suppress
            // macOS's native scroller by itself.
            ThinScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    header

                    sectionHeader("Appearance").padding(.top, 22)
                    appearanceSection

                    sectionHeader("Permissions").padding(.top, 22)
                    permissionsSection

                    sectionHeader("Dictation").padding(.top, 22)
                    dictationSection

                    sectionHeader("Software").padding(.top, 22)
                    softwareSection
                }
                // Attached to the whole page, not to `dictationSection` or
                // any individual trigger: an `.overlay` only ever paints
                // above its *own* host view, and a later sibling declared
                // outside that host (Software, or the next row down) still
                // draws on top of it — which is exactly the bug where the
                // Parakeet-model row's own white trigger rendered over the
                // still-open Recognition-engine panel behind it. Anchoring
                // here means the open panel always has every row on the
                // page as an earlier sibling, so it wins regardless of
                // which trigger opened it.
                .overlayPreferenceValue(DropdownAnchorKey.self) { anchors in
                    if let openDropdown, let anchor = anchors[openDropdown] {
                        DropdownPanel(
                            openDropdown: openDropdown,
                            anchor: anchor,
                            options: dropdownOptions(for: openDropdown),
                            label: dropdownLabel(for: openDropdown),
                            selection: dropdownSelection(for: openDropdown),
                            close: { self.openDropdown = nil })
                    }
                }
            }
        }
        .onAppear(perform: loadLocales)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Settings")
                .font(.manrope(22, .medium))
                .tracking(-0.33)
                .foregroundStyle(Palette.warmInk)
            Text("Appearance, permissions, dictation key, recognition engine.")
                .font(.manrope(12.5))
                .foregroundStyle(Palette.warmInkFaint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.manrope(13, .semibold))
            .foregroundStyle(Palette.warmInk)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// `.field-row` reskinned in warm tokens: a label/detail on the left, a
    /// control on the right, a hairline below unless it's the section's
    /// last row. Reused for every row on this page rather than shared —
    /// same call as every other bespoke warm view this redesign has added.
    private func fieldRow<Control: View>(
        label: String, detail: String? = nil, isLast: Bool = false,
        @ViewBuilder control: () -> Control
    ) -> some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(label)
                        .font(.manrope(12.5, .semibold))
                        .foregroundStyle(Palette.warmInk)
                    if let detail {
                        Text(detail)
                            .font(.manrope(11))
                            .foregroundStyle(Palette.warmInkSoft)
                            .lineSpacing(3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 16)
                control()
            }
            .padding(.vertical, 12)
            if !isLast {
                Rectangle().fill(Palette.warmRowBorder).frame(height: 1)
            }
        }
    }

    // MARK: Appearance

    private var appearanceSection: some View {
        fieldRow(label: "Theme", detail: appearanceDetail, isLast: true) {
            HStack(spacing: 2) {
                ForEach(AppearanceSetting.allCases) { setting in
                    Button {
                        withAnimation(.murmurEase(0.18)) { app.setAppearance(setting) }
                    } label: {
                        Text(setting.label)
                            .font(.manrope(12, setting == app.appearance ? .semibold : .regular))
                            .foregroundStyle(setting == app.appearance ? .white : Palette.warmInkSoft)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 6)
                            .background {
                                if setting == app.appearance {
                                    Capsule().fill(Palette.sunset)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(2)
            .background(Color.white, in: Capsule())
            .overlay(Capsule().stroke(Palette.warmRowBorder, lineWidth: 1))
            .fixedSize()
        }
    }

    /// Says what the current choice actually does, rather than restating
    /// the option's own name back at the reader.
    private var appearanceDetail: String {
        switch app.appearance {
        case .system:
            return "Follows your Mac — including switching automatically if macOS is set to Auto."
        case .light:
            return "Always light, whatever your Mac is set to."
        case .dark:
            return "Always dark, whatever your Mac is set to."
        }
    }

    // MARK: Permissions

    private var permissionsSection: some View {
        VStack(spacing: 0) {
            permissionRow(
                granted: app.micAuthorized,
                title: "Microphone",
                detail: "Required to hear your dictation.",
                pane: "Privacy_Microphone",
                isLast: false)
            permissionRow(
                granted: app.axTrusted,
                title: "Accessibility",
                detail: "Required for the global hotkey and pasting. "
                    + "Relaunch Murmur after granting.",
                pane: "Privacy_Accessibility",
                isLast: app.axTrusted)
            if !app.axTrusted {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Toggle on in System Settings but still red here? The saved grant "
                         + "belongs to an older build. Click Reset Grant — the app relaunches, "
                         + "macOS asks once more, and the new grant sticks for all future updates.")
                        .font(.manrope(11.5))
                        .foregroundStyle(Palette.warmInkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 8) {
                        Button("Reset Grant & Relaunch") { app.resetAccessibilityGrant() }
                            .buttonStyle(WarmGhostButtonStyle())
                        Button("Relaunch") { app.relaunch() }
                            .buttonStyle(WarmGhostButtonStyle())
                    }
                }
                .padding(.top, 10)
                .padding(.bottom, 12)
            }
        }
    }

    private func permissionRow(
        granted: Bool, title: String, detail: String, pane: String, isLast: Bool
    ) -> some View {
        fieldRow(label: title, detail: detail, isLast: isLast) {
            if granted {
                HStack(spacing: 6) {
                    MurmurIconView(icon: .check).frame(width: 13, height: 13)
                    Text("Granted").font(.manrope(12, .semibold))
                }
                .foregroundStyle(Palette.sunsetDeep)
            } else {
                Button("Open Settings") {
                    let url = URL(string:
                        "x-apple.systempreferences:com.apple.preference.security?\(pane)")!
                    NSWorkspace.shared.open(url)
                }
                .buttonStyle(WarmGhostButtonStyle())
            }
        }
    }

    // MARK: Dictation

    private var dictationSection: some View {
        VStack(spacing: 0) {
            fieldRow(label: "Dictation key") {
                AccentFieldSelect(
                    id: "hotkey", label: app.hotkey.displayName, openID: $openDropdown)
            }
            fieldRow(
                label: "Hands-free auto-stop",
                detail: "Double-tap to start, then stop automatically on a real pause "
                    + "instead of tapping again. Manual stop always still works.",
                isLast: false
            ) {
                WarmToggle(isOn: $handsFreeAutoStop)
                    .onChange(of: handsFreeAutoStop) { _, newValue in
                        Settings.handsFreeAutoStop = newValue
                    }
            }
            fieldRow(label: "Language") {
                AccentFieldSelect(
                    id: "language",
                    label: Locale.current.localizedString(forIdentifier: app.localeID) ?? app.localeID,
                    openID: $openDropdown)
            }
            fieldRow(
                label: "Recognition engine",
                detail: engineDetail,
                isLast: app.engine != "whisper" && app.engine != "whispercpp"
                    && app.engine != "parakeet"
            ) {
                AccentFieldSelect(id: "engine", label: engineLabel(app.engine), openID: $openDropdown)
            }
            if app.engine == "whisper" {
                fieldRow(
                    label: "Whisper model",
                    detail: whisperModelDetail,
                    isLast: true
                ) {
                    AccentFieldSelect(
                        id: "whisperModel",
                        label: WhisperEngine.availableModels.first { $0.id == app.whisperModel }?.label
                            ?? app.whisperModel,
                        openID: $openDropdown)
                }
            }
            if app.engine == "whispercpp" {
                fieldRow(
                    label: "whisper.cpp model",
                    detail: whisperCppModelDetail,
                    isLast: true
                ) {
                    AccentFieldSelect(
                        id: "whisperCppModel",
                        label: WhisperCppEngine.availableModels.first { $0.id == app.whisperCppModel }?.label
                            ?? app.whisperCppModel,
                        openID: $openDropdown)
                }
            }
            if app.engine == "parakeet" {
                fieldRow(
                    label: "Parakeet model",
                    detail: parakeetModelDetail,
                    isLast: true
                ) {
                    AccentFieldSelect(
                        id: "parakeetModel",
                        label: ParakeetEngine.availableModels.first { $0.id == app.parakeetModel }?.label
                            ?? app.parakeetModel,
                        openID: $openDropdown)
                }
            }
        }
    }

    /// The shared panel rendered by the page-level `.overlayPreferenceValue`
    /// needs to know which options/labels/binding go with whichever
    /// `AccentFieldSelect.id` is currently open — these three dispatch on
    /// that id rather than the panel carrying a generic `Binding<T>` itself,
    /// since all four dropdowns on this page happen to be `String`-valued
    /// anyway.
    private func dropdownOptions(for id: String) -> [String] {
        switch id {
        case "hotkey": return HotkeyMonitor.Hotkey.allCases.map(\.rawValue)
        case "engine": return ["apple", "whisper", "whispercpp", "parakeet"]
        case "whisperModel": return WhisperEngine.availableModels.map(\.id)
        case "whisperCppModel": return WhisperCppEngine.availableModels.map(\.id)
        case "parakeetModel": return ParakeetEngine.availableModels.map(\.id)
        case "language": return pickerLocaleIDs
        default: return []
        }
    }

    private func dropdownLabel(for id: String) -> (String) -> String {
        switch id {
        case "hotkey":
            return { raw in HotkeyMonitor.Hotkey(rawValue: raw)?.displayName ?? raw }
        case "engine": return engineLabel
        case "whisperModel":
            return { m in WhisperEngine.availableModels.first { $0.id == m }?.label ?? m }
        case "whisperCppModel":
            return { m in WhisperCppEngine.availableModels.first { $0.id == m }?.label ?? m }
        case "parakeetModel":
            return { m in ParakeetEngine.availableModels.first { $0.id == m }?.label ?? m }
        case "language":
            return { id in Locale.current.localizedString(forIdentifier: id) ?? id }
        default: return { $0 }
        }
    }

    private func dropdownSelection(for id: String) -> Binding<String> {
        switch id {
        case "hotkey":
            return Binding(
                get: { app.hotkey.rawValue },
                set: { if let hotkey = HotkeyMonitor.Hotkey(rawValue: $0) { app.setHotkey(hotkey) } })
        case "engine": return Binding(get: { app.engine }, set: { app.setEngine($0) })
        case "whisperModel": return Binding(get: { app.whisperModel }, set: { app.setWhisperModel($0) })
        case "whisperCppModel":
            return Binding(get: { app.whisperCppModel }, set: { app.setWhisperCppModel($0) })
        case "parakeetModel": return Binding(get: { app.parakeetModel }, set: { app.setParakeetModel($0) })
        case "language": return Binding(get: { app.localeID }, set: { app.setLocale($0) })
        default: return .constant("")
        }
    }

    private func engineLabel(_ id: String) -> String {
        switch id {
        case "whisper": return "Whisper — precise"
        // whisper.cpp runs the same Whisper models through a different,
        // Metal-accelerated engine — benchmarked ~3-4x faster than the
        // WhisperKit/Neural-Engine path above on Apple Silicon, likely
        // because it uses the GPU rather than the power-efficient Neural
        // Engine. A speed/battery tradeoff worth letting you pick, not one
        // engine replacing the other.
        case "whispercpp": return "whisper.cpp — precise, Metal"
        case "parakeet": return "Parakeet — precise, fast"
        default: return "Apple — instant"
        }
    }

    private var engineDetail: String {
        switch app.engine {
        case "whisper":
            return "Whisper: best accuracy on accents and jargon; your vocabulary is fed "
                + "to the model. Runs locally."
        case "whispercpp":
            return "whisper.cpp: the same Whisper models, run on the GPU via Metal instead "
                + "of the Neural Engine — faster, at some cost to battery life. Runs locally."
        case "parakeet":
            return "Parakeet: NVIDIA's model, run on the Neural Engine — notably fast, "
                + "strong accuracy. Your dictionary isn't fed to it yet, unlike the "
                + "Whisper engines above. Runs locally."
        default:
            return "Apple: instant, built into macOS. Runs locally."
        }
    }

    private var whisperModelDetail: String {
        if app.whisperReady {
            return "Model loaded — Whisper is transcribing your dictations."
        }
        if app.whisperEngine.isModelDownloaded(app.whisperModel) {
            return "Model downloaded — loading. Apple engine covers dictations until it's ready."
        }
        return "Downloading in the background. Apple engine covers dictations until it's ready."
    }

    private var whisperCppModelDetail: String {
        if app.whisperCppReady {
            return "Model loaded — whisper.cpp is transcribing your dictations."
        }
        if app.whisperCppEngine.isModelDownloaded(app.whisperCppModel) {
            return "Model downloaded — loading. Apple engine covers dictations until it's ready."
        }
        return "Downloading in the background. Apple engine covers dictations until it's ready."
    }

    private var parakeetModelDetail: String {
        if app.parakeetReady {
            return "Model loaded — Parakeet is transcribing your dictations."
        }
        if app.parakeetEngine.isModelDownloaded(app.parakeetModel) {
            return "Model downloaded — loading. Apple engine covers dictations until it's ready."
        }
        return "Downloading in the background. Apple engine covers dictations until it's ready."
    }

    // MARK: Software

    private var softwareSection: some View {
        fieldRow(label: "Murmur", detail: "Version \(appVersion)", isLast: true) {
            EmptyView()
        }
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
    }

    /// The engine currently selected in Settings determines which
    /// languages are even offered — Apple's fixed on-device asset list
    /// only applies to the "apple" engine; Whisper/whisper.cpp/Parakeet
    /// each have their own trained-language set (see
    /// `AppDelegate.supportedLanguageIDs()`), which is where Parakeet v3's
    /// languages show up — only the ones accurate enough to actually
    /// offer, per `ParakeetEngine.v3WordErrorRates`.
    private var pickerLocaleIDs: [String] {
        var ids = sortedByLocalizedName(app.supportedLanguageIDs() ?? supportedLocaleIDs)
        if !ids.contains(app.localeID) { ids.insert(app.localeID, at: 0) }
        return ids
    }

    private func sortedByLocalizedName(_ ids: [String]) -> [String] {
        ids.sorted {
            (Locale.current.localizedString(forIdentifier: $0) ?? $0)
            < (Locale.current.localizedString(forIdentifier: $1) ?? $1)
        }
    }

    private func loadLocales() {
        Task {
            let locales = await SpeechTranscriber.supportedLocales
            supportedLocaleIDs = sortedByLocalizedName(locales.map { $0.identifier(.bcp47) })
        }
    }
}

/// `.switch` reskinned in warm tokens — see VoiceProfileView's own
/// `warmToggle` for the twin of this; kept as a separate local type here
/// (rather than shared) since `private` there scopes it to that file.
private struct WarmToggle: View {
    @Binding var isOn: Bool

    var body: some View {
        Button {
            withAnimation(.murmurEase(0.18)) { isOn.toggle() }
        } label: {
            ZStack(alignment: isOn ? .trailing : .leading) {
                Capsule()
                    .fill(isOn ? Palette.sunset : Palette.warmDivider)
                    .frame(width: 32, height: 19)
                Circle()
                    .fill(.white)
                    .frame(width: 15, height: 15)
                    .padding(.horizontal, 2)
            }
            .frame(width: 32, height: 19)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// `GhostButtonStyle` reskinned in warm tokens — same soft-accent pairing
/// the mockup itself uses for its "Update available" pill.
private struct WarmGhostButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.manrope(11.5, .semibold))
            .foregroundStyle(Palette.sunsetDeep)
            .padding(.horizontal, 11)
            .padding(.vertical, 6)
            .background(Palette.sunsetSoft, in: RoundedRectangle(cornerRadius: Radius.sm))
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
    }
}

/// Reports each `AccentFieldSelect` trigger's on-screen bounds, keyed by
/// its `id`, up to the page-level `.overlayPreferenceValue` that actually
/// draws the open panel — see that call site for why the panel can't just
/// be a plain `.overlay` on the trigger itself.
private struct DropdownAnchorKey: PreferenceKey {
    static var defaultValue: [String: Anchor<CGRect>] = [:]
    static func reduce(value: inout [String: Anchor<CGRect>], nextValue: () -> [String: Anchor<CGRect>]) {
        value.merge(nextValue()) { _, new in new }
    }
}

/// Positions and sizes the floating options panel for whichever dropdown
/// is open. Deliberately its own `View` rather than an inline closure in
/// `SettingsPage.body`: `@Environment` is resolved by a view's position in
/// the *rendered tree*, not by where a line of code textually sits, so
/// reading `\.tooltipClipBounds` from a property on `SettingsPage` itself
/// silently returned nil — `SettingsPage` sits *above* `ThinScrollView` in
/// the hierarchy, and `ThinScrollView` is what actually sets that value,
/// only for views nested inside it. This struct is constructed from
/// inside `.overlayPreferenceValue`, which *is* nested inside
/// `ThinScrollView`'s content, so its own `@Environment` read here
/// resolves correctly. Concretely, that bug meant the panel always
/// believed it had infinite room below the trigger, so it opened
/// downward unconditionally and simply ran off the bottom of the window
/// whenever real content was too tall to fit.
private struct DropdownPanel: View {
    let openDropdown: String
    let anchor: Anchor<CGRect>
    let options: [String]
    let label: (String) -> String
    let selection: Binding<String>
    let close: () -> Void

    @Environment(\.tooltipClipBounds) private var clipBounds

    var body: some View {
        GeometryReader { proxy in
            let rect = proxy[anchor]
            // The visible viewport's bottom edge, converted from
            // `clipBounds`' global space into this GeometryReader's own
            // local space, so it's directly comparable to `rect`.
            let viewportMaxY = (clipBounds?.maxY ?? .infinity)
                - proxy.frame(in: .global).minY
            let viewportHeight = clipBounds?.height ?? .greatestFiniteMagnitude
            let searchFieldHeight: CGFloat = openDropdown == "language" ? 50 : 0
            // The list's own ideal height, from its *actual* option count
            // — Language used to hardcode 396 here regardless of how many
            // locales were really on offer, which broke the moment
            // Parakeet v2 (English-only) narrowed it down to 2 options:
            // the estimate stayed at "whole page's worth," so the card
            // rendered huge with almost nothing in it. Per-row, not a flat
            // multiply: at this card's width (max 320pt, minus padding),
            // a label past ~38 characters wraps to two lines — measured
            // against "Parakeet v3 — multilingual (10 languages), ~600 MB"
            // (52 chars) actually clipping its second line at 36pt/row.
            // Model/engine labels routinely run this long; locale names
            // never do, so this only ever affects the non-Language lists.
            let rowHeight: (String) -> CGFloat = { label($0).count > 38 ? 56 : 36 }
            let idealContentHeight = options.reduce(0) { $0 + rowHeight($1) } + 12 + searchFieldHeight
            let availableBelow = max(0, viewportMaxY - rect.maxY - 6)
            let availableAbove = max(0, rect.minY - 6)
            let opensUpward = availableBelow < idealContentHeight
                && availableAbove > availableBelow
            // A *sensible* size, not just whatever happens to be free —
            // capped at half the visible viewport regardless of how much
            // *more* room a direction has: a short list opening upward
            // from low on a tall page had the whole page above it to use,
            // which is exactly why it rendered as a mostly-empty card
            // stretching nearly to the top. This only ever shrinks
            // `idealContentHeight` down for the *card's own size*
            // (`listHeight` below) — it must stay completely separate
            // from the positioning math right below, which needs the
            // real, uncapped distance to the trigger to line up against
            // it; conflating the two once already sent every panel
            // floating off to some fixed spot unrelated to its trigger.
            let sizeCap = max(160, min(
                opensUpward ? availableAbove : availableBelow, viewportHeight / 2))
            let listHeight = max(100, min(idealContentHeight, sizeCap) - searchFieldHeight)

            ZStack(alignment: .topLeading) {
                // Click-outside-to-dismiss: far bigger than any real
                // screen so it covers the window regardless of where the
                // trigger sits, invisible but still hit-testable via
                // `contentShape`. Declared first so the panel below —
                // drawn after, i.e. on top — intercepts its own clicks
                // instead of this catcher swallowing them.
                Color.clear
                    .frame(width: 6000, height: 6000)
                    .contentShape(Rectangle())
                    .onTapGesture(perform: close)
                    .offset(x: -3000, y: -3000)
                // Trailing-aligned to the trigger's own right edge without
                // needing to know the panel's width up front: proposing a
                // container exactly `rect.maxX` wide (from the content
                // area's left edge to the trigger's right edge) and
                // right-aligning within it puts the panel's own right
                // edge flush with the trigger's, however wide the panel
                // ends up being — a fixed guessed offset undershot for a
                // long label like "Parakeet v2 — English, highest recall,
                // ~600 MB" and ran the panel past the window's edge. The
                // vertical side uses the same trick: rather than subtract
                // an estimated panel height to position it (compounding
                // that estimate's own error), bottom-aligning within a
                // frame that ends exactly at the trigger's top edge lets
                // the panel's *real* height determine how far upward it
                // grows.
                HStack(spacing: 0) {
                    Spacer(minLength: 0)
                    AccentFieldSelectList(
                        options: options,
                        label: label,
                        selection: selection,
                        close: close,
                        showsSearch: openDropdown == "language",
                        listHeight: listHeight)
                        .frame(height: opensUpward ? max(0, rect.minY - 6) : nil,
                               alignment: .bottom)
                }
                .frame(width: max(1, rect.maxX))
                .offset(y: opensUpward ? 0 : rect.maxY + 6)
            }
        }
    }
}

/// The canvas's dedicated `Dropdown` component. Originally reserved for
/// just the two choices the mockup itself gives the treatment
/// (recognition engine, model) — Dictation key and Language used a
/// plainer, now-deleted `WarmFieldSelect` instead — but that inconsistency
/// read as leftover old UI once the rest of the page moved to this one, so
/// every dropdown on the page now shares it.
///
/// Deliberately not `.popover` — a native macOS popover always draws its
/// own arrow/caret pointing back at the trigger, which read as "old
/// system style" next to the mockup's plain floating card with no arrow
/// at all. Deliberately not a plain `.overlay` on the trigger either —
/// that only ever paints above its own host view, so a later sibling row
/// (e.g. the Parakeet-model trigger sitting right below the open
/// Recognition-engine panel) still drew on top of it. This only reports
/// *where* the trigger is via `.anchorPreference`; the panel itself is
/// drawn once, at the whole-page level, by `SettingsPage.body`'s own
/// `.overlayPreferenceValue` — see that for the actual positioning.
///
/// Also differs from `WarmFieldSelect` in that the trigger's accent
/// border and chevron color only appear while open — both mockup
/// illustrations of this only ever show the accent state *together with*
/// the panel already open, never at rest, and the closed/idle look
/// should match every other trigger on the page — and the selected row
/// in the panel carries a permanent tinted background plus a checkmark
/// instead of relying on hover alone to show which option is current.
/// No drop shadow on the panel, by request — overriding the mockup's own
/// (which does specify one), same no-shadow call as every other
/// floating/card element in this redesign. The mockup's own
/// `Dropdown.dc.html` also adds a search field, but only for its
/// Language illustration — a handful of engine/model options doesn't
/// need one, and the screenshot this was requested from shows none.
private struct AccentFieldSelect: View {
    let id: String
    let label: String
    @Binding var openID: String?

    private var isOpen: Bool { openID == id }

    var body: some View {
        Button {
            withAnimation(.murmurEase(0.12)) { openID = isOpen ? nil : id }
        } label: {
            HStack(spacing: 6) {
                Text(label)
                Image(systemName: isOpen ? "chevron.up" : "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
            }
            .font(.manrope(12, .medium))
            .foregroundStyle(isOpen ? Palette.sunsetDeep : Palette.warmInk)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.white, in: RoundedRectangle(cornerRadius: Radius.sm))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.sm)
                    .stroke(isOpen ? Palette.sunset : Palette.warmRowBorder, lineWidth: isOpen ? 1.5 : 1))
        }
        .buttonStyle(.plain)
        .fixedSize()
        .anchorPreference(key: DropdownAnchorKey.self, value: .bounds) { [id: $0] }
    }
}

private struct AccentFieldSelectList: View {
    let options: [String]
    let label: (String) -> String
    @Binding var selection: String
    let close: () -> Void
    /// Only Language needs this — a couple dozen locales is the one list
    /// on this page long enough to warrant filtering, matching the
    /// mockup's own `Dropdown.dc.html`, which only ever illustrates the
    /// search field on its Language example, not a generic dropdown
    /// feature every instance gets.
    var showsSearch = false
    /// The options list's *exact* rendered height, computed by the caller
    /// (`DropdownPanel`) from the option count and available space —
    /// applied directly rather than as a maximum. A plain `ScrollView`
    /// fills whatever height it's offered instead of shrinking to fit
    /// short content, so a bare max-height cap alone left a 2-option list
    /// rendering as a mostly-empty card the full size of the cap.
    var listHeight: CGFloat = 336
    @State private var hovered: String?
    @State private var searchText = ""

    private var filteredOptions: [String] {
        guard showsSearch, !searchText.isEmpty else { return options }
        return options.filter { label($0).localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if showsSearch {
                searchField
                Rectangle().fill(Palette.warmRowBorder).frame(height: 1)
            }
            // `ThinScrollView`, not a plain `ScrollView` — see
            // ScratchpadView.swift's own note on why: a bare
            // `.scrollIndicators(.hidden)` doesn't reliably suppress
            // macOS's native scroller by itself. Applied unconditionally
            // now, not just for Language.
            ThinScrollView {
                optionsList.padding(6)
            }
            .frame(height: listHeight)
        }
        // `maxWidth`, not just `minWidth` — without a cap, the `Spacer`
        // pushing each row's checkmark to the trailing edge had unlimited
        // room to expand into and stretched the whole panel across most
        // of the page instead of hugging its content.
        .frame(minWidth: 220, maxWidth: 320)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .environment(\.colorScheme, .light)
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            MurmurIconView(icon: .search)
                .frame(width: 13, height: 13)
                .foregroundStyle(Palette.warmInkFaint)
            TextField("Search languages…", text: $searchText)
                .textFieldStyle(.plain)
                .font(.manrope(12.5))
                .foregroundStyle(Palette.warmInk)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        // `#F7F5F0` in the mockup — happens to be the exact same value as
        // `homeGradientBottom`, reused here rather than adding a new
        // one-off token for a single search field.
        .background(Palette.homeGradientBottom, in: RoundedRectangle(cornerRadius: Radius.sm))
        .padding(10)
    }

    private var optionsList: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(filteredOptions, id: \.self) { option in
                let isSelected = option == selection
                Button {
                    selection = option
                    close()
                } label: {
                    HStack {
                        Text(label(option))
                            .font(.manrope(13, isSelected ? .medium : .regular))
                            .foregroundStyle(Palette.warmInk)
                        Spacer(minLength: 12)
                        if isSelected {
                            MurmurIconView(icon: .check)
                                .frame(width: 13, height: 13)
                                .foregroundStyle(Palette.sunset)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 9)
                    .background(
                        isSelected ? Palette.sunsetSoft
                            : (hovered == option ? Palette.warmRowBorder : Color.clear),
                        in: RoundedRectangle(cornerRadius: Radius.sm))
                }
                .buttonStyle(.plain)
                .onHover { inside in hovered = inside ? option : nil }
            }
        }
    }
}
