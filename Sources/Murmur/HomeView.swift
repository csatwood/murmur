import AppKit
import SwiftUI

// MARK: - Home
//
// Redesigned per the "Main" canvas (Main.dc.html): the capture zone becomes
// a warm sunset-gradient hero instead of the old dark banner, and the whole
// page now sits on its own frosted glass panel over a sage-to-cream
// backdrop rather than the shell's flat panel background. Every store call
// and binding is unchanged from the previous implementation — this is a
// View-layer rewrite only.

struct HomePage: View {
    @ObservedObject var app: AppDelegate
    @Binding var page: Page
    @State private var searchText = ""
    @State private var searchOpen = false
    @State private var showClearConfirm = false
    @State private var editingEntry: HistoryEntry?
    @State private var editText = ""
    @State private var learnFeedback: String?

    var body: some View {
        GlassPanelPage {
            VStack(alignment: .leading, spacing: 20) {
                captureZone
                statStrip
                historySection
            }
        }
        .sheet(item: $editingEntry) { entry in correctionSheet(entry) }
    }

    // MARK: Capture zone

    /// One warm sunset-gradient surface with one job: show what Murmur last
    /// captured, at headline scale, with a live status readout above it and
    /// the waveform beside it. Replaces the old promotional banner — this
    /// is the actual "hero" now, not a CTA card competing with a data
    /// dashboard beside it.
    ///
    /// Headline text is dark ink, not white — unlike the old near-black
    /// banner, this surface is a light-toned gradient (sunset orange
    /// fading to peach), so `Palette.warmInk` reads correctly here while
    /// `Palette.ink`/`onInk` (tuned for the shell's own light/dark surfaces)
    /// would not.
    private var captureZone: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center) {
                HStack(spacing: 8) {
                    PulsingDot(
                        color: app.uiState == .idle ? .white.opacity(0.7) : Palette.warmInk,
                        size: 6, maxScale: 2.2, active: app.uiState != .idle)
                    Text(captureStatusLabel.uppercased())
                        .font(.manrope(10, .bold))
                        .kerning(0.9)
                        .foregroundStyle(.white.opacity(0.78))
                }
                Spacer()
                // A plain Keycap here just displayed the hotkey; this
                // needs to also let you change it without a trip to
                // Settings — same underlying `app.hotkey`/`setHotkey`
                // Settings already drives (SettingsView.swift's own
                // "Dictation key" row), just reachable from the one place
                // you're already looking at when you'd want to change it.
                FieldSelect(
                    options: HotkeyMonitor.Hotkey.allCases,
                    label: { "Hold \($0.displayName)" },
                    selection: Binding(
                        get: { app.hotkey },
                        set: { app.setHotkey($0) }),
                    tint: .white,
                    background: .white.opacity(0.2),
                    borderColor: .white.opacity(0.28))
            }
            // Side by side, not stacked: the headline anchors the left
            // edge and takes whatever width is left over once the
            // waveform's own fixed size is reserved on the right, so the
            // two read as one deliberately composed row instead of a
            // block of text with a small animation floating somewhere
            // beneath it.
            HStack(alignment: .center, spacing: 36) {
                Text(Self.captureHeadline)
                    .font(.manrope(33, .medium))
                    .tracking(-0.66)
                    .lineSpacing(8)
                    .lineLimit(3)
                    .foregroundStyle(Palette.warmInk)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                HeroCaptureWaveform()
            }
            .padding(.top, 22)
        }
        .padding(.horizontal, 32)
        .padding(.vertical, 28)
        .background(Palette.homeHeroGradient, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .shadow(color: .black.opacity(0.04), radius: 1, y: 1)
        .shadow(color: .black.opacity(0.06), radius: 16, y: 16)
    }

    /// "Ready"/"Listening" wording, matching what `StatusHUD.swift`
    /// already established for ambient, HUD-style status — this surface
    /// is now the app's one titlebar-adjacent status readout (the old
    /// titlebar `StatusPill` duplicated it and was removed).
    private var captureStatusLabel: String {
        if let status = app.transformStatus { return status }
        switch app.uiState {
        case .idle: return "Ready"
        case .recording: return app.isHandsFree ? "Listening — hands-free" : "Listening"
        case .processing: return "Working"
        }
    }

    /// A fixed brand line, matching Main.dc.html's own copy exactly
    /// (explicit line breaks, not natural wrapping) — not the user's own
    /// recent dictation, which would duplicate the history list directly
    /// beneath it. Names Murmur's own two most-differentiated pillars
    /// specifically: per-app formatting and on-device privacy.
    private static let captureHeadline =
        "Speak naturally.\nMurmur formats it for every app,\nright on your Mac."

    // MARK: Stat strip

    /// Words-today, wpm, and streak used to be two boxed `Card`s with big
    /// colored numerals fighting the capture zone for top billing. One
    /// quiet inline row instead — the trend arrow and the 7-day pip strip
    /// stay on Insights, which already exists for exactly this, rather
    /// than duplicating them here too.
    private var statStrip: some View {
        HStack(spacing: 20) {
            statItem(wordsToday.formatted(), "words today")
            stripDivider
            if let wpm = wpmToday {
                statItem("\(wpm)", "wpm")
                stripDivider
            }
            statItem("\(dayStreak)", dayStreak == 1 ? "day streak" : "day streak")
            Spacer()
            Button { page = .appProfiles } label: {
                Text("Dictate differently per app →")
                    .font(.manrope(13, .medium))
                    .foregroundStyle(Palette.sunsetDeep)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 4)
    }

    private func statItem(_ value: String, _ label: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Text(value)
                .font(.manrope(17, .medium))
                .tracking(-0.3)
                .monospacedDigit()
                .foregroundStyle(Palette.warmInk)
            Text(label)
                .font(.manrope(11.5))
                .foregroundStyle(Palette.warmInkSoft)
        }
    }

    private var stripDivider: some View {
        Rectangle().fill(Palette.warmDivider).frame(width: 1, height: 14)
    }

    // MARK: History
    //
    // No card of its own anymore — by request, this now lives directly on
    // the glass panel instead of a separate white surface floating inside
    // it. `warmRowBorder`'s near-white hairline read fine against solid
    // white but all but disappeared against the frosted, gradient-tinted
    // material, so row dividers switched to `glassDivider` (a translucent
    // black that keeps working regardless of exactly what's blurred behind
    // it); the faintest ink/dot tones moved one step darker for the same
    // reason.

    /// Fills whatever height the hero and stat strip leave behind.
    private var historySection: some View {
        VStack(alignment: .leading, spacing: 0) {
            historyHeader
            ThinScrollView(bottomInset: 12) {
                historyRows
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// Stays fixed above the scrolling list.
    private var historyHeader: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                // Each day group below carries its own label ("Today",
                // "July 12, 2026", …) — a static label here would either
                // repeat the first one or, worse, go stale exactly like
                // the old fixed "Today" did once the list scrolled past
                // it. "Results" is the one case worth stating up front,
                // since a search match isn't otherwise obvious from the
                // day grouping alone.
                if searchOpen && !searchText.isEmpty {
                    Text("RESULTS")
                        .font(.manrope(10, .semibold))
                        .kerning(0.9)
                        .foregroundStyle(Palette.warmInkSoft)
                }
                Spacer()
                if showClearConfirm {
                    Text("Clear all \(app.entries.count) transcript\(app.entries.count == 1 ? "" : "s")? This can't be undone.")
                        .font(.manrope(12))
                        .foregroundStyle(Palette.warmInkSoft)
                    Button("Cancel") { showClearConfirm = false }
                        .buttonStyle(GhostButtonStyle())
                    Button("Clear History") {
                        app.clearHistoryEntries()
                        showClearConfirm = false
                    }
                    .buttonStyle(DangerButtonStyle())
                } else {
                    if searchOpen {
                        HStack(spacing: 8) {
                            MurmurIconView(icon: .search)
                                .frame(width: 13, height: 13)
                                .foregroundStyle(Palette.warmInkFaint)
                            TextField("Search transcripts", text: $searchText)
                                .textFieldStyle(.plain)
                                .font(.manrope(12.5))
                                .foregroundStyle(Palette.warmInk)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Palette.warmRowBorder, in: RoundedRectangle(cornerRadius: Radius.sm))
                        .overlay(RoundedRectangle(cornerRadius: Radius.sm).stroke(Palette.warmDivider, lineWidth: 1))
                        .frame(width: 200)
                    }
                    IconButton(icon: searchOpen ? .plus : .search,
                               rotated: searchOpen,
                               help: searchOpen ? "Close search" : "Search transcripts") {
                        searchOpen.toggle()
                        if !searchOpen { searchText = "" }
                    }
                    IconButton(icon: .trash, help: "Clear all history") {
                        showClearConfirm = true
                    }
                }
            }
            .padding(.bottom, 14)

            if let feedback = learnFeedback {
                HStack(spacing: 6) {
                    MurmurIconView(icon: .check).frame(width: 12, height: 12)
                    Text(feedback).font(.manrope(12, .medium))
                }
                .foregroundStyle(Palette.sunsetDeep)
                .padding(.bottom, 10)
                .task {
                    try? await Task.sleep(nanoseconds: 5_000_000_000)
                    learnFeedback = nil
                }
            }
        }
    }

    /// The only part of Home that scrolls. Grouped by calendar day — the
    /// fixed header above can only ever say one static thing, which is
    /// what let a flat, ungrouped list read as if everything in it were
    /// from today even once older days scrolled into view. Each row now
    /// carries a small leading dot and its own hairline top rule (matching
    /// the mockup) instead of the old per-day bordered/filled card — the
    /// dot is only lit (sunset orange) on the single newest entry across
    /// the whole list, not once per day.
    ///
    /// Flattened into one `ForEach` (day labels and entries as siblings)
    /// rather than a `ForEach` of day-groups each containing its own
    /// nested `ForEach` of rows — `LazyVStack` only lazily instantiates
    /// its own *direct* children, so the nested version made it treat an
    /// entire day (however many transcripts that turned out to be) as one
    /// unsplittable unit of work instead of one row at a time.
    private var historyRows: some View {
        VStack(alignment: .leading, spacing: 0) {
            if app.entries.isEmpty {
                emptyState(
                    "No transcripts yet — click into any text field, hold \(app.hotkey.displayName), and speak.")
            } else if filteredEntries.isEmpty {
                emptyState("No transcripts match “\(searchText)”.")
            } else {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(flatHistoryRows.enumerated()), id: \.element.id) { index, row in
                        switch row {
                        case .day(let date):
                            daySectionLabel(date, isFirst: index == 0)
                        case .entry(let entry):
                            HistoryRowView(
                                entry: entry,
                                isNewest: entry.id == newestEntryID,
                                onCopy: {
                                    let pb = NSPasteboard.general
                                    pb.clearContents()
                                    pb.setString(entry.text, forType: .string)
                                },
                                onCorrect: {
                                    editText = entry.text
                                    editingEntry = entry
                                },
                                onTemplate: {
                                    app.pendingTemplateText = entry.text
                                    page = .templates
                                },
                                onDelete: { app.deleteHistoryEntry(id: entry.id) })
                        }
                    }
                }
            }
        }
    }

    private func daySectionLabel(_ day: Date, isFirst: Bool) -> some View {
        Text(dayLabel(day).uppercased())
            .font(.manrope(10, .semibold))
            .kerning(0.9)
            .foregroundStyle(Palette.warmInkSoft)
            .padding(.top, isFirst ? 0 : 14)
            .padding(.bottom, 6)
    }

    private func emptyState(_ text: String) -> some View {
        Text(text)
            .font(.manrope(12.5))
            .italic()
            .foregroundStyle(Palette.warmInkFaint)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 28)
            .background(Palette.warmRowBorder, in: RoundedRectangle(cornerRadius: Radius.lg))
    }

    private func correctionSheet(_ entry: HistoryEntry) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Correct this transcript").font(.manrope(15, .semibold))
            Text("Fix what Murmur misheard. It compares your fix with the "
                 + "original and learns the corrections for future dictations.")
                .font(.manrope(12))
                .foregroundStyle(Palette.inkSoft)
            TextEditor(text: $editText)
                .font(.manrope(13))
                .scrollContentBackground(.hidden)
                .padding(10)
                .frame(width: 460, height: 140)
                .background(Palette.card, in: RoundedRectangle(cornerRadius: Radius.md))
            HStack {
                Spacer()
                Button("Cancel") { editingEntry = nil }
                Button("Save & Learn") {
                    let learnedCount = app.correctHistoryEntry(id: entry.id, newText: editText)
                    learnFeedback = learnedCount > 0
                        ? "Learned \(learnedCount) correction\(learnedCount == 1 ? "" : "s") from your fix."
                        : "Transcript updated."
                    editingEntry = nil
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
    }

    // MARK: Derived data

    private var filteredEntries: [HistoryEntry] {
        HistoryStore.matching(searchText, in: app.entries)
    }

    /// `filteredEntries` grouped by calendar day, most recent day first.
    /// `app.entries` (and so `filteredEntries`) is already newest-first —
    /// appending each day the first time it's seen preserves that order
    /// for the groups too, with no separate sort needed.
    private var groupedEntries: [(day: Date, entries: [HistoryEntry])] {
        let calendar = Calendar.current
        var order: [Date] = []
        var byDay: [Date: [HistoryEntry]] = [:]
        for entry in filteredEntries {
            let day = calendar.startOfDay(for: entry.date)
            if byDay[day] == nil { order.append(day) }
            byDay[day, default: []].append(entry)
        }
        return order.map { (day: $0, entries: byDay[$0] ?? []) }
    }

    /// The id of the single most recent entry across every group — what
    /// `HistoryRowView` uses to decide which one row (not one per day) gets
    /// the accent treatment.
    private var newestEntryID: String? {
        groupedEntries.first?.entries.first?.id
    }

    /// `groupedEntries` flattened into one list of day-labels and entries
    /// as equal siblings, so `historyRows`' `ForEach` can hand `LazyVStack`
    /// one row at a time instead of one whole day at a time.
    private var flatHistoryRows: [HistoryListRow] {
        groupedEntries.flatMap { group in
            [.day(group.day)] + group.entries.map { .entry($0) }
        }
    }

    private func dayLabel(_ day: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(day) { return "Today" }
        if calendar.isDateInYesterday(day) { return "Yesterday" }
        return day.formatted(.dateTime.month(.abbreviated).day())
    }

    private func words(on day: Date) -> Int {
        let calendar = Calendar.current
        return app.entries
            .filter { calendar.isDate($0.date, inSameDayAs: day) }
            .reduce(0) { $0 + $1.wordCount }
    }

    private var wordsToday: Int { words(on: Date()) }

    /// Words per minute across today's timed dictations only. The trend
    /// vs. yesterday and the 7-day pip strip that used to sit alongside
    /// these numbers stay on Insights, which already exists for exactly
    /// this — Home's stat strip is a teaser, not a second copy of it.
    private var wpmToday: Int? {
        let calendar = Calendar.current
        let timed = app.entries.filter {
            calendar.isDateInToday($0.date) && ($0.duration ?? 0) > 1
        }
        let seconds = timed.reduce(0.0) { $0 + ($1.duration ?? 0) }
        guard seconds > 0 else { return nil }
        let words = timed.reduce(0) { $0 + $1.wordCount }
        return Int(Double(words) / (seconds / 60))
    }

    private var dayStreak: Int {
        let calendar = Calendar.current
        let days = Set(app.entries.map { calendar.startOfDay(for: $0.date) })
        var day = calendar.startOfDay(for: Date())
        if !days.contains(day) {
            day = calendar.date(byAdding: .day, value: -1, to: day)!
        }
        var streak = 0
        while days.contains(day) {
            streak += 1
            day = calendar.date(byAdding: .day, value: -1, to: day)!
        }
        return streak
    }

}

