import AppKit
import SwiftUI

// MARK: - Ask Murmur
//
// A real chat layout per the design: the conversation scrolls and the
// composer is pinned to the bottom, instead of the old static Q&A block
// with the field below the content.

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
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        PageHeader(
                            title: "Ask Murmur",
                            subtitle: "Chat over your entire dictation history — on-device, nothing sent anywhere.")

                        if let note = app.rewriteEngine.availabilityNote {
                            PageTip(text: note)
                                .padding(.bottom, 16)
                        }

                        if turns.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Try asking")
                                    .font(.manrope(12, .semibold))
                                    .foregroundStyle(Palette.inkSoft)
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
                                    // `.chat-bubble-user`: ink fill, on-ink
                                    // text, with the bottom-right corner
                                    // tightened into a tail.
                                    Text(turn.question)
                                        .font(.manrope(13.5))
                                        .foregroundStyle(Palette.onInk)
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 10)
                                        .background(
                                            UnevenRoundedRectangle(
                                                topLeadingRadius: 16,
                                                bottomLeadingRadius: 16,
                                                bottomTrailingRadius: 5,
                                                topTrailingRadius: 16)
                                                .fill(Palette.ink))
                                        .frame(maxWidth: 420, alignment: .trailing)
                                }
                                if let answer = turn.answer {
                                    HStack(alignment: .top, spacing: 10) {
                                        ZStack {
                                            Circle().fill(Palette.accentSoft)
                                            MurmurIconView(icon: .wave)
                                                .frame(width: 12, height: 12)
                                                .foregroundStyle(Palette.accentText)
                                        }
                                        .frame(width: 22, height: 22)
                                        VStack(alignment: .leading, spacing: 8) {
                                            Text(answer)
                                                .font(.manrope(13))
                                                .foregroundStyle(Palette.ink)
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
                                            .foregroundStyle(Palette.inkSoft)
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

    private var composer: some View {
        HStack(alignment: .bottom, spacing: 6) {
            TextField("Ask about anything you've dictated…", text: $question, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.manrope(13.5))
                .lineLimit(1...5)
                .padding(.vertical, 9)
                .padding(.leading, 16)
                .onSubmit(ask)
            // Speak your question: same dictation mechanism as anywhere
            // else — the hint tells you to use the global key rather than
            // implying a second, separate recorder lives here.
            Button {} label: {
                MurmurIconView(icon: .mic)
                    .frame(width: 15, height: 15)
                    .foregroundStyle(Palette.inkSoft)
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(Palette.card))
            }
            .buttonStyle(PressScaleButtonStyle(scale: 0.92))
            .help("Click into the field and hold \(app.hotkey.displayName) to speak your question")
            Button(action: ask) {
                MurmurIconView(icon: .arrowRight)
                    .frame(width: 15, height: 15)
                    .foregroundStyle(canSend ? Palette.accentInk : Palette.inkFaint)
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(canSend ? Palette.accent : Palette.card))
            }
            .buttonStyle(PressScaleButtonStyle(scale: 0.92))
            .disabled(!canSend)
        }
        .padding(6)
        .padding(.leading, 0)
        .background(Palette.panel, in: RoundedRectangle(cornerRadius: Radius.lg))
        .overlay(RoundedRectangle(cornerRadius: Radius.lg).stroke(Palette.border, lineWidth: 1))
        .murmurShadow()
        .padding(.top, 10)
        .padding(.bottom, 26)
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
                    .foregroundStyle(Palette.accentText)
                Text(text)
                    .font(.manrope(12.5))
                    .foregroundStyle(Palette.ink)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(hovering ? Palette.cardHover : Palette.card,
                        in: RoundedRectangle(cornerRadius: Radius.md))
            .contentShape(Rectangle())
        }
        .buttonStyle(PressScaleButtonStyle(scale: 0.99))
        .onHover { hovering = $0 }
        .animation(.murmurEase(0.12), value: hovering)
    }
}
