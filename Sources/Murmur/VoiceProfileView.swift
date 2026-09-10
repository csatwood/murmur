import AppKit
import SwiftUI

// MARK: - Voice Profile / Voice Training
//
// Redesigned per the "Main" canvas (VoiceProfile.dc.html): same
// `GlassPanelPage` shell as the other redesigned pages, warm palette
// instead of the shared dynamic `Palette`. `TrainingModel` (the actual
// recording/transcription/learning logic) is untouched — this is a
// View-layer rewrite only.
//
// The toggle row, chips, and tip banner are bespoke to this page rather
// than the shared `FieldRow`/`MurmurToggle`/`ChipRow`/`PageTip` components
// — those are still tuned for the old dynamic/lime palette and shared with
// pages that haven't been redesigned yet (Settings uses `MurmurToggle` and
// `FieldRow` extensively), so forking them here keeps this page exact
// without changing how they look anywhere else.

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
        GlassPanelPage {
            // `ThinScrollView`, not a plain `ScrollView` — see
            // ScratchpadView.swift's own note on why: a bare
            // `.scrollIndicators(.hidden)` doesn't reliably suppress
            // macOS's native scroller by itself.
            ThinScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    header
                    personaCard
                        .padding(.top, 18)
                    useVoiceRow
                    teachCard
                        .padding(.top, 4)

                    HStack(alignment: .lastTextBaseline) {
                        Text("Learned corrections")
                            .font(.manrope(14, .semibold))
                            .foregroundStyle(Palette.warmInk)
                        Spacer()
                        Text(correctionsCount)
                            .font(.manrope(11.5))
                            .foregroundStyle(Palette.warmInkFaint)
                    }
                    .padding(.top, 22)
                    Text("Also learned automatically when you fix a transcript in History (pencil icon).")
                        .font(.manrope(11.5))
                        .foregroundStyle(Palette.warmInkFaint)
                        .padding(.top, 4)
                        .padding(.bottom, 12)

                    correctionsList

                    if !learned.terms.isEmpty {
                        Text("Vocabulary hints: " + learned.terms.joined(separator: ", "))
                            .font(.manrope(11.5))
                            .foregroundStyle(Palette.warmInkFaint)
                            .padding(.top, 12)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    relatedLink
                        .padding(.top, 14)
                }
            }
        }
        .onAppear { learned = LearnedStore.load() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Voice Profile")
                .font(.manrope(22, .medium))
                .tracking(-0.33)
                .foregroundStyle(Palette.warmInk)
            Text("Say a word Murmur keeps mishearing — it learns the correction, "
                 + "and your persona on Home updates as you go.")
                .font(.manrope(12.5))
                .lineSpacing(3)
                .foregroundStyle(Palette.warmInkFaint)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 620, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Persona

    private var personaCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("YOUR PERSONA")
                    .font(.manrope(11, .medium))
                    .kerning(0.7)
                    .foregroundStyle(Palette.warmInkFaint)
                Spacer()
                if app.voiceProfile != nil {
                    IconButton(icon: .refresh, help: "Refresh profile") {
                        app.refreshVoiceProfileIfDue(force: true)
                    }
                }
            }
            Text(app.voiceProfile?.title ?? "Still listening…")
                .font(.manrope(20, .medium))
                .foregroundStyle(Palette.warmInk)
                .padding(.top, 8)
            Text(app.voiceProfile?.summary
                 ?? "Dictate a bit more and Murmur will sketch your persona from what you talk about.")
                .font(.manrope(13))
                .lineSpacing(3)
                .foregroundStyle(Palette.warmInkSoft)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 6)
            if let traits = app.voiceProfile?.traits, !traits.isEmpty {
                HStack(spacing: 8) {
                    ForEach(traits, id: \.self) { warmChip($0) }
                }
                .padding(.top, 10)
            }
            Rectangle().fill(Palette.warmRowBorder).frame(height: 1).padding(.top, 14)
            Text((Locale.current.localizedString(forIdentifier: app.localeID) ?? app.localeID)
                 + " · Hold \(app.hotkey.displayName)")
                .font(.manrope(12))
                .foregroundStyle(Palette.warmInkSoft)
                .padding(.top, 12)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 20)
        // Without this, the card sizes to its own widest line of content
        // instead of the full glass panel — every card here is short text
        // and pill chips, none of which need the full width to lay out, so
        // the card was shrink-wrapping to that and (being left-aligned)
        // leaving the leftover space stranded on the right instead of
        // split evenly on both sides.
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func warmChip(_ text: String) -> some View {
        Text(text)
            .font(.manrope(11.5))
            .foregroundStyle(Palette.warmInkSoft)
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(Color.white, in: Capsule())
            .overlay(Capsule().stroke(Palette.warmRowBorder, lineWidth: 1))
    }

    // MARK: Use my voice toggle
    //
    // The profile used to be display-only. Now it feeds every rewrite and
    // every Ask answer, so it needs an off switch. A plain row directly on
    // the glass panel, not a card — matches the mockup, which gives this
    // no fill of its own (`padding: 14px 4px`, no background).

    private var useVoiceRow: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Use my voice in rewrites")
                    .font(.manrope(12.5, .semibold))
                    .foregroundStyle(Palette.warmInk)
                Text("Style and template rewrites keep your vocabulary and "
                     + "phrasing, and Ask answers read your notes in your terms.")
                    .font(.manrope(11))
                    .lineSpacing(2)
                    .foregroundStyle(Palette.warmInkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 16)
            warmToggle
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 14)
    }

    /// `MurmurToggle` with a fixed accent — that shared component's
    /// "on" fill is `Palette.toggleOn` (the old dynamic/lime accent), and
    /// it's used throughout Settings, so it isn't touched here; this is a
    /// one-off matching Main.dc.html's own sunset-orange track exactly.
    private var warmToggle: some View {
        Button {
            withAnimation(.murmurEase(0.18)) {
                useVoiceProfile.toggle()
                Settings.useVoiceProfile = useVoiceProfile
            }
        } label: {
            ZStack(alignment: useVoiceProfile ? .trailing : .leading) {
                Capsule()
                    .fill(useVoiceProfile ? Palette.sunset : Palette.warmDivider)
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

    // MARK: Teach a word

    private var teachCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("TEACH A WORD")
                .font(.manrope(11, .medium))
                .kerning(0.7)
                .foregroundStyle(Palette.warmInkFaint)

            HStack(spacing: 8) {
                TextField("word or phrase, e.g. “Søren” or “Baseten”", text: $target)
                    .textFieldStyle(.plain)
                    .font(.manrope(12.5))
                    .foregroundStyle(Palette.warmInk)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: Radius.sm))
                    .overlay(RoundedRectangle(cornerRadius: Radius.sm).stroke(Palette.warmRowBorder, lineWidth: 1))

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
                                     ? .white : (visuallyMuted ? Palette.warmInkFainter : .white))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 9)
                    .background(
                        RoundedRectangle(cornerRadius: Radius.sm)
                            .fill(visuallyMuted
                                  ? AnyShapeStyle(Palette.warmRowBorder)
                                  : AnyShapeStyle(model.isRecording ? Palette.danger : Palette.sunset)))
                }
                .buttonStyle(PressScaleButtonStyle())
                .disabled(recordDisabled)

                if model.isProcessing {
                    ProgressView().controlSize(.small)
                }
            }
            .padding(.top, 12)

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
                    .foregroundStyle(model.resultIsError ? Palette.danger : Palette.sunsetDeep)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 10)
                    .onAppear { learned = LearnedStore.load() }
            }

            HStack(alignment: .top, spacing: 8) {
                MurmurIconView(icon: .help)
                    .frame(width: 13, height: 13)
                    .foregroundStyle(Palette.warmInkSoft)
                    .padding(.top, 1)
                Text("Repeat a word 2–3 times — different mishearings each become "
                     + "their own correction.")
                    .font(.manrope(12.5))
                    .lineSpacing(3)
                    .foregroundStyle(Palette.warmInkSoft)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .padding(.top, 12)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 20)
        // Same fix as personaCard above: without this the card shrinks to
        // its own content's width instead of the full glass panel.
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
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

    // MARK: Learned corrections

    private var correctionsList: some View {
        Group {
            if learned.corrections.isEmpty {
                Text("Nothing learned yet — corrections you make while dictating will show up here.")
                    .font(.manrope(12.5))
                    .italic()
                    .foregroundStyle(Palette.warmInkFaint)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
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
                            Rectangle().fill(Palette.warmRowBorder).frame(height: 1)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 2)
                // Same fix as personaCard/teachCard above: rows are all
                // short text, so without this the card shrinks to their
                // width instead of the full glass panel.
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            }
        }
    }

    private var relatedLink: some View {
        HStack(spacing: 4) {
            Text("Setting a word manually instead?")
                .font(.manrope(12))
                .foregroundStyle(Palette.warmInkSoft)
            Button { page = .dictionary } label: {
                Text("Dictionary")
                    .font(.manrope(12, .medium))
                    .foregroundStyle(Palette.sunsetDeep)
            }
            .buttonStyle(.plain)
            Text("lets you define exact replacements.")
                .font(.manrope(12))
                .foregroundStyle(Palette.warmInkSoft)
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

private struct CorrectionRow: View {
    let correction: LearnedCorrection
    let onDelete: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 16) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("“\(correction.heard)”")
                    .foregroundStyle(Palette.warmInkSoft)
                Text("→").foregroundStyle(Palette.warmInkFaint)
                Text("“\(correction.intended)”")
                    .font(.manrope(13, .medium))
                    .foregroundStyle(Palette.warmInk)
                if correction.timesSeen > 1 {
                    Text("×\(correction.timesSeen)")
                        .font(.manrope(11))
                        .foregroundStyle(Palette.warmInkFainter)
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
                .fill(hovering ? Palette.warmRowBorder : Color.clear))
        // See HomeView.swift's historyRow for why this is needed: a .clear
        // background makes SwiftUI treat the row's empty space as outside
        // the hoverable region until this forces the whole padded frame to
        // count, regardless of what's actually drawn there.
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
    }
}
