import AppKit
import SwiftUI

// MARK: - Home
//
// Ported 1:1 from the approved design mockup: dark banner with waveform,
// three stat cards (words today + trend + wpm, streak with day pills,
// voice profile), and the history feed with working search / clear-all /
// per-row actions. Every store call and binding is unchanged from the
// previous implementation — this is a View-layer rewrite only.

struct HomePage: View {
    @ObservedObject var app: AppDelegate
    @Binding var page: Page
    @State private var searchText = ""
    @State private var searchOpen = false
    @State private var showClearConfirm = false
    @State private var hoveredRow: String?
    @State private var editingEntry: HistoryEntry?
    @State private var editText = ""
    @State private var learnFeedback: String?

    // Only the transcript list scrolls. The capture zone, the stat strip,
    // and the "Today" header with its search/clear actions all stay put —
    // scrolling the entire page to reach older transcripts meant losing
    // every fixed reference point on the screen at once.
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            captureZone
            statStrip
            historyHeader
            ThinScrollView(bottomInset: 24) {
                historyRows
            }
        }
        .padding(.top, 24)
        .padding(.bottom, 24)
        .frame(maxHeight: .infinity, alignment: .top)
        .sheet(item: $editingEntry) { entry in correctionSheet(entry) }
    }

    // MARK: Capture zone

    /// One dark surface with one job: show what Murmur last captured, at
    /// headline scale, with a live status readout above it and the
    /// waveform beneath. Replaces the old promotional banner — this is
    /// the actual "hero" now, not a CTA card competing with a data
    /// dashboard beside it.
    ///
    /// `Palette.heroSurface`, not a fixed `Color`: dark and light app
    /// appearance need genuinely different fills here (see that token's
    /// own comment — a dark card needs to sit *lighter* than an
    /// already-dark page to read as elevated, since shadows don't work
    /// once nothing nearby is lighter to contrast against). Either way
    /// this surface stays dark enough that its own content still uses
    /// fixed white-based colors below, not `Palette.onInk` — that token
    /// flips to a near-black value in dark mode (since it's meant for
    /// text on `Palette.ink`, which itself flips), which would go
    /// dark-on-dark here.
    private var captureZone: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center) {
                HStack(spacing: 8) {
                    PulsingDot(
                        color: app.uiState == .idle ? .white.opacity(0.4) : Palette.accent,
                        size: 6, maxScale: 2.2, active: app.uiState != .idle)
                    Text(captureStatusLabel.uppercased())
                        .font(.manrope(10.5, .semibold))
                        .kerning(0.8)
                        .foregroundStyle(.white.opacity(0.5))
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
                    tint: .white.opacity(0.7),
                    background: .white.opacity(0.08),
                    borderColor: .white.opacity(0.14))
            }
            // Side by side, not stacked: the headline anchors the left
            // edge and takes whatever width is left over once the
            // waveform's own fixed size is reserved on the right, so the
            // two read as one deliberately composed row instead of a
            // block of text with a small animation floating somewhere
            // beneath it.
            HStack(alignment: .center, spacing: 32) {
                Text(Self.captureHeadline)
                    .font(.manrope(46, .regular))
                    .tracking(-1.3)
                    .lineSpacing(2)
                    .lineLimit(3)
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                CaptureWaveform(active: true, color: .white)
            }
            .padding(.top, 28)
        }
        .padding(.horizontal, 44)
        .padding(.vertical, 40)
        .background(Palette.heroSurface, in: RoundedRectangle(cornerRadius: Radius.xl))
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

    /// A fixed brand line, not the user's own recent dictation — that
    /// duplicated the history list directly beneath it. Names Murmur's
    /// own two most-differentiated pillars specifically (per-app
    /// formatting was already the old banner's primary pitch; on-device
    /// privacy is the app's core premise), rather than the borrowed
    /// murmurmac.com placeholder, which was evocative but generic enough
    /// that any dictation app could claim it.
    private static let captureHeadline =
        "Speak naturally. Murmur formats it for every app — right on your Mac."

    // MARK: Stat strip

    /// Words-today, wpm, and streak used to be two boxed `Card`s with big
    /// colored numerals fighting the capture zone for top billing. One
    /// quiet inline row instead — the trend arrow and the 7-day pip strip
    /// stay on Insights, which already exists for exactly this, rather
    /// than duplicating them here too.
    private var statStrip: some View {
        HStack(spacing: 24) {
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
                    .font(.manrope(11.5, .semibold))
                    .foregroundStyle(Palette.accentText)
            }
            .buttonStyle(.plain)
        }
    }

    private func statItem(_ value: String, _ label: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Text(value)
                .font(.manrope(18, .semibold))
                .tracking(-0.3)
                .foregroundStyle(Palette.ink)
            Text(label)
                .font(.manrope(11.5))
                .foregroundStyle(Palette.inkFaint)
        }
    }

    private var stripDivider: some View {
        Rectangle().fill(Palette.border).frame(width: 1, height: 15)
    }

    // MARK: History

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
                        .font(.manrope(11, .medium))
                        .kerning(0.7)
                        .foregroundStyle(Palette.inkSoft)
                }
                Spacer()
                if showClearConfirm {
                    Text("Clear all \(app.entries.count) transcript\(app.entries.count == 1 ? "" : "s")? This can't be undone.")
                        .font(.manrope(12))
                        .foregroundStyle(Palette.inkSoft)
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
                                .foregroundStyle(Palette.inkFaint)
                            TextField("Search transcripts", text: $searchText)
                                .textFieldStyle(.plain)
                                .font(.manrope(12.5))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Palette.panel, in: RoundedRectangle(cornerRadius: Radius.sm))
                        .overlay(RoundedRectangle(cornerRadius: Radius.sm).stroke(Palette.border, lineWidth: 1))
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
            // No top padding here — the outer body VStack's own spacing
            // (between statStrip and this header) already provides the
            // gap. This used to sit directly under the old dark banner
            // with nothing else between them, so its own 26pt top pad was
            // the only spacing; now it stacks with the body VStack's
            // spacing on top of it, doubling the gap.
            .padding(.bottom, 10)

            if let feedback = learnFeedback {
                HStack(spacing: 6) {
                    MurmurIconView(icon: .check).frame(width: 12, height: 12)
                    Text(feedback).font(.manrope(12, .medium))
                }
                .foregroundStyle(Palette.accentText)
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
    /// from today even once older days scrolled into view. Flat
    /// quote-stream styling per the approved redesign: no bordered/filled
    /// card per day, just a day label and rows separated by padding alone
    /// — the accent bar marks the single newest entry across the whole
    /// list, not once per day.
    private var historyRows: some View {
        VStack(alignment: .leading, spacing: 0) {
            if app.entries.isEmpty {
                emptyState(
                    "No transcripts yet — click into any text field, hold \(app.hotkey.displayName), and speak.")
            } else if filteredEntries.isEmpty {
                emptyState("No transcripts match “\(searchText)”.")
            } else {
                LazyVStack(alignment: .leading, spacing: 22) {
                    ForEach(Array(groupedEntries.enumerated()), id: \.element.day) { _, group in
                        VStack(alignment: .leading, spacing: 2) {
                            daySectionLabel(group.day)
                            ForEach(group.entries, id: \.id) { entry in
                                historyRow(entry, isNewest: entry.id == newestEntryID)
                            }
                        }
                    }
                }
            }
        }
    }

    private func daySectionLabel(_ day: Date) -> some View {
        Text(dayLabel(day).uppercased())
            .font(.manrope(11, .medium))
            .kerning(0.7)
            .foregroundStyle(Palette.inkFaint)
            .padding(.bottom, 6)
    }

    private func emptyState(_ text: String) -> some View {
        Text(text)
            .font(.manrope(12.5))
            .italic()
            .foregroundStyle(Palette.inkFaint)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 28)
            .background(Palette.card, in: RoundedRectangle(cornerRadius: Radius.lg))
    }

    /// A 3pt leading bar replaces the old bordered/filled day-card as the
    /// row's own marker — lime (`accentText`) only on the single newest
    /// entry across the whole list (`isNewest`), a plain neutral bar on
    /// every other row. The time column echoes the same accent, mirroring
    /// it rather than leaving it as the one permanently-colored element on
    /// every row.
    private func historyRow(_ entry: HistoryEntry, isNewest: Bool) -> some View {
        let hovered = hoveredRow == entry.id
        return HStack(alignment: .center, spacing: 14) {
            Rectangle()
                .fill(isNewest ? Palette.accentText : Palette.border)
                .frame(width: 3)
                .frame(maxHeight: .infinity)
            HStack(alignment: .center, spacing: 16) {
                Text(entry.date, format: .dateTime.hour().minute())
                    .font(.manrope(13, .semibold))
                    .foregroundStyle(isNewest ? Palette.accentText : Palette.inkFaint)
                    // `font-variant-numeric: tabular-nums`. Verified Manrope
                    // ships Monospaced Numbers, so this stays in Manrope
                    // rather than falling back to a substitute face.
                    .monospacedDigit()
                    .frame(width: 44, alignment: .leading)
                Text(entry.text.replacingOccurrences(of: "\n", with: " "))
                    .font(.manrope(13.5))
                    .foregroundStyle(isNewest ? Palette.ink : Palette.inkSoft)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                // Actions stay laid out and only fade, so hovering a row
                // never reflows its text.
                HStack(spacing: 6) {
                    IconButton(icon: .copy, help: "Copy") {
                        let pb = NSPasteboard.general
                        pb.clearContents()
                        pb.setString(entry.text, forType: .string)
                    }
                    IconButton(icon: .edit, help: "Correct & learn") {
                        editText = entry.text
                        editingEntry = entry
                    }
                    IconButton(icon: .tpl, help: "Turn into a note") {
                        app.pendingTemplateText = entry.text
                        page = .templates
                    }
                    IconButton(icon: .trash, help: "Delete") {
                        app.deleteHistoryEntry(id: entry.id)
                    }
                }
                .opacity(hovered ? 1 : 0)
                .animation(.easeOut(duration: 0.1), value: hovered)
            }
        }
        .padding(.leading, 11)
        .padding(.trailing, 8)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: Radius.sm)
                .fill(hovered ? Palette.cardHover : Color.clear))
        // Without an explicit hit-testable shape, SwiftUI only counts
        // actually-drawn content (the text glyphs) as hoverable when the
        // background is .clear — the padding and inter-column gaps read as
        // "not part of the view" for hover purposes until the background
        // is already filled, so entering the row anywhere but directly on
        // the text failed to reveal the actions. This makes the whole
        // padded frame one hoverable region regardless of what's drawn.
        .contentShape(Rectangle())
        .onHover { inside in
            hoveredRow = inside ? entry.id : (hoveredRow == entry.id ? nil : hoveredRow)
        }
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
    /// `historyRow` uses to decide which one row (not one per day) gets
    /// the accent bar.
    private var newestEntryID: String? {
        groupedEntries.first?.entries.first?.id
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
