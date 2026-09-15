import AppKit
import SwiftUI

// MARK: - Ask Murmur
//
// Redesigned per the "Main" canvas (Ask.dc.html): same `GlassPanelPage`
// shell as Home/Insights/Scratchpad, warm palette instead of the shared
// dynamic `Palette`. Structurally unchanged from the previous pass — a
// real chat layout where the conversation scrolls and the composer stays
// pinned to the bottom.
//
// The thread itself (`app.askTurns`) lives on `AppDelegate`, not here —
// see that property's own comment for why: this `View` struct is
// recreated every time the rail navigates to this page, so anything kept
// as plain `@State` reset to empty on every visit.

struct AskPage: View {
    @ObservedObject var app: AppDelegate
    @State private var question = ""

    struct ChatTurn: Identifiable {
        let id = UUID()
        let question: String
        var answer: String?
        /// The notes the answer above was actually generated from, shown
        /// via `SourcesDisclosure` — empty while `answer` is still nil.
        var sources: [AskMurmur.AskSource] = []
    }

    private let suggestions = [
        "What did I dictate today?",
        "Summarize this week",
        "What tasks or action items did I mention?",
    ]

    var body: some View {
        GlassPanelPage {
            VStack(spacing: 0) {
                ScrollViewReader { proxy in
                    ThinScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            header

                            if let note = app.rewriteEngine.availabilityNote {
                                PageTip(text: note)
                                    .padding(.bottom, 16)
                            }

                            if app.askTurns.isEmpty {
                                if app.entries.isEmpty {
                                    noHistoryNotice
                                } else {
                                    VStack(alignment: .leading, spacing: 8) {
                                        Text("Try asking")
                                            .font(.manrope(12, .semibold))
                                            .foregroundStyle(Palette.warmInkSoft)
                                            .padding(.bottom, 2)
                                        ForEach(suggestions, id: \.self) { suggestion in
                                            SuggestionChip(text: suggestion) {
                                                question = suggestion
                                                ask()
                                            }
                                        }
                                    }
                                }
                            }

                            ForEach(app.askTurns) { turn in
                                TurnView(turn: turn, canRegenerate: !app.askThinking) {
                                    regenerate(turn)
                                }
                                .padding(.bottom, 22)
                                .id(turn.id)
                            }
                            Color.clear.frame(height: 1).id("bottom")
                        }
                    }
                    .onChange(of: app.askTurns.count) { _, _ in
                        withAnimation(.murmurEase()) { proxy.scrollTo("bottom", anchor: .bottom) }
                    }
                }

                composer
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Ask Murmur")
                .font(.manrope(22, .medium))
                .tracking(-0.33)
                .foregroundStyle(Palette.warmInk)
            Text("Chat over your entire dictation history — on-device, nothing sent anywhere.")
                .font(.manrope(12.5))
                .foregroundStyle(Palette.warmInkFaint)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 480, alignment: .leading)
        }
        .padding(.bottom, 18)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Same visual language as `HomeView`'s own `emptyState(_:)` — an
    /// italic note on a flat warm fill — shown in place of the "Try
    /// asking" suggestions, which would otherwise let you fire off a
    /// question `AskMurmur.ask` can only answer with "you don't have any
    /// dictations yet" after a real round-trip through "Thinking…".
    private var noHistoryNotice: some View {
        Text("You don't have any dictations yet — dictate a few things, then come back and ask about them.")
            .font(.manrope(12.5))
            .italic()
            .foregroundStyle(Palette.warmInkFaint)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 16)
            .padding(.horizontal, 14)
            .background(Palette.warmRowBorder, in: RoundedRectangle(cornerRadius: Radius.lg))
    }

    private var composer: some View {
        // Main.dc.html: `align-items: center` on this row. `.bottom` here
        // previously aligned the 34pt icon circles to the bottom of the
        // (taller, ~38pt) text field instead of centering them against
        // it, which is what actually produced the uneven gap — more space
        // above the circles than below, since only the *top* difference
        // was left unaccounted for.
        HStack(alignment: .center, spacing: 6) {
            TextField("Ask about anything you've dictated…", text: $question, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.manrope(13.5))
                .foregroundStyle(Palette.warmInk)
                .lineLimit(1...5)
                .padding(.vertical, 9)
                .padding(.leading, 16)
                .disabled(app.entries.isEmpty)
                .onSubmit(ask)
                // The dedicated mic button this field used to have next
                // to it was purely decorative — its action was empty, by
                // design (dictation here is the same global hotkey as
                // everywhere else, not a second click-to-record control)
                // — but sitting right beside a *working* send button, a
                // control that presses like a button and does nothing
                // read as broken rather than intentional. Removed, with
                // the hint it carried moved onto the field itself so the
                // hotkey is still discoverable on hover.
                .help("Hold \(app.hotkey.displayName) to speak your question")
            Button(action: ask) {
                // Circle stays the same neutral fill the mic button used
                // to have — only the glyph itself picks up the accent
                // orange, always, not just once there's something to
                // send. `sunsetDeep`, not `sunset`: the latter is tuned
                // for big saturated fills (the hero gradient, the logo
                // badge) and reads as washed out at icon scale —
                // `sunsetDeep` is already this redesign's own answer for
                // small text/icon accents (stat-strip trends, history
                // timestamps). No opacity dimming while disabled either —
                // that was fading the *background* along with the glyph,
                // so the circle stopped matching the design's own
                // `#F0EEE7` the moment the field was empty.
                MurmurIconView(icon: .arrowRight)
                    .frame(width: 15, height: 15)
                    .foregroundStyle(Palette.sunsetDeep)
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(Palette.warmRowBorder))
            }
            .buttonStyle(PressScaleButtonStyle(scale: 0.92))
            .disabled(!canSend)
        }
        .padding(6)
        // Matches the text field's own 16pt *leading* inset (above) on
        // the trailing side too — without this, the gap after the arrow
        // circle was just the bare 6pt outer padding, well short of the
        // 6+16 the text side gets before its own content starts.
        .padding(.trailing, 16)
        // No drop shadow, by request — same call as Scratchpad's editor
        // card: it read as an odd smear along the bottom edge sitting on
        // the frosted glass panel.
        .background(Color.white, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(Palette.warmRowBorder, lineWidth: 1))
        .padding(.top, 10)
    }

    private var canSend: Bool {
        !app.askThinking
            && !app.entries.isEmpty
            && !question.trimmingCharacters(in: .whitespaces).isEmpty
            && app.rewriteEngine.isAvailable
    }

    private func ask() {
        let submitted = question.trimmingCharacters(in: .whitespaces)
        guard !submitted.isEmpty, !app.askThinking else { return }
        question = ""
        app.askThinking = true
        let conversation = recentConversation()
        let turn = ChatTurn(question: submitted, answer: nil)
        app.askTurns.append(turn)
        Task {
            defer { app.askThinking = false }
            let result = try? await AskMurmur.ask(
                submitted, history: app.entries, meetings: app.notetaker.notes, engine: app.rewriteEngine,
                conversation: conversation, voice: Settings.useVoiceProfile ? app.voiceProfile : nil)
            guard let index = app.askTurns.firstIndex(where: { $0.id == turn.id }) else { return }
            app.askTurns[index].answer = result?.text ?? "Something went wrong answering that — try again."
            app.askTurns[index].sources = result?.sources ?? []
        }
    }

    /// Re-asks one turn's own question in place — same retrieval and
    /// conversation context it would get freshly asked today, just without
    /// having to retype it. Blocked while another ask is already in
    /// flight, same as the composer's own send button.
    private func regenerate(_ turn: ChatTurn) {
        guard !app.askThinking,
              let index = app.askTurns.firstIndex(where: { $0.id == turn.id })
        else { return }
        let conversation = recentConversation(before: index)
        app.askTurns[index].answer = nil
        app.askTurns[index].sources = []
        app.askThinking = true
        Task {
            defer { app.askThinking = false }
            let result = try? await AskMurmur.ask(
                turn.question, history: app.entries, meetings: app.notetaker.notes, engine: app.rewriteEngine,
                conversation: conversation, voice: Settings.useVoiceProfile ? app.voiceProfile : nil)
            guard let idx = app.askTurns.firstIndex(where: { $0.id == turn.id }) else { return }
            app.askTurns[idx].answer = result?.text ?? "Something went wrong answering that — try again."
            app.askTurns[idx].sources = result?.sources ?? []
        }
    }

    /// The last few completed turns before `index` (or before the end of
    /// the thread, for a new question), as `AskMurmur.ask`'s own
    /// conversation-recap shape. Capped at 3 for the same reason a single
    /// call's own NOTES context is capped — a short recap keeps "it"/"that"
    /// resolvable without the prompt growing over the whole thread.
    private func recentConversation(before index: Int? = nil) -> [AskMurmur.PriorTurn] {
        let slice = index.map { Array(app.askTurns.prefix($0)) } ?? app.askTurns
        return slice.suffix(3).compactMap { turn in
            turn.answer.map { AskMurmur.PriorTurn(question: turn.question, answer: $0) }
        }
    }
}

