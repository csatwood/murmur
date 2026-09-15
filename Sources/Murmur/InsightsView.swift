import AppKit
import SwiftUI

// MARK: - Insights
//
// Redesigned per the "Main" canvas (Insights.dc.html): same `GlassPanelPage`
// shell as Home, warm ink/sunset palette instead of the shared dynamic
// `Palette`. The line-chart math (monotone interpolation, hover crosshair,
// end-label placement) is untouched — this is a View-layer rewrite only.
//
// The design replaced the old saturated bar chart with a line + soft area
// wash (the dataviz rule: "trend over time" is a line, not bars), a 2.5px
// stroke, recessive hairline gridlines, a direct end-label on the latest
// point, and a hover crosshair + tooltip (the last two aren't in the static
// mockup — added because a 7-point chart with no way to read exact values
// per day is a worse chart, not a more faithful one).

struct InsightsPage: View {
    @ObservedObject var app: AppDelegate
    @State private var hoverIndex: Int?
    @State private var chartMetric: ChartMetric = .words
    @State private var chartRange: ChartRange = .month
    @State private var tab: InsightsTab = .usage

    enum InsightsTab: CaseIterable {
        case usage, voice
        var label: String {
            switch self {
            case .usage: return "Your usage"
            case .voice: return "Your voice"
            }
        }
    }

    enum ChartMetric: CaseIterable {
        case words, wpm
        var label: String {
            switch self {
            case .words: return "Words"
            case .wpm: return "Pace (wpm)"
            }
        }
    }

    enum ChartRange: CaseIterable {
        case week, month, all
        var label: String {
            switch self {
            case .week: return "7D"
            case .month: return "30D"
            case .all: return "All"
            }
        }
    }

    var body: some View {
        GlassPanelPage {
            // A third card (Top apps) can now push the page taller than a
            // short window — this used to be a bare `VStack`, fine when the
            // chart card was the last thing on the page and just stretched
            // to fill whatever was left. `ThinScrollView` matches Home's own
            // choice for the same reason: content that can now exceed the
            // visible height needs to be reachable, not just clipped.
            ThinScrollView(bottomInset: 12) {
                VStack(alignment: .leading, spacing: 0) {
                    header

                    if app.entries.isEmpty {
                        // Replaces the whole strip + chart rather than
                        // showing four zeroes and a flat line at zero —
                        // `emptyState` matches Home's own (HomeView.swift's
                        // own function of the same name), the one other
                        // page with this problem.
                        emptyState.padding(.top, 24)
                    } else {
                        tabBar.padding(.top, 22)

                        switch tab {
                        case .usage: usageTab
                        case .voice: voiceTab
                        }
                    }
                }
            }
        }
    }

