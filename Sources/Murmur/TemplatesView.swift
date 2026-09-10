import AppKit
import SwiftUI

// MARK: - Templates
//
// Redesigned per the "Main" canvas (Templates.dc.html): same
// `GlassPanelPage` shell as the other redesigned pages, warm palette
// instead of the shared dynamic `Palette`. Functionally unchanged — a card
// grid, each card showing what the template actually produces plus its
// spoken trigger, with the voice toggle and the transcript workspace all
// on one page. `templateEditor`'s `.sheet` is deliberately left on the old
// dynamic palette and attached outside `GlassPanelPage`'s content, same
// call as HomeView's own sheet — see `GlassPanelPage`'s own doc comment on
// why presented content shouldn't be forced light.

struct TemplatesPage: View {
    @ObservedObject var app: AppDelegate
    @Binding var page: Page
    @State private var inputText = ""
    @State private var result = ""
    @State private var selectedTemplateID: UUID?
    @State private var running = false
    @State private var templates: [NoteTemplate] = NoteTemplateStore.all()
    @State private var showingEditor = false
    @State private var editorName = ""
    @State private var editorInstructions = ""
    @State private var editorTrigger = ""
    @State private var voiceTemplatesEnabled = Settings.voiceTemplatesEnabled

    /// `.grid3` — exactly three equal columns, not adaptive wrapping.
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 3)

    /// One-line descriptions of what each built-in actually produces —
    /// the card previously showed only a name.
    private func blurb(for template: NoteTemplate) -> String {
        switch template.name {
        case "Meeting Notes": return "Attendees, key points, decisions, action items"
        case "Summary": return "One short paragraph, about a quarter the length"
        case "Email Draft": return "Subject, greeting, body, sign-off"
        case "Task List": return "Every action item as a checkbox"
        case "Blog Post": return "Opening, subheadings, closing"
        default: return template.isBuiltIn ? "" : "Your custom template"
        }
    }

    var body: some View {
        GlassPanelPage {
            // `ThinScrollView`, not a plain `ScrollView` — see
            // ScratchpadView.swift's own note on why: a bare
            // `.scrollIndicators(.hidden)` doesn't reliably suppress
            // macOS's native scroller by itself.
            ThinScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    header

                    tipBanner("Say the trigger phrase first, then keep talking — Murmur strips "
                              + "it off and reshapes everything that follows.")
                        .padding(.top, 18)

                    applyByVoiceRow
                        .padding(.top, 14)

                    if let note = app.rewriteEngine.availabilityNote {
                        tipBanner(note).padding(.top, 12)
                    }

                    LazyVGrid(columns: columns, spacing: 10) {
                        ForEach(templates) { template in
                            templateCard(template)
                        }
                        newTemplateCard
                    }
                    .padding(.top, 14)

                    Text("Transcript")
                        .font(.manrope(14, .semibold))
                        .foregroundStyle(Palette.warmInk)
                        .padding(.top, 14)
                    transcriptCard
                        .padding(.top, 8)

                    if !result.isEmpty {
                        Text("Result")
                            .font(.manrope(14, .semibold))
                            .foregroundStyle(Palette.warmInk)
                            .padding(.top, 14)
                        resultCard
                            .padding(.top, 8)
                    }

                    relatedLink
                        .padding(.top, 14)
                }
            }
        }
        .onAppear(perform: consumePendingText)
        .onChange(of: app.pendingTemplateText) { _, _ in consumePendingText() }
        .sheet(isPresented: $showingEditor) { templateEditor }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Templates")
                .font(.manrope(22, .medium))
                .tracking(-0.33)
                .foregroundStyle(Palette.warmInk)
            Text("Restructure a transcript — say the trigger, get the shape, no clicking.")
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

    /// A bare flat row directly on the glass panel — no card, no border —
    /// matching the mockup's own treatment (unlike Voice Profile/App
    /// Profiles, nothing else on this page needed a flat field row, so
    /// this stays local rather than becoming a shared component).
    private var applyByVoiceRow: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 1) {
                Text("Apply by voice")
                    .font(.manrope(12.5, .semibold))
                    .foregroundStyle(Palette.warmInk)
                Text("Say a template's trigger phrase to reshape a dictation automatically")
                    .font(.manrope(11))
                    .foregroundStyle(Palette.warmInkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 16)
            WarmToggle(isOn: $voiceTemplatesEnabled)
                .onChange(of: voiceTemplatesEnabled) { _, newValue in
                    Settings.voiceTemplatesEnabled = newValue
                }
        }
        .padding(.horizontal, 4)
    }

    private func templateCard(_ template: NoteTemplate) -> some View {
        TemplateCard(
            template: template,
            blurb: blurb(for: template),
            selected: selectedTemplateID == template.id,
            voiceEnabled: voiceTemplatesEnabled,
            onSelect: { selectedTemplateID = template.id },
            onDelete: template.isBuiltIn ? nil : { deleteCustomTemplate(template) })
    }

    private var newTemplateCard: some View {
        Button {
            editorName = ""
            editorInstructions = ""
            editorTrigger = ""
            showingEditor = true
        } label: {
            HStack(spacing: 7) {
                MurmurIconView(icon: .plus).frame(width: 14, height: 14)
                Text("New template").font(.manrope(12, .semibold))
            }
            .foregroundStyle(Palette.warmInkSoft)
            .frame(maxWidth: .infinity, minHeight: 78)
            .background(
                RoundedRectangle(cornerRadius: Radius.md)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                    .foregroundStyle(Palette.warmDivider))
            .contentShape(Rectangle())
        }
        .buttonStyle(PressScaleButtonStyle(scale: 0.98))
    }

    private var transcriptCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            TextEditor(text: $inputText)
                .font(.manrope(13))
                .foregroundStyle(Palette.warmInk)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 110)
                .overlay(alignment: .topLeading) {
                    if inputText.isEmpty {
                        Text("Paste or dictate a transcript, or send one in from History…")
                            .font(.manrope(13))
                            .italic()
                            .foregroundStyle(Palette.warmInkFaint)
                            .padding(.top, 8)
                            .padding(.leading, 5)
                            .allowsHitTesting(false)
                    }
                }
            HStack(spacing: 10) {
                Button(action: generate) {
                    HStack(spacing: 7) {
                        if running {
                            ProgressView().controlSize(.small)
                        } else {
                            MurmurIconView(icon: .trans).frame(width: 13, height: 13)
                        }
                        Text(running ? "Generating…" : "Generate")
                            .font(.manrope(12.5, .semibold))
                    }
                    .foregroundStyle(canGenerate ? .white : Palette.warmInkFaint)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 9)
                    .background(
                        RoundedRectangle(cornerRadius: Radius.sm)
                            .fill(canGenerate ? Palette.sunset : Palette.warmRowBorder))
                }
                .buttonStyle(PressScaleButtonStyle())
                .disabled(!canGenerate)

                if selectedTemplateID == nil {
                    Text("Pick a shape above first")
                        .font(.manrope(11.5))
                        .foregroundStyle(Palette.warmInkFaint)
                }
                Spacer()
                if !inputText.isEmpty {
                    Button("Clear") { inputText = ""; result = "" }
                        .buttonStyle(.plain)
                        .font(.manrope(12.5, .medium))
                        .foregroundStyle(Palette.warmInkSoft)
                }
            }
            .padding(.top, 12)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
        // No drop shadow, by request — same call as every other white card
        // floating on the glass panel in this redesign.
        .background(Color.white, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var resultCard: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Spacer()
                IconButton(icon: .copy, help: "Copy") {
                    let pb = NSPasteboard.general
                    pb.clearContents()
                    pb.setString(result, forType: .string)
                }
                IconButton(icon: .arrowRight, help: "Paste at cursor in the app behind Murmur") {
                    TextInserter.insert(result)
                }
            }
            Text(result)
                .font(.manrope(13))
                .foregroundStyle(Palette.warmInk)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var relatedLink: some View {
        HStack(spacing: 4) {
            Text("Want a template applied automatically in one app?")
                .font(.manrope(12))
                .foregroundStyle(Palette.warmInkSoft)
            Button { page = .appProfiles } label: {
                Text("App Profiles")
                    .font(.manrope(12, .medium))
                    .foregroundStyle(Palette.sunsetDeep)
            }
            .buttonStyle(.plain)
            Text("set it there, no trigger phrase needed.")
                .font(.manrope(12))
                .foregroundStyle(Palette.warmInkSoft)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private var canGenerate: Bool {
        !running && !inputText.isEmpty && selectedTemplateID != nil
            && app.rewriteEngine.isAvailable
    }

    private func consumePendingText() {
        guard let pending = app.pendingTemplateText else { return }
        inputText = pending
        result = ""
        app.pendingTemplateText = nil
    }

    private func deleteCustomTemplate(_ template: NoteTemplate) {
        var custom = NoteTemplateStore.loadCustom()
        custom.removeAll { $0.id == template.id }
        NoteTemplateStore.saveCustom(custom)
        templates = NoteTemplateStore.all()
        if selectedTemplateID == template.id { selectedTemplateID = nil }
    }

    private func generate() {
        guard let template = templates.first(where: { $0.id == selectedTemplateID }) else { return }
        running = true
        result = ""
        Task {
            defer { running = false }
            do {
                result = try await app.rewriteEngine.edit(
                    inputText, instructions: template.instructions)
            } catch {
                result = "Failed: \(error.localizedDescription)"
            }
        }
    }

    /// Deliberately left on the old dynamic palette, outside the glass
    /// panel's light-pinned scope — see this file's own top-of-file note.
    private var templateEditor: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("New template").font(.manrope(16, .semibold))
            TextField("Name, e.g. \"Standup Update\"", text: $editorName)
                .textFieldStyle(.roundedBorder)
            Text("Instructions for the model")
                .font(.manrope(11.5))
                .foregroundStyle(Palette.inkSoft)
            TextEditor(text: $editorInstructions)
                .font(.manrope(13))
                .scrollContentBackground(.hidden)
                .padding(8)
                .frame(minHeight: 120)
                .background(Palette.card, in: RoundedRectangle(cornerRadius: Radius.md))
            Text("Voice trigger (optional)")
                .font(.manrope(11.5))
                .foregroundStyle(Palette.inkSoft)
            TextField("e.g. \"standup update\" — say this to apply hands-free", text: $editorTrigger)
                .textFieldStyle(.roundedBorder)
            HStack {
                Spacer()
                Button("Cancel") { showingEditor = false }
                Button("Save") {
                    var custom = NoteTemplateStore.loadCustom()
                    custom.append(NoteTemplate(
                        name: editorName.trimmingCharacters(in: .whitespaces),
                        icon: "doc.text",
                        instructions: editorInstructions.trimmingCharacters(in: .whitespacesAndNewlines),
                        voiceTrigger: editorTrigger.trimmingCharacters(in: .whitespaces).lowercased()))
                    NoteTemplateStore.saveCustom(custom)
                    templates = NoteTemplateStore.all()
                    showingEditor = false
                }
                .keyboardShortcut(.defaultAction)
                .disabled(editorName.trimmingCharacters(in: .whitespaces).isEmpty
                          || editorInstructions.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 440)
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

private struct TemplateCard: View {
    let template: NoteTemplate
    let blurb: String
    let selected: Bool
    let voiceEnabled: Bool
    let onSelect: () -> Void
    let onDelete: (() -> Void)?

    @State private var hovering = false

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(template.name)
                        .font(.manrope(12.5, .semibold))
                        .foregroundStyle(selected ? .white : Palette.warmInk)
                    Spacer()
                    if let onDelete {
                        IconButton(icon: .trash, size: 20, iconSize: 11,
                                   tint: selected ? .white.opacity(0.7) : Palette.warmInkSoft,
                                   help: "Delete", action: onDelete)
                            .opacity(hovering ? 1 : 0)
                    }
                }
                if !blurb.isEmpty {
                    Text(blurb)
                        .font(.manrope(11))
                        .foregroundStyle(selected ? .white.opacity(0.7) : Palette.warmInkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 2)
                if !template.voiceTrigger.isEmpty {
                    Text("Say “\(template.voiceTrigger)”")
                        .font(.manrope(10.5))
                        .foregroundStyle(selected ? .white.opacity(0.75) : Palette.sunsetDeep)
                        .opacity(voiceEnabled ? 1 : 0.35)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 78, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: Radius.md)
                    .fill(selected ? Palette.navActivePill : (hovering ? Palette.warmRowBorder : Color.white)))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.md)
                    .stroke(selected ? Color.clear : Palette.warmRowBorder, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(PressScaleButtonStyle(scale: 0.98))
        .onHover { hovering = $0 }
        .animation(.murmurEase(0.12), value: hovering)
    }
}