private struct TurnView: View {
    let turn: AskPage.ChatTurn
    let canRegenerate: Bool
    let onRegenerate: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Spacer(minLength: 60)
                // `.chat-bubble-user`: fixed dark fill, white text, with
                // the bottom-right corner tightened into a tail.
                Text(turn.question)
                    .font(.manrope(13.5))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(
                        UnevenRoundedRectangle(
                            topLeadingRadius: 16,
                            bottomLeadingRadius: 16,
                            bottomTrailingRadius: 5,
                            topTrailingRadius: 16)
                            .fill(Palette.navActivePill))
                    .frame(maxWidth: 420, alignment: .trailing)
            }
            if let answer = turn.answer {
                HStack(alignment: .top, spacing: 10) {
                    ZStack {
                        Circle().fill(Palette.sunsetSoft)
                        MurmurIconView(icon: .wave)
                            .frame(width: 12, height: 12)
                            .foregroundStyle(Palette.sunset)
                    }
                    .frame(width: 22, height: 22)
                    VStack(alignment: .leading, spacing: 8) {
                        Text(answer)
                            .font(.manrope(13))
                            .foregroundStyle(Palette.warmInk)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                        HStack(spacing: 2) {
                            IconButton(icon: .copy, size: 22, iconSize: 12, help: "Copy") {
                                let pb = NSPasteboard.general
                                pb.clearContents()
                                pb.setString(answer, forType: .string)
                            }
                            IconButton(icon: .arrowRight, size: 22, iconSize: 12,
                                       help: "Paste at cursor in the app behind Murmur") {
                                TextInserter.insert(answer)
                            }
                            IconButton(icon: .refresh, size: 22, iconSize: 12, help: "Ask again") {
                                onRegenerate()
                            }
                            .disabled(!canRegenerate)
                        }
                        if !turn.sources.isEmpty {
                            SourcesDisclosure(sources: turn.sources)
                        }
                    }
                }
            } else {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Thinking…")
                        .font(.manrope(12))
                        .foregroundStyle(Palette.warmInkSoft)
                }
            }
        }
    }
}