    /// Underlined text tabs, deliberately not another
    /// `WarmSegmentedPicker` pill — the chart card already has two of
    /// those for its own in-card options (metric, range); a third pill
    /// control at the page level would read as one more of the same thing
    /// rather than the page's own top-level navigation.
    private var tabBar: some View {
        HStack(spacing: 20) {
            ForEach(InsightsTab.allCases, id: \.self) { candidate in
                Button {
                    tab = candidate
                } label: {
                    Text(candidate.label)
                        .font(.manrope(13.5, .semibold))
                        .foregroundStyle(tab == candidate ? Palette.warmInk : Palette.warmInkFaint)
                        .padding(.bottom, 10)
                        .overlay(alignment: .bottom) {
                            Rectangle()
                                .fill(tab == candidate ? Palette.sunsetDeep : .clear)
                                .frame(height: 2)
                        }
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
        }
        .overlay(alignment: .bottom) {
            Rectangle().fill(Palette.warmDivider).frame(height: 1)
        }
    }

    private var usageTab: some View {
        VStack(alignment: .leading, spacing: 0) {
            // `.pcard flat stat-row`: a flat strip on the pane with
            // hairline dividers — no card fill, not three boxed cards.
            Card(flat: true) {
                HStack(alignment: .top, spacing: 0) {
                    statTile(.lines, "\(app.entries.count)", "dictations",
                             trend: dictationsTrend, isFirst: true)
                    statTile(.wave, compact(totalWords), "total words",
                             trend: wordsTrend, isFirst: false)
                    statTile(.calendar, avgWords, "avg words / dictation",
                             trend: nil, isFirst: false)
                    statTile(.clock, timeSavedLabel, "time saved this week",
                             trend: nil, isFirst: false)
                }
            }
            .padding(.top, 20)

            chartCard
                .padding(.top, 26)

            HStack(alignment: .top, spacing: 20) {
                fixesCard
                categoryCard
            }
            .padding(.top, 20)

            topAppsCard
                .padding(.top, 20)
        }
    }

    private var voiceTab: some View {
        VStack(alignment: .leading, spacing: 0) {
            personaCard
                .padding(.top, 20)
            factsCard
                .padding(.top, 16)
        }
    }

    private var emptyState: some View {
        Text("No dictations yet — once you've spoken a few things, your word-count "
             + "trend, speaking pace, and time saved will show up here.")
            .font(.manrope(12.5))
            .italic()
            .foregroundStyle(Palette.warmInkFaint)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 28)
            .background(Palette.warmRowBorder, in: RoundedRectangle(cornerRadius: Radius.lg))
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Insights")
                .font(.manrope(22, .medium))
                .tracking(-0.33)
                .foregroundStyle(Palette.warmInk)
            Text("How your dictation is trending.")
                .font(.manrope(12.5))
                .foregroundStyle(Palette.warmInkFaint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var chartCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 10) {
                Text(chartMetric == .words ? "Words dictated" : "Speaking pace")
                    .font(.manrope(13, .semibold))
                    .foregroundStyle(Palette.warmInk)
                Spacer(minLength: 12)
                WarmSegmentedPicker(options: ChartMetric.allCases, label: \.label, selection: $chartMetric)
                WarmSegmentedPicker(options: ChartRange.allCases, label: \.label, selection: $chartRange)
            }
            TrendChart(points: chartPoints, hoverIndex: $hoverIndex)
                .padding(.top, 20)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 22)
        // `maxHeight: .infinity` (stretch to fill the page) made sense
        // when this was the last, only element below the stat strip — now
        // that `topAppsCard` sits below it and the whole thing scrolls,
        // this needs its own natural height instead: inside a
        // `ScrollView`, an unbounded height proposal plus `maxHeight:
        // .infinity` is exactly the "expands to fill nothing in
        // particular" shape that produced HomeView's row-menu stretch bug.
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .onChange(of: chartMetric) { _, _ in hoverIndex = nil }
        .onChange(of: chartRange) { _, _ in hoverIndex = nil }
        // No drop shadow, by request (same call as Scratchpad's editor
        // card and Ask Murmur's composer) — it read as an odd smear along
        // the bottom edge sitting on the frosted glass panel.
        .background(Color.white, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var topAppsCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .lastTextBaseline) {
                Text("Top apps this week")
                    .font(.manrope(13, .semibold))
                    .foregroundStyle(Palette.warmInk)
                Spacer()
                Text("by words dictated")
                    .font(.manrope(11.5))
                    .foregroundStyle(Palette.warmInkFaint)
            }
            if topApps.isEmpty {
                // Every entry recorded before this shipped has no
                // `targetBundleID` at all (see `HistoryEntry`) — this
                // fills in as new dictations happen, not retroactively.
                Text("Not enough data yet — this fills in as you keep dictating.")
                    .font(.manrope(12.5))
                    .italic()
                    .foregroundStyle(Palette.warmInkFaint)
                    .padding(.top, 16)
            } else {
                VStack(spacing: 0) {
                    let maxWords = topApps.first?.words ?? 1
                    ForEach(Array(topApps.enumerated()), id: \.element.id) { index, usage in
                        AppUsageRow(usage: usage, maxWords: maxWords, isFirst: index == 0)
                    }
                }
                .padding(.top, 14)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 22)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    /// Counts read from `PipelineStatsStore` — see that type's own header
    /// for why these are plain before/after tallies taken at each pipeline
    /// stage's existing call site, not a change to what any of the three
    /// stages (Harper, the Dictionary, Snippets) actually do.
    private var fixesCard: some View {
        let stats = app.pipelineStats.totals(lastDays: 30)
        let total = stats.harperFixes + stats.dictionaryFixes + stats.snippetExpansions
        return VStack(alignment: .leading, spacing: 0) {
            Text("Fixes made by Murmur")
                .font(.manrope(13, .semibold))
                .foregroundStyle(Palette.warmInk)
            if total == 0 {
                Text("Nothing to show yet — this fills in as Harper, your Dictionary, "
                     + "and Snippets catch things in new dictations.")
                    .font(.manrope(12.5))
                    .italic()
                    .foregroundStyle(Palette.warmInkFaint)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 14)
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("\(total)")
                        .font(.manrope(27))
                        .tracking(-0.5)
                        .foregroundStyle(Palette.warmInk)
                    Text("this month")
                        .font(.manrope(11.5))
                        .foregroundStyle(Palette.warmInkFaint)
                }
                .padding(.top, 10)
                let maxFix = max(stats.harperFixes, stats.dictionaryFixes, stats.snippetExpansions, 1)
                VStack(spacing: 0) {
                    UsageBarRow(icon: .check, name: "Words corrected", detail: "Harper grammar",
                                value: stats.harperFixes, maxValue: maxFix,
                                figureText: "\(stats.harperFixes)", isFirst: true)
                    UsageBarRow(icon: .tpl, name: "Dictionary corrections", detail: nil,
                                value: stats.dictionaryFixes, maxValue: maxFix,
                                figureText: "\(stats.dictionaryFixes)", isFirst: false)
                    UsageBarRow(icon: .trans, name: "Snippets expanded", detail: nil,
                                value: stats.snippetExpansions, maxValue: maxFix,
                                figureText: "\(stats.snippetExpansions)", isFirst: false)
                }
                .padding(.top, 14)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 22)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    /// Not a literal copy of Wispr Flow's own category set — see
    /// `UsageCategory`'s own header for why this app leans toward
    /// Code editors/AI assistants over their Documents/Work-messages split.
    private var categoryCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .lastTextBaseline) {
                Text("Usage by category")
                    .font(.manrope(13, .semibold))
                    .foregroundStyle(Palette.warmInk)
                Spacer()
                Text("this week")
                    .font(.manrope(11.5))
                    .foregroundStyle(Palette.warmInkFaint)
            }
            if categoryUsage.isEmpty {
                Text("Not enough data yet — this fills in as you keep dictating.")
                    .font(.manrope(12.5))
                    .italic()
                    .foregroundStyle(Palette.warmInkFaint)
                    .padding(.top, 16)
            } else {
                let total = categoryUsage.reduce(0) { $0 + $1.words }
                let maxWords = categoryUsage.first?.words ?? 1
                VStack(spacing: 0) {
                    ForEach(Array(categoryUsage.enumerated()), id: \.element.category) { index, usage in
                        let percent = total > 0 ? Int((Double(usage.words) / Double(total) * 100).rounded()) : 0
                        UsageBarRow(icon: usage.category.icon, name: usage.category.rawValue, detail: nil,
                                    value: usage.words, maxValue: maxWords,
                                    figureText: "\(percent)%", isFirst: index == 0)
                    }
                }
                .padding(.top, 14)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 22)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    /// Reads `app.voiceProfile` — already generated and kept fresh by
    /// `AppDelegate.refreshVoiceProfileIfDue()` on every dictation, same
    /// data the dedicated Voice Profile page shows. This card doesn't
    /// generate anything itself, only displays it alongside the progress
    /// toward its next refresh.
    private var personaCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let profile = app.voiceProfile {
                let target = profile.wordCountAtGeneration + VoiceProfileStore.refreshThreshold
                let progress = target > profile.wordCountAtGeneration
                    ? Double(totalWords - profile.wordCountAtGeneration)
                        / Double(VoiceProfileStore.refreshThreshold)
                    : 1
                HStack {
                    Text("Voice profile")
                        .font(.manrope(10.5, .bold))
                        .kerning(0.6)
                        .foregroundStyle(Palette.warmInk)
                    Spacer()
                    Text("Next update in \(max(target - totalWords, 0)) words")
                        .font(.manrope(10.5))
                        .foregroundStyle(Palette.warmInk.opacity(0.6))
                }
                GeometryReader { geo in
                    RoundedRectangle(cornerRadius: 2).fill(.white.opacity(0.35))
                        .overlay(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 2).fill(Palette.warmInk)
                                .frame(width: geo.size.width * CGFloat(min(max(progress, 0), 1)))
                        }
                }
                .frame(height: 4)
                .padding(.top, 8)

