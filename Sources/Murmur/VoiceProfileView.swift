import AppKit
import SwiftUI

// MARK: - Voice Profile / Voice Training
//
// The design's Voice Profile page: the persona card Home only teases, the
// teach-a-word recorder, and the learned-correction history — all three on
// one page instead of the old bare form + list.

@MainActor
final class TrainingModel: ObservableObject {
    @Published var isRecording = false
    @Published var isProcessing = false
    @Published var heard: String?
    @Published var result: String?
    @Published var resultIsError = false

    private let recorder = AudioRecorder()

    func toggle(app: AppDelegate, target: String) {
        if isRecording {
            stop(app: app, target: target)
        } else {
            start()
        }
    }

    private func start() {
        heard = nil
        result = nil
        resultIsError = false
        do {
            try recorder.start()
            isRecording = true
            NSSound(named: "Pop")?.play()
        } catch {
            result = "Could not start recording: \(error.localizedDescription)"
            resultIsError = true
        }
    }

    private func stop(app: AppDelegate, target: String) {
        isRecording = false
        guard let url = recorder.stop() else { return }
        NSSound(named: "Tink")?.play()
        isProcessing = true
        Task {
            defer {
                isProcessing = false
                try? FileManager.default.removeItem(at: url)
            }
            do {
                let raw = try await app.transcribeRaw(fileAt: url)
                let cleaned = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                    .trimmingCharacters(in: CharacterSet(charactersIn: ".,!?"))
                heard = cleaned.isEmpty ? nil : cleaned
                let intended = target.trimmingCharacters(in: .whitespaces)
                guard let heardText = heard else {
                    result = "Nothing was heard — try again, a bit louder."
                    resultIsError = true
                    return
                }
                if heardText.lowercased() == intended.lowercased() {
                    LearnedStore.addTerm(intended)
                    result = "Recognized correctly! Added “\(intended)” to your "
                        + "vocabulary so it stays reliable."
                    resultIsError = false
                } else {
                    LearnedStore.add(heard: heardText, intended: intended)
                    result = "Learned: “\(heardText)” → “\(intended)”. Murmur will "
                        + "make this correction automatically from now on."
                    resultIsError = false
                }
            } catch {
                result = "Transcription failed: \(error.localizedDescription)"
                resultIsError = true
            }
        }
    }
}

struct TrainingPage: View {
    @ObservedObject var app: AppDelegate
    @Binding var page: Page
    @StateObject private var model = TrainingModel()
    @State private var target = ""
    @State private var learned = LearnedStore.load()
    @State private var useVoiceProfile = Settings.useVoiceProfile

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PageHeader(
                title: "Voice Profile",
                subtitle: "Say a word Murmur keeps mishearing — it learns the correction, "
                    + "and your persona on Home updates as you go.")

            personaCard

            // The profile used to be display-only. Now it feeds every
            // rewrite and every Ask answer, so it needs an off switch.
            Card(flat: true) {
                FieldRow(
                    label: "Use my voice in rewrites",
                    detail: "Style and template rewrites keep your vocabulary and "
                        + "phrasing, and Ask answers read your notes in your terms.",
                    isLast: true
                ) {
                    MurmurToggle(isOn: $useVoiceProfile)
                        .onChange(of: useVoiceProfile) { _, newValue in
                            Settings.useVoiceProfile = newValue
                        }
                }
            }
            .padding(.top, 4)
            teachCard.padding(.top, 16)

            SectionHead(title: "Learned corrections", trailing: correctionsCount)
            Text("Also learned automatically when you fix a transcript in History (pencil icon).")
                .font(.manrope(11.5))
                .foregroundStyle(Palette.inkSoft)
                .padding(.bottom, 10)

