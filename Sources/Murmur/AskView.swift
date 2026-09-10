import AppKit
import SwiftUI

// MARK: - Ask Murmur
//
// Redesigned per the "Main" canvas (Ask.dc.html): same `GlassPanelPage`
// shell as Home/Insights/Scratchpad, warm palette instead of the shared
// dynamic `Palette`. Structurally unchanged from the previous pass — a
// real chat layout where the conversation scrolls and the composer stays
// pinned to the bottom.

struct AskPage: View {
    @ObservedObject var app: AppDelegate
    @State private var question = ""
    @State private var turns: [ChatTurn] = []
    @State private var asking = false

    struct ChatTurn: Identifiable {
        let id = UUID()
        let question: String
        var answer: String?
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

                            if turns.isEmpty {
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

                            ForEach(turns) { turn in
                                VStack(alignment: .leading, spacing: 14) {
                                    HStack {
                                        Spacer(minLength: 60)
                                        // `.chat-bubble-user`: fixed dark
                                        // fill, white text, with the
                                        // bottom-right corner tightened
                                        // into a tail.
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
                                .padding(.bottom, 22)
                                .id(turn.id)
                            }
                            Color.clear.frame(height: 1).id("bottom")
                        }
                    }
                    .onChange(of: turns.count) { _, _ in
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
        !asking
            && !question.trimmingCharacters(in: .whitespaces).isEmpty
            && app.rewriteEngine.isAvailable
    }

    private func ask() {
        let submitted = question.trimmingCharacters(in: .whitespaces)
        guard !submitted.isEmpty, !asking else { return }
        question = ""
        asking = true
        let turn = ChatTurn(question: submitted, answer: nil)
        turns.append(turn)
        Task {
            defer { asking = false }
            let answer = (try? await AskMurmur.ask(
                submitted, history: app.entries, engine: app.rewriteEngine,
                voice: Settings.useVoiceProfile ? app.voiceProfile : nil))
                ?? "Something went wrong answering that — try again."
            if let index = turns.firstIndex(where: { $0.id == turn.id }) {
                turns[index].answer = answer
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