                Text(profile.title)
                    .font(.manrope(24, .semibold))
                    .tracking(-0.3)
                    .foregroundStyle(Palette.warmInk)
                    .padding(.top, 16)
                if !profile.summary.isEmpty {
                    Text(profile.summary)
                        .font(.manrope(13))
                        .foregroundStyle(Palette.warmInk.opacity(0.75))
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: 480, alignment: .leading)
                        .padding(.top, 8)
                }
                if let traits = profile.traits, !traits.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(traits, id: \.self) { trait in
                            Text(trait)
                                .font(.manrope(11, .medium))
                                .foregroundStyle(Palette.warmInk)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(Color.white, in: Capsule())
                        }
                    }
                    .padding(.top, 12)
                }
            } else {
                Text("Voice profile")
                    .font(.manrope(10.5, .bold))
                    .kerning(0.6)
                    .foregroundStyle(Palette.warmInk)
                Text("Keep dictating — Murmur builds this from your own transcripts "
                     + "once you've dictated at least \(VoiceProfileStore.minimumWords) words.")
                    .font(.manrope(13))
                    .foregroundStyle(Palette.warmInk.opacity(0.75))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 10)
            }
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 24)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        // Same treatment as Home's own hero (`captureZone`): the bold
        // sunset-to-light gradient, not a flat pale fill, plus its
        // shadow — this is Insights' one deliberately elevated "hero"
        // card, not another flat content card like `chartCard`/
        // `fixesCard` next to it (those stay shadowless by the page's
        // usual rule; a hero reads as a hero partly because it doesn't).
        // Flat, not the gradient — just `sunset`, its own darker stop, as
        // a solid fill (same call as Scratchpad's and Notetaker's heroes).
        .background(Palette.sunset, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .shadow(color: .black.opacity(0.04), radius: 1, y: 1)
        .shadow(color: .black.opacity(0.06), radius: 16, y: 16)
    }

    /// Catchphrase, most-used and most-corrected words, and peak time &
    /// place — real, computed facts, deliberately not padded out to four
    /// separate cards the way `personaCard` alone would leave this tab
    /// looking thin next to `usageTab`.
    private var factsCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            factRow("Catchphrase", quote: catchphrase, isFirst: true)
            factRow("Most used word", quote: mostUsedWord, isFirst: false)
            factRow("Most corrected word", quote: mostCorrectedWord, isFirst: false)
            factRow("Peak time & place", quote: nil, detail: peakTimeDescription, isFirst: false)
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func factRow(_ label: String, quote: String?, detail: String? = nil, isFirst: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            Text(label.uppercased())
                .font(.manrope(11, .semibold))
                .kerning(0.4)
                .foregroundStyle(Palette.warmInkFaint)
                .frame(width: 160, alignment: .leading)
            if let quote {
                Text("“\(quote)”")
                    .font(.manrope(13.5, .semibold))
                    .foregroundStyle(Palette.warmInk)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .multilineTextAlignment(.trailing)
            } else {
                Text(detail ?? "Not enough data yet")
                    .font(.manrope(13))
                    .foregroundStyle(Palette.warmInk)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .multilineTextAlignment(.trailing)
            }
        }
        .padding(.vertical, 15)
        .overlay(alignment: .top) {
            if !isFirst { Rectangle().fill(Palette.warmRowBorder).frame(height: 1) }
        }
    }

    private func statTile(
        _ icon: MurmurIcon, _ value: String, _ label: String,
        trend: String?, isFirst: Bool
    ) -> some View {
        // The divider is an *overlay*, not a layout sibling. A bare
        // `Rectangle` with only a width set expands to whatever height is
        // offered, so as a sibling it competed with the chart for free
        // vertical space and stretched this whole strip. As an overlay it
        // paints inside the tile's content-derived height and can never
        // influence layout.
        VStack(alignment: .leading, spacing: 0) {
            Text(value)
                .font(.manrope(27))
                .tracking(-0.54)
                .foregroundStyle(Palette.warmInk)
            HStack(spacing: 5) {
                MurmurIconView(icon: icon)
                    .frame(width: 12, height: 12)
                    .foregroundStyle(Palette.warmInkFaint)
                Text(label)
                    .font(.manrope(11.5))
                    .foregroundStyle(Palette.warmInkFaint)
            }
            .padding(.top, 4)
            if let trend {
                HStack(spacing: 4) {
                    MurmurIconView(icon: .arrowRight)
                        .frame(width: 10, height: 10)
                        .rotationEffect(.degrees(-45))
                    Text(trend).font(.manrope(12, .semibold))
                }
                .foregroundStyle(Palette.sunsetDeep)
                .padding(.top, 6)
            }
        }
        .padding(.trailing, 20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, isFirst ? 0 : 20)
        .overlay(alignment: .leading) {
            // Sits exactly on the tile boundary (outside this tile's own
            // 20pt leading inset), the same seam `.stat-row > div` draws it
            // on in the design.
            if !isFirst {
                Rectangle().fill(Palette.warmDivider).frame(width: 1)
                    .padding(.leading, -20)
            }
        }
    }

    // MARK: Derived data

    private var totalWords: Int {
        app.entries.reduce(0) { $0 + $1.wordCount }
    }

    private var avgWords: String {
        app.entries.isEmpty ? "—" : "\(totalWords / app.entries.count)"
    }

    private func compact(_ number: Int) -> String {
        number >= 1000 ? String(format: "%.1fK", Double(number) / 1000) : "\(number)"
    }

    /// Days the chart spans for the current `chartRange` — a fixed 7 or 30,
    /// or every day since the oldest entry for "All". Kept unbounded on
    /// purpose rather than capped at some arbitrary window: a new user's
    /// "All" is naturally short, and a long-time user's really is long —
    /// `TrendChart` already thins its x-axis labels as point count grows,
    /// so the line just gets denser rather than unreadable.
    private var chartDayCount: Int {
        switch chartRange {
        case .week: return 7
        case .month: return 30
        case .all:
            guard let earliest = app.entries.map(\.date).min() else { return 7 }
            let calendar = Calendar.current
            let days = calendar.dateComponents(
                [.day], from: calendar.startOfDay(for: earliest), to: calendar.startOfDay(for: Date())
            ).day ?? 0
            return max(days + 1, 7)
        }
    }

    /// Words and speaking pace for one calendar day — the two `chartPoints`
    /// picks between, and `timeSavedLabel`'s own per-day building block.
    private func dayStats(_ day: Date) -> (words: Int, wpm: Int) {
        let calendar = Calendar.current
        let entries = app.entries.filter { calendar.isDate($0.date, inSameDayAs: day) }
        let words = entries.reduce(0) { $0 + $1.wordCount }
        let seconds = entries.reduce(0.0) { $0 + ($1.duration ?? 0) }
        let wpm = seconds > 0 ? Int(Double(words) / (seconds / 60)) : 0
        return (words, wpm)
    }

    private var chartPoints: [(label: String, value: Int)] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        return (0..<chartDayCount).reversed().map { offset in
            let day = calendar.date(byAdding: .day, value: -offset, to: today)!
            let stats = dayStats(day)
            let value = chartMetric == .words ? stats.words : stats.wpm
            return (day.formatted(.dateTime.day().month(.abbreviated)), value)
        }
    }

    /// A commonly-cited average typing speed, so the gap between it and
    /// this week's own measured dictation pace reads as time actually
    /// saved — not just another word count restated as minutes.
    private static let assumedTypingWPM: Double = 40

    /// This calendar week's entries — the shared basis for `timeSavedLabel`
    /// and `topApps`, which both need "this week," not whatever `chartRange`
    /// currently has the chart itself showing.
    private var weekEntries: [HistoryEntry] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        return (0..<7).flatMap { offset -> [HistoryEntry] in
            let day = calendar.date(byAdding: .day, value: -offset, to: today)!
            return app.entries.filter { calendar.isDate($0.date, inSameDayAs: day) }
        }
    }

    /// Same window as `weekEntries`, over Notetaker's own notes — used
    /// alongside it in `topApps`/`categoryUsage` so a meeting's words count
    /// toward the same app/category totals a dictation's do, instead of
    /// meetings being invisible to both cards.
    private var weekMeetings: [MeetingNote] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        return (0..<7).flatMap { offset -> [MeetingNote] in
            let day = calendar.date(byAdding: .day, value: -offset, to: today)!
            return app.notetaker.notes.filter { calendar.isDate($0.date, inSameDayAs: day) }
        }
    }

    private var timeSavedLabel: String {
        let words = weekEntries.reduce(0) { $0 + $1.wordCount }
        guard words > 0 else { return "—" }
        let dictationMinutes = weekEntries.reduce(0.0) { $0 + ($1.duration ?? 0) } / 60
        let typingMinutes = Double(words) / Self.assumedTypingWPM
        let savedMinutes = max(0, typingMinutes - dictationMinutes)
        guard savedMinutes >= 1 else { return "< 1 min" }
        return savedMinutes >= 60
            ? String(format: "%.1f hrs", savedMinutes / 60)
            : "\(Int(savedMinutes.rounded())) min"
    }

    /// One row of `topAppsCard` — the app's real name and icon, resolved
    /// from the bundle ID recorded at dictation time (`AppDelegate`'s own
    /// `recordingTargetBundleID`, threaded through `HistoryEntry` since
    /// this card needed it and nothing was persisting it before).
    struct AppUsage: Identifiable {
        let bundleID: String
        let name: String
        let icon: NSImage?
        let words: Int
        var id: String { bundleID }
    }

    /// Resolves via the *installed* app, not the running-apps list
    /// `AppProfilesView`'s own picker uses — a dictation's target app may
    /// well have quit by the time this page is looked at.
    private func resolveApp(bundleID: String) -> (name: String, icon: NSImage?) {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            return (bundleID, nil)
        }
        let name = FileManager.default.displayName(atPath: url.path)
        return (name, NSWorkspace.shared.icon(forFile: url.path))
    }

    private var topApps: [AppUsage] {
        var wordsByBundleID: [String: Int] = [:]
        for entry in weekEntries {
            guard let bundleID = entry.targetBundleID else { continue }
            wordsByBundleID[bundleID, default: 0] += entry.wordCount
        }
        for note in weekMeetings {
            guard let bundleID = note.appBundleID else { continue }
            wordsByBundleID[bundleID, default: 0] += note.wordCount
        }
        return wordsByBundleID
            .sorted { $0.value > $1.value }
            .prefix(5)
            .map { bundleID, words in
                let resolved = resolveApp(bundleID: bundleID)
                return AppUsage(bundleID: bundleID, name: resolved.name, icon: resolved.icon, words: words)
            }
    }

    /// This week's words grouped by `UsageCategory`, sorted highest first.
    /// Entries with no recorded `targetBundleID` are skipped rather than
    /// folded into `.other` — "we don't know what app this was" and "we
    /// know the app but not its category" are different things, and only
    /// the second one is what `.other` is meant to mean.
    private var categoryUsage: [(category: UsageCategory, words: Int)] {
        var totals: [UsageCategory: Int] = [:]
        for entry in weekEntries {
            guard let bundleID = entry.targetBundleID else { continue }
            totals[AppCategoryClassifier.category(forBundleID: bundleID), default: 0] += entry.wordCount
        }
        for note in weekMeetings {
            guard let bundleID = note.appBundleID else { continue }
            totals[AppCategoryClassifier.category(forBundleID: bundleID), default: 0] += note.wordCount
        }
        return totals.sorted { $0.value > $1.value }.map { ($0.key, $0.value) }
    }

    // MARK: Your voice

    private static let wordCatalogStopWords: Set<String> = [
        "the", "a", "an", "and", "or", "but", "in", "on", "at", "to", "for",
        "of", "is", "are", "was", "were", "what", "when", "where", "who",
        "did", "do", "does", "i", "my", "me", "this", "that", "with",
        "about", "have", "has", "had", "you", "your", "it", "be", "been",
        "so", "just", "can", "will", "would", "there", "here", "we", "us",
    ]

    private func words(in text: String) -> [String] {
        text.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
    }

    /// The single word (stopwords aside) said most often across all of
    /// History — a plain frequency count, no AI involved.
    private var mostUsedWord: String? {
        var counts: [String: Int] = [:]
        for entry in app.entries {
            for word in words(in: entry.text) where word.count > 2 && !Self.wordCatalogStopWords.contains(word) {
                counts[word, default: 0] += 1
            }
        }
        return counts.max(by: { $0.value < $1.value })?.key
    }

    /// The recurring 3-word phrase said most often — a sliding trigram
    /// count over every entry, skipping any window that's entirely
    /// stopwords (otherwise "in the" + one more common word wins every
    /// time, which says nothing about how this person actually talks).
    private var catchphrase: String? {
        var counts: [String: Int] = [:]
        for entry in app.entries {
            let tokens = words(in: entry.text)
            guard tokens.count >= 3 else { continue }
            for i in 0...(tokens.count - 3) {
                let gram = Array(tokens[i..<(i + 3)])
                guard gram.contains(where: { !Self.wordCatalogStopWords.contains($0) }) else { continue }
                counts[gram.joined(separator: " "), default: 0] += 1
            }
        }
        return counts.filter { $0.value > 1 }.max(by: { $0.value < $1.value })?.key
    }

    /// The correction Murmur's Dictionary has been taught most often —
    /// `LearnedCorrection.timesSeen` already counts exactly this, so this
    /// reads that store directly rather than re-deriving anything.
    private var mostCorrectedWord: String? {
        LearnedStore.load().corrections.max(by: { $0.timesSeen < $1.timesSeen })?.intended
    }

    /// The (weekday, hour) bucket with the most dictations, and whichever
    /// app was most common within that bucket — a plain mode over History,
    /// not an AI-written summary, so this stays accurate even for a small
    /// sample instead of reading like an invented anecdote.
    private var peakTimeDescription: String? {
        guard !app.entries.isEmpty else { return nil }
        let calendar = Calendar.current
        var buckets: [DateComponents: [HistoryEntry]] = [:]
        for entry in app.entries {
            let comps = calendar.dateComponents([.weekday, .hour], from: entry.date)
            buckets[comps, default: []].append(entry)
        }
        guard let (comps, bucketEntries) = buckets.max(by: { $0.value.count < $1.value.count }),
              let weekday = comps.weekday, let hour = comps.hour
        else { return nil }

        let weekdayName = calendar.weekdaySymbols[weekday - 1]
        let hour12 = hour % 12 == 0 ? 12 : hour % 12
        let period = hour < 12 ? "am" : "pm"
        var line = "\(weekdayName)s around \(hour12)\(period)"

        let appCounts = Dictionary(grouping: bucketEntries.compactMap(\.targetBundleID)) { $0 }
            .mapValues(\.count)
        if let topBundleID = appCounts.max(by: { $0.value < $1.value })?.key {
            line += ", usually in \(resolveApp(bundleID: topBundleID).name)"
        }
        return line
    }

    /// Compares the last 7 days against the 7 before them.
    private func weekOverWeek(_ metric: (Range<Int>) -> Int) -> String? {
        let this = metric(0..<7)
        let prior = metric(7..<14)
        guard prior > 0, this != prior else { return nil }
        let change = Double(this - prior) / Double(prior) * 100
        guard change > 0 else { return nil }
        return "\(Int(change))% vs last week"
    }

    private var wordsTrend: String? {
        weekOverWeek { range in
            let calendar = Calendar.current
            let today = calendar.startOfDay(for: Date())
            return range.reduce(0) { sum, offset in
                let day = calendar.date(byAdding: .day, value: -offset, to: today)!
                return sum + app.entries
                    .filter { calendar.isDate($0.date, inSameDayAs: day) }
                    .reduce(0) { $0 + $1.wordCount }
            }
        }
    }

    private var dictationsTrend: String? {
        weekOverWeek { range in
            let calendar = Calendar.current
            let today = calendar.startOfDay(for: Date())
            return range.reduce(0) { sum, offset in
                let day = calendar.date(byAdding: .day, value: -offset, to: today)!
                return sum + app.entries.filter { calendar.isDate($0.date, inSameDayAs: day) }.count
            }
        }
    }
}