/// "Based on N notes", expanding to the actual notes an answer was
/// generated from — so an on-device answer over the user's own dictated
/// history can be checked, not just trusted.
private struct SourcesDisclosure: View {
    let sources: [AskMurmur.AskSource]

    private static let maxShown = 8

    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                withAnimation(.murmurEase(0.12)) { expanded.toggle() }
            } label: {
                HStack(spacing: 4) {
                    Text("Based on \(sources.count) note\(sources.count == 1 ? "" : "s")")
                    MurmurIconView(icon: .caret)
                        .frame(width: 7, height: 7)
                        .rotationEffect(.degrees(expanded ? 90 : 0))
                }
                .font(.manrope(11, .medium))
                .foregroundStyle(Palette.warmInkFaint)
            }
            .buttonStyle(.plain)

            if expanded {
                let shown = Array(sources.prefix(Self.maxShown))
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(shown.enumerated()), id: \.offset) { index, source in
                        HStack(alignment: .top, spacing: 8) {
                            Text(source.date, format: .dateTime.month(.abbreviated).day().hour().minute())
                                .font(.manrope(10.5, .semibold))
                                .foregroundStyle(Palette.warmInkFaint)
                                .frame(width: 74, alignment: .leading)
                            // A meeting note's preview is just its title —
                            // marked with a small prefix so it's obvious at
                            // a glance which citations are dictations and
                            // which are meetings, without needing a second
                            // icon column.
                            Text((source.kind == .meeting ? "Meeting: " : "")
                                 + source.preview.replacingOccurrences(of: "\n", with: " "))
                                .font(.manrope(11.5))
                                .foregroundStyle(Palette.warmInkSoft)
                                .lineLimit(1)
                        }
                        .padding(.vertical, 5)
                        if index != shown.count - 1 {
                            Rectangle().fill(Palette.warmDivider).frame(height: 1)
                        }
                    }
                    if sources.count > Self.maxShown {
                        Text("+ \(sources.count - Self.maxShown) more")
                            .font(.manrope(10.5))
                            .foregroundStyle(Palette.warmInkFaint)
                            .padding(.top, 4)
                    }
                }
                .padding(10)
                .background(Palette.warmRowBorder, in: RoundedRectangle(cornerRadius: Radius.sm))
            }
        }
    }
}

private struct SuggestionChip: View {
    let text: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                MurmurIconView(icon: .ask)
                    .frame(width: 12, height: 12)
                    .foregroundStyle(Palette.sunsetDeep)
                Text(text)
                    .font(.manrope(12.5))
                    .foregroundStyle(Palette.warmInk)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(hovering ? Palette.warmRowBorder : Color.white,
                        in: RoundedRectangle(cornerRadius: Radius.md))
            .contentShape(Rectangle())
        }
        .buttonStyle(PressScaleButtonStyle(scale: 0.99))
        .onHover { hovering = $0 }
        .animation(.murmurEase(0.12), value: hovering)
    }
}