/// One flattened item of `historyRows`' single `ForEach` — a day-section
/// label or a transcript, as equal siblings (see `flatHistoryRows`).
private enum HistoryListRow: Identifiable {
    case day(Date)
    case entry(HistoryEntry)

    var id: String {
        switch self {
        case .day(let date): return "day-\(date.timeIntervalSince1970)"
        case .entry(let entry): return entry.id
        }
    }
}

// MARK: - History row

/// Its own `View` rather than a method on `HomePage` returning `some View`,
/// specifically so `hovering` is local `@State` scoped to one row instead
/// of a single `String?` shared on `HomePage` for every row to compare
/// itself against. With the shared version, scrolling the list under a
/// stationary cursor fires an enter/exit on every row that passes under
/// it, and each one reassigned `HomePage`'s own state — which invalidated
/// `HomePage.body` and re-evaluated every row in the list on every single
/// one of those events, not just the row whose own hover actually changed.
/// A real `View` type gives SwiftUI a stable identity to diff against, so
/// a hover change here only ever re-renders this one row.
private struct HistoryRowView: View {
    let entry: HistoryEntry
    let isNewest: Bool
    let onCopy: () -> Void
    let onCorrect: () -> Void
    let onTemplate: () -> Void
    let onDelete: () -> Void

    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Rectangle().fill(Palette.glassDivider).frame(height: 1)
            HStack(alignment: .top, spacing: 13) {
                // No leading dot — just the time, top-aligned with the
                // entry text so both start at the same line regardless of
                // whether the text wraps to a second line.
                Text(entry.date, format: .dateTime.hour().minute())
                    .font(.manrope(12, .semibold))
                    .foregroundStyle(isNewest ? Palette.sunsetDeep : Palette.warmInkSoft)
                    // `font-variant-numeric: tabular-nums`. Verified Manrope
                    // ships Monospaced Numbers, so this stays in Manrope
                    // rather than falling back to a substitute face.
                    .monospacedDigit()
                    .frame(width: 40, alignment: .leading)
                Text(entry.text.replacingOccurrences(of: "\n", with: " "))
                    .font(.manrope(13))
                    .lineSpacing(4)
                    .foregroundStyle(isNewest ? Palette.warmInk : Palette.warmInkSoft)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                // Actions stay laid out and only fade, so hovering a row
                // never reflows its text.
                HStack(spacing: 6) {
                    IconButton(icon: .copy, help: "Copy", action: onCopy)
                    IconButton(icon: .edit, help: "Correct & learn", action: onCorrect)
                    IconButton(icon: .tpl, help: "Turn into a note", action: onTemplate)
                    IconButton(icon: .trash, help: "Delete", action: onDelete)
                }
                .opacity(hovering ? 1 : 0)
                .animation(.easeOut(duration: 0.1), value: hovering)
            }
            // No leading inset — the dot that used to want a little room
            // from the edge is gone, so the time column now sits flush
            // with the day-section label above it.
            .padding(.trailing, 6)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: Radius.sm)
                    .fill(hovering ? Palette.cardHover : Color.clear))
            // Without an explicit hit-testable shape, SwiftUI only counts
            // actually-drawn content (the text glyphs) as hoverable when the
            // background is .clear — the padding and inter-column gaps read as
            // "not part of the view" for hover purposes until the background
            // is already filled, so entering the row anywhere but directly on
            // the text failed to reveal the actions. This makes the whole
            // padded frame one hoverable region regardless of what's drawn.
            .contentShape(Rectangle())
            .onHover { hovering = $0 }
        }
    }
}