/// One row of `topAppsCard`: real icon (a plain rounded square placeholder
/// when the app can't be resolved, e.g. long since uninstalled — never a
/// fabricated one), name, a proportional bar, and the word count.
/// One row of `fixesCard`/`categoryCard`: a `MurmurIcon` (not a resolved
/// app icon — `AppUsageRow` below is for that), name (with an optional
/// faint detail line under it), a proportional bar, and a trailing figure.
/// Shared rather than two near-duplicates since both cards are otherwise
/// the same shape.
private struct UsageBarRow: View {
    let icon: MurmurIcon
    let name: String
    let detail: String?
    let value: Int
    let maxValue: Int
    let figureText: String
    let isFirst: Bool

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 7).fill(Palette.warmRowBorder)
                MurmurIconView(icon: icon)
                    .frame(width: 13, height: 13)
                    .foregroundStyle(Palette.sunsetDeep)
            }
            .frame(width: 26, height: 26)

            VStack(alignment: .leading, spacing: 1) {
                Text(name)
                    .font(.manrope(12.5, .semibold))
                    .foregroundStyle(Palette.warmInk)
                    .lineLimit(1)
                if let detail {
                    Text(detail)
                        .font(.manrope(10.5))
                        .foregroundStyle(Palette.warmInkFainter)
                }
            }
            .frame(width: 128, alignment: .leading)

            GeometryReader { geo in
                RoundedRectangle(cornerRadius: 3)
                    .fill(Palette.warmRowBorder)
                    .overlay(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Palette.sunset)
                            .frame(width: geo.size.width * CGFloat(value) / CGFloat(max(maxValue, 1)))
                    }
            }
            .frame(height: 6)

            Text(figureText)
                .font(.manrope(11.5))
                .monospacedDigit()
                .foregroundStyle(Palette.warmInkSoft)
                .frame(width: 64, alignment: .trailing)
        }
        .padding(.vertical, 8)
        .overlay(alignment: .top) {
            if !isFirst { Rectangle().fill(Palette.warmRowBorder).frame(height: 1) }
        }
    }
}