            if learned.corrections.isEmpty {
                Text("Nothing learned yet — corrections you make while dictating will show up here.")
                    .font(.manrope(12.5))
                    .italic()
                    .foregroundStyle(Palette.inkFaint)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
            } else {
                VStack(spacing: 0) {
                    let items = Array(learned.corrections.reversed())
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, correction in
                        CorrectionRow(correction: correction) {
                            var data = LearnedStore.load()
                            data.corrections.removeAll { $0.id == correction.id }
                            LearnedStore.save(data)
                            learned = data
                        }
                        if index != items.count - 1 {
                            Rectangle().fill(Palette.border).frame(height: 1)
                        }
                    }
                }
            }

            if !learned.terms.isEmpty {
                Text("Vocabulary hints: " + learned.terms.joined(separator: ", "))
                    .font(.manrope(11.5))
                    .foregroundStyle(Palette.inkFaint)
                    .padding(.top, 12)
                    .fixedSize(horizontal: false, vertical: true)
            }

            RelatedLink(
                prefix: "Setting a word manually instead?",
                linkTitle: "Dictionary",
                suffix: "lets you define exact replacements."
            ) { page = .dictionary }
        }
        .onAppear { learned = LearnedStore.load() }
    }

    private var personaCard: some View {
        Card {
            HStack {
                Text("YOUR PERSONA")
                    .font(.manrope(11, .medium))
                    .kerning(0.7)
                    .foregroundStyle(Palette.inkSoft)
                Spacer()
                if app.voiceProfile != nil {
                    IconButton(icon: .refresh, help: "Refresh profile") {
                        app.refreshVoiceProfileIfDue(force: true)
                    }
                }
            }
            Text(app.voiceProfile?.title ?? "Still listening…")
                .font(.manrope(20, .medium))
                .foregroundStyle(Palette.ink)
                .padding(.top, 8)
            Text(app.voiceProfile?.summary
                 ?? "Dictate a bit more and Murmur will sketch your persona from what you talk about.")
                .font(.manrope(13))
                .foregroundStyle(Palette.inkSoft)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 6)
            if let traits = app.voiceProfile?.traits, !traits.isEmpty {
                ChipRow(items: traits).padding(.top, 10)
            }
            Divider().overlay(Palette.border).padding(.top, 14)
            Text((Locale.current.localizedString(forIdentifier: app.localeID) ?? app.localeID)
                 + " · Hold \(app.hotkey.displayName)")
                .font(.manrope(12))
                .foregroundStyle(Palette.inkSoft)
                .padding(.top, 12)
        }
    }

    private var teachCard: some View {
        Card {
            Text("TEACH A WORD")
                .font(.manrope(11, .medium))
                .kerning(0.7)
                .foregroundStyle(Palette.inkSoft)
                .padding(.bottom, 12)

            HStack(spacing: 8) {
                TextField("word or phrase, e.g. “Søren” or “Baseten”", text: $target)
                    .textFieldStyle(.plain)
                    .font(.manrope(12.5))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(Palette.panel, in: RoundedRectangle(cornerRadius: Radius.sm))
                    .overlay(RoundedRectangle(cornerRadius: Radius.sm).stroke(Palette.border, lineWidth: 1))

                Button {
                    model.toggle(app: app, target: target)
                } label: {
                    HStack(spacing: 7) {
                        if model.isRecording {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(.white)
                                .frame(width: 10, height: 10)
                            Text("Stop").font(.manrope(12.5, .semibold))
                        } else {
                            MurmurIconView(icon: .mic).frame(width: 14, height: 14)
                            Text("Record").font(.manrope(12.5, .semibold))
                        }
                    }
                    .foregroundStyle(model.isRecording
                                     ? .white : (visuallyMuted ? Palette.inkFaint : Palette.accentInk))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 9)
                    .background(
                        RoundedRectangle(cornerRadius: Radius.sm)
                            .fill(visuallyMuted
                                  ? AnyShapeStyle(Palette.cardHover)
                                  : AnyShapeStyle(model.isRecording ? Palette.danger : Palette.accent)))
                }
                .buttonStyle(PressScaleButtonStyle())
                .disabled(recordDisabled)

                if model.isProcessing {
                    ProgressView().controlSize(.small)
                }
            }

            if model.isRecording {
                HStack(spacing: 6) {
                    MurmurIconView(icon: .wave).frame(width: 13, height: 13)
                    Text("Say “\(target)” now, then press Stop.")
                        .font(.manrope(12.5, .medium))
                }
                .foregroundStyle(Palette.danger)
                .padding(.top, 10)
            } else if let result = model.result {
                Text(result)
                    .font(.manrope(12.5, .medium))
                    .foregroundStyle(model.resultIsError ? Palette.danger : Palette.accentText)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 10)
                    .onAppear { learned = LearnedStore.load() }
            }

            PageTip(text: "Repeat a word 2–3 times — different mishearings each become "
                    + "their own correction.")
                .padding(.top, 12)
        }
    }

    private var recordDisabled: Bool {
        target.trimmingCharacters(in: .whitespaces).isEmpty
            || model.isProcessing
            || !app.micAuthorized
    }

    /// The design's `.vp-record-btn:disabled` look is only ever driven by
    /// actually-busy states (processing, no mic access) — the mockup never
    /// gates the button's *appearance* on the input being empty, even
    /// though `recordDisabled` above correctly still blocks the *click*
    /// there (recording against a blank target would teach a bogus
    /// correction). So the button reads as its normal accent color even
    /// before you've typed a word, matching the design, while staying
    /// inert until you have.
    private var visuallyMuted: Bool {
        model.isProcessing || !app.micAuthorized
    }

    private var correctionsCount: String {
        let n = learned.corrections.count
        return "\(n) \(n == 1 ? "correction" : "corrections")"
    }
}

private struct CorrectionRow: View {
    let correction: LearnedCorrection
    let onDelete: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 16) {
            HStack(spacing: 6) {
                Text("“\(correction.heard)”")
                    .foregroundStyle(Palette.inkSoft)
                Text("→").foregroundStyle(Palette.inkFaint)
                Text("“\(correction.intended)”")
                    .font(.manrope(13, .medium))
                    .foregroundStyle(Palette.ink)
                if correction.timesSeen > 1 {
                    Text("×\(correction.timesSeen)")
                        .font(.manrope(11))
                        .foregroundStyle(Palette.inkFaint)
                }
            }
            .font(.manrope(13))
            .frame(maxWidth: .infinity, alignment: .leading)

            IconButton(icon: .trash, size: 22, iconSize: 12, help: "Remove", action: onDelete)
                .opacity(hovering ? 1 : 0)
                .animation(.easeOut(duration: 0.1), value: hovering)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 15)
        .background(
            RoundedRectangle(cornerRadius: Radius.sm)
                .fill(hovering ? Palette.cardHover : Color.clear))
        // See HomeView.swift's historyRow for why this is needed: a .clear
        // background makes SwiftUI treat the row's empty space as outside
        // the hoverable region until this forces the whole padded frame to
        // count, regardless of what's actually drawn there.
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
    }
}