// MARK: - Hero waveform

/// Home hero's own waveform — distinct from the app-wide `CaptureWaveform`
/// (DesignSystem.swift), which keeps its dark-surface, lime-center look for
/// Onboarding. This one matches Main.dc.html's `.hero-bar`s: 13 bars,
/// heights mirrored around the centre but colors graded from a muted
/// translucent ink at the edges up through the hero gradient's own sunset
/// tones at the peak, animated as a `scaleY` breathe (CSS `heroWave`)
/// rather than a height change.
private struct HeroCaptureWaveform: View {
    var active: Bool = true

    @State private var tall = false

    private static let mutedBar = Color.black.opacity(0.16)
    private static let bars: [(height: CGFloat, color: Color, delay: Double)] = [
        (16, mutedBar, 0),
        (32, mutedBar, 0.06),
        (48, mutedBar, 0.12),
        (64, Palette.sunsetPale, 0.18),
        (45, mutedBar, 0.24),
        (80, Palette.sunsetMid, 0.30),
        (100, Palette.sunset, 0.36),
        (80, Palette.sunsetMid, 0.30),
        (45, Palette.sunsetPale, 0.24),
        (64, mutedBar, 0.18),
        (48, mutedBar, 0.12),
        (32, mutedBar, 0.06),
        (16, mutedBar, 0),
    ]

    var body: some View {
        HStack(alignment: .center, spacing: 6) {
            ForEach(Array(Self.bars.enumerated()), id: \.offset) { _, bar in
                Capsule()
                    .fill(bar.color)
                    .frame(width: 6, height: bar.height)
                    .scaleEffect(y: tall ? 1 : 0.55, anchor: .center)
                    .animation(
                        tall
                            ? .easeInOut(duration: 1.1).repeatForever(autoreverses: true).delay(bar.delay)
                            : .easeOut(duration: 0.3),
                        value: tall)
            }
        }
        .frame(height: 108)
        .onAppear { tall = active }
        .onChange(of: active) { _, isActive in tall = isActive }
    }
}

// MARK: - Button styles

struct GhostButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.manrope(11.5, .semibold))
            .foregroundStyle(Palette.accentText)
            .padding(.horizontal, 11)
            .padding(.vertical, 6)
            .background(Palette.accentSoft, in: RoundedRectangle(cornerRadius: Radius.sm))
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
    }
}

struct DangerButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.manrope(11.5, .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 11)
            .padding(.vertical, 6)
            .background(Palette.danger, in: RoundedRectangle(cornerRadius: Radius.sm))
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
    }
}