private struct AppUsageRow: View {
    let usage: InsightsPage.AppUsage
    let maxWords: Int
    let isFirst: Bool

    var body: some View {
        HStack(spacing: 12) {
            Group {
                if let icon = usage.icon {
                    Image(nsImage: icon).resizable()
                } else {
                    RoundedRectangle(cornerRadius: 6).fill(Palette.warmRowBorder)
                }
            }
            .frame(width: 26, height: 26)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

            Text(usage.name)
                .font(.manrope(12.5, .semibold))
                .foregroundStyle(Palette.warmInk)
                .lineLimit(1)
                .frame(width: 120, alignment: .leading)

            GeometryReader { geo in
                RoundedRectangle(cornerRadius: 3)
                    .fill(Palette.warmRowBorder)
                    .overlay(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Palette.sunset)
                            .frame(width: geo.size.width * CGFloat(usage.words) / CGFloat(max(maxWords, 1)))
                    }
            }
            .frame(height: 6)

            Text("\(usage.words)")
                .font(.manrope(11.5))
                .monospacedDigit()
                .foregroundStyle(Palette.warmInkSoft)
                .frame(width: 56, alignment: .trailing)
        }
        .padding(.vertical, 8)
        .overlay(alignment: .top) {
            if !isFirst {
                Rectangle().fill(Palette.warmRowBorder).frame(height: 1)
            }
        }
    }
}

/// A borderless pill-in-pill segmented control — the same recipe as
/// StyleView's own tone switcher (`Palette.sunset`-filled capsule, no
/// dividers between segments), generalized to any `Hashable` option since
/// this page needs two of these (metric, range) rather than one fixed
/// enum. The shared `SegmentedPicker` (DesignSystem.swift) exists too, but
/// draws with the dynamic light/dark `Palette` — StyleView already skips
/// it for the same reason this does: it reads as a mismatched, cooler
/// neutral against this page's warm/light-only palette.
private struct WarmSegmentedPicker<T: Hashable>: View {
    let options: [T]
    let label: (T) -> String
    @Binding var selection: T

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.self) { option in
                Button {
                    selection = option
                } label: {
                    Text(label(option))
                        .font(.manrope(11.5, option == selection ? .semibold : .regular))
                        .foregroundStyle(option == selection ? .white : Palette.warmInkSoft)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 5)
                        .background {
                            if option == selection {
                                Capsule().fill(Palette.sunset)
                            }
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(Color.white, in: Capsule())
        .overlay(Capsule().stroke(Palette.warmRowBorder, lineWidth: 1))
        .fixedSize()
    }
}

// MARK: - Trend chart

/// Reports the hover tooltip's own rendered size back up so its position
/// can be derived from its *actual* height instead of a guessed constant.
private struct TooltipSizeKey: PreferenceKey {
    static var defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        value = nextValue()
    }
}

struct TrendChart: View {
    let points: [(label: String, value: Int)]
    @Binding var hoverIndex: Int?

    /// The hover tooltip's own measured size (see `SizeKey` below) — its
    /// position is derived from this rather than a guessed fixed offset,
    /// so the gap above the curve is exact regardless of font metrics.
    @State private var tooltipSize: CGSize = .zero

    /// Fixed clearance between the tooltip's bottom edge and the point it
    /// describes. Previously the tooltip was centered a flat 34pt above
    /// the point with no regard for its own height, which happened to
    /// leave a reasonable gap only by coincidence for a short tooltip —
    /// against Manrope's actual line height here, the box's bottom edge
    /// landed right on the curve instead, worst right at a peak (the one
    /// case that most needs clearance). Positioning off the tooltip's own
    /// measured height fixes this everywhere, not just at the extremes.
    private static let tooltipGap: CGFloat = 10

    /// The plot and the y-axis labels must be laid out at exactly the same
    /// height or the ticks stop lining up with their gridlines. A seven-
    /// point weekly trend doesn't get more readable past roughly this
    /// height — it just leaves the line stranded in empty space — so the
    /// chart is deliberately sized, not stretched to fill the window.
    private let plotHeight: CGFloat = 240

    /// Every Nth x-axis label is shown once a range has more days than fit
    /// legibly — a week's worth never thins, a month shows roughly one
    /// label per five days, and a year+ "All" thins further still, rather
    /// than cramming 30+ overlapping date strings under the plot.
    private var labelStep: Int {
        switch points.count {
        case ...7: return 1
        case ...31: return 5
        default: return max(points.count / 8, 10)
        }
    }

    private var maxValue: Int {
        max(points.map(\.value).max() ?? 0, 1)
    }

    /// Rounds the axis top up to a clean tick so gridlines read as round
    /// numbers rather than arbitrary maxima.
    private var axisTop: Int {
        let raw = Double(maxValue) * 1.15
        let magnitude = pow(10, floor(log10(max(raw, 1))))
        return max(Int(ceil(raw / magnitude) * magnitude), 1)
    }

    private var ticks: [Int] {
        (0...3).map { axisTop * $0 / 3 }
    }

    /// The y a given tick sits at. Used by both the gridlines and the axis
    /// labels so the two can't drift apart.
    private func gridY(for tick: Int, in height: CGFloat) -> CGFloat {
        height - (CGFloat(tick) / CGFloat(axisTop)) * height
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            // Y axis. Each label is positioned on its gridline's exact y,
            // not spread evenly down the column: four labels in four equal
            // slices only ever agrees with four gridlines at thirds for the
            // topmost one, which left "0" floating far below the baseline.
            ZStack(alignment: .topTrailing) {
                Color.clear
                ForEach(ticks, id: \.self) { tick in
                    Text("\(tick)")
                        .font(.manrope(10))
                        .foregroundStyle(Palette.warmInkFainter)
                        .alignmentGuide(.top) { d in d.height / 2 }
                        .offset(y: gridY(for: tick, in: plotHeight))
                }
            }
            .frame(width: 34, height: plotHeight, alignment: .topTrailing)

            VStack(spacing: 6) {
                GeometryReader { geo in
                    let w = geo.size.width
                    let h = geo.size.height
                    let coords = coordinates(in: CGSize(width: w, height: h))

                    ZStack(alignment: .topLeading) {
                        // Recessive gridlines
                        ForEach(ticks, id: \.self) { tick in
                            let y = gridY(for: tick, in: h)
                            Path { p in
                                p.move(to: CGPoint(x: 0, y: y))
                                p.addLine(to: CGPoint(x: w, y: y))
                            }
                            .stroke(Palette.warmRowBorder, lineWidth: 1)
                        }

                        // Area wash — ~10% opacity, never a saturated block
                        smoothPath(coords, closedTo: h)
                            .fill(Palette.sunset.opacity(0.1))

                        // 2.5px line
                        smoothPath(coords, closedTo: nil)
                            .stroke(Palette.sunset,
                                    style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))

                        // Crosshair + hovered point
                        if let i = hoverIndex, coords.indices.contains(i) {
                            Path { p in
                                p.move(to: CGPoint(x: coords[i].x, y: 0))
                                p.addLine(to: CGPoint(x: coords[i].x, y: h))
                            }
                            .stroke(Palette.warmDivider, lineWidth: 1)
                            Circle()
                                .fill(Palette.sunset)
                                .frame(width: 8, height: 8)
                                .position(coords[i])
                        }

                        // Direct end-label on the most recent point
                        if let last = coords.last, let value = points.last?.value {
                            Circle()
                                .fill(Palette.sunset)
                                .frame(width: 8, height: 8)
                                .overlay(Circle().stroke(.white, lineWidth: 2))
                                .position(last)
                            // `.line-chart-end-label`:
                            // `transform: translate(-50%, calc(-100% - 8px))`
                            // — centered on the dot, lifted clear above it.
                            //
                            // Clamping this horizontally (an earlier fix)
                            // was the actual bug: shifting the label left,
                            // toward the plot's interior, moves it onto a
                            // stretch of curve that's still descending —
                            // i.e. *higher* than the dot — so the line
                            // ended up passing through the label instead of
                            // under it. The design never clamps: the card
                            // carries its own ~20pt padding around the
                            // plot, the chart card doesn't clip its
                            // content, so a few points of horizontal
                            // overflow from a right-edge label lands
                            // harmlessly in that padding instead of
                            // overlapping the curve.
                            Text("\(value)")
                                .font(.manrope(12, .semibold))
                                .monospacedDigit()
                                .foregroundStyle(Palette.sunset)
                                .fixedSize()
                                .position(x: last.x, y: max(last.y - 17, 9))
                        }

                        // Hover tooltip
                        if let i = hoverIndex, coords.indices.contains(i) {
                            VStack(alignment: .leading, spacing: 1) {
                                Text("\(points[i].value)")
                                    .font(.manrope(12, .semibold))
                                    .foregroundStyle(Palette.warmInk)
                                Text(points[i].label)
                                    .font(.manrope(10))
                                    .foregroundStyle(Palette.warmInkSoft)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(Color.white, in: RoundedRectangle(cornerRadius: 8))
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Palette.warmDivider, lineWidth: 1))
                            .background(
                                GeometryReader { tooltipGeo in
                                    Color.clear
                                        .preference(key: TooltipSizeKey.self, value: tooltipGeo.size)
                                })
                            // Bottom edge sits `tooltipGap` above the point,
                            // full stop — never clamped back down toward it
                            // (the previous bug: flooring this pulled the
                            // tooltip down toward a high peak once the old
                            // fixed offset went negative, landing it right
                            // on the curve instead of above it, worst
                            // exactly where clearance mattered most) and
                            // never guessed from font metrics (the other
                            // bug: a flat 34pt offset assumed a tooltip
                            // height that didn't match Manrope's real line
                            // height, so even the "un-clamped" version still
                            // touched the curve at every point, not just
                            // peaks). Floating above the plot's own top
                            // edge is fine — the chart card's padding
                            // absorbs it, same as the end-label's horizontal
                            // overflow above.
                            .position(x: min(max(coords[i].x, 40), w - 40),
                                      y: coords[i].y - Self.tooltipGap - tooltipSize.height / 2)
                            .onPreferenceChange(TooltipSizeKey.self) { tooltipSize = $0 }
                        }
                    }
                    .contentShape(Rectangle())
                    .onContinuousHover { phase in
                        switch phase {
                        case .active(let location):
                            let step = w / CGFloat(max(points.count - 1, 1))
                            hoverIndex = min(max(Int((location.x / step).rounded()), 0), points.count - 1)
                        case .ended:
                            hoverIndex = nil
                        }
                    }
                }
                .frame(height: plotHeight)

                // X axis — `justify-content: space-between`, matching how
                // the points themselves run edge to edge. Centering each
                // label in an equal-width column instead (as this did)
                // offsets every label from the dot it belongs to, worst at
                // the two ends. The last day (today) is always bold/dark,
                // matching the mockup's own static emphasis — every other
                // day is faint unless actively hovered.
                //
                // Every point still gets a slot (and the same `Spacer`
                // between slots) regardless of `labelStep` — only the text
                // itself is skipped for thinned-out points, so the labels
                // that do show stay aligned under their own dot rather
                // than redistributing across the freed-up space.
                HStack(spacing: 4) {
                    ForEach(Array(points.enumerated()), id: \.offset) { index, point in
                        let isLast = index == points.count - 1
                        let isHighlighted = isLast || index == hoverIndex
                        let shown = isLast || index % labelStep == 0
                        Text(shown ? point.label : "")
                            .font(.manrope(10.5, isLast ? .semibold : .regular))
                            .foregroundStyle(isHighlighted ? Palette.warmInk : Palette.warmInkFainter)
                            .fixedSize()
                        if index != points.count - 1 { Spacer(minLength: 0) }
                    }
                }
                .padding(.top, 8)
            }
        }
    }

    private func coordinates(in size: CGSize) -> [CGPoint] {
        let n = max(points.count - 1, 1)
        return points.enumerated().map { index, point in
            CGPoint(
                x: size.width * CGFloat(index) / CGFloat(n),
                y: size.height - (CGFloat(point.value) / CGFloat(axisTop)) * size.height)
        }
    }

    /// Monotone cubic (Fritsch–Carlson) Hermite interpolation.
    ///
    /// The mockup smooths with plain Catmull-Rom, which is fine for its
    /// hand-picked sample data but **overshoots** on real data: a flat run
    /// of zero-word days followed by a spike makes the curve swing below
    /// the baseline, drawing days with negative words. Word counts can't
    /// be negative, so the chart must not be able to draw one.
    ///
    /// This variant limits each tangent to the slope of its neighbouring
    /// segments, so the curve is guaranteed to stay within the range of
    /// the two points it connects — it can never dip under a zero day.
    private func smoothPath(_ pts: [CGPoint], closedTo bottom: CGFloat?) -> Path {
        var path = Path()
        guard let first = pts.first else { return path }
        path.move(to: first)
        guard pts.count > 1 else { return path }

        let n = pts.count
        // Secant slope of each segment.
        var slopes = [CGFloat](repeating: 0, count: n - 1)
        for i in 0..<(n - 1) {
            let dx = pts[i + 1].x - pts[i].x
            slopes[i] = dx == 0 ? 0 : (pts[i + 1].y - pts[i].y) / dx
        }
        // Tangents: average of adjacent secants, endpoints one-sided.
        var tangents = [CGFloat](repeating: 0, count: n)
        tangents[0] = slopes[0]
        tangents[n - 1] = slopes[n - 2]
        for i in 1..<(n - 1) {
            tangents[i] = slopes[i - 1] * slopes[i] <= 0
                ? 0                                     // local extremum: flatten
                : (slopes[i - 1] + slopes[i]) / 2
        }
        // Fritsch–Carlson limiter — the step that actually prevents overshoot.
        for i in 0..<(n - 1) {
            if slopes[i] == 0 {
                tangents[i] = 0
                tangents[i + 1] = 0
                continue
            }
            let alpha = tangents[i] / slopes[i]
            let beta = tangents[i + 1] / slopes[i]
            let magnitude = alpha * alpha + beta * beta
            if magnitude > 9 {
                let tau = 3 / magnitude.squareRoot()
                tangents[i] = tau * alpha * slopes[i]
                tangents[i + 1] = tau * beta * slopes[i]
            }
        }
        for i in 0..<(n - 1) {
            let p1 = pts[i]
            let p2 = pts[i + 1]
            let dx = (p2.x - p1.x) / 3
            let c1 = CGPoint(x: p1.x + dx, y: p1.y + tangents[i] * dx)
            let c2 = CGPoint(x: p2.x - dx, y: p2.y - tangents[i + 1] * dx)
            path.addCurve(to: p2, control1: c1, control2: c2)
        }
        if let bottom, let last = pts.last {
            path.addLine(to: CGPoint(x: last.x, y: bottom))
            path.addLine(to: CGPoint(x: first.x, y: bottom))
            path.closeSubpath()
        }
        return path
    }
}
