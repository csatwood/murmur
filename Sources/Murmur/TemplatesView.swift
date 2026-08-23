import AppKit
import SwiftUI

// MARK: - Templates
//
// Card grid per the design, each card showing what the template actually
// produces plus its spoken trigger, with the voice toggle, per-app
// auto-activation rules, and the transcript workspace all on one page.

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
        VStack(alignment: .leading, spacing: 0) {
            PageHeader(
                title: "Templates",
                subtitle: "Restructure a transcript — say the trigger, get the shape, no clicking.")

            PageTip(text: "Say the trigger phrase first, then keep talking — Murmur strips it "
                    + "off and reshapes everything that follows.")
                .padding(.bottom, 12)

            Card(flat: true) {
                FieldRow(
                    label: "Apply by voice",
                    detail: "Say a template's trigger phrase to reshape a dictation automatically",
                    isLast: true
                ) {
                    MurmurToggle(isOn: $voiceTemplatesEnabled)
                        .onChange(of: voiceTemplatesEnabled) { _, newValue in
                            Settings.voiceTemplatesEnabled = newValue
                        }
                }
            }
            .padding(.bottom, 16)

            if let note = app.rewriteEngine.availabilityNote {
                PageTip(text: note).padding(.bottom, 12)
            }

            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(templates) { template in
                    templateCard(template)
                }
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
                    .foregroundStyle(Palette.inkSoft)
                    .frame(maxWidth: .infinity, minHeight: 78)
                    .background(
                        RoundedRectangle(cornerRadius: Radius.md)
                            .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                            .foregroundStyle(Palette.border))
                    .contentShape(Rectangle())
                }
                .buttonStyle(PressScaleButtonStyle(scale: 0.98))
            }

            // Workspace
            SectionHead(title: "Transcript")
            Card {
                TextEditor(text: $inputText)
                    .font(.manrope(13))
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 110)
                    .overlay(alignment: .topLeading) {
                        if inputText.isEmpty {
                            Text("Paste or dictate a transcript, or send one in from History…")
                                .font(.manrope(13))
                                .italic()
                                .foregroundStyle(Palette.inkFaint)
                                .padding(.top, 8)
                                .padding(.leading, 5)
                                .allowsHitTesting(false)
                        }
                    }
                HStack(spacing: 10) {
                    Button {
                        generate()
                    } label: {
                        HStack(spacing: 7) {
                            if running {
                                ProgressView().controlSize(.small)
                            } else {
                                MurmurIconView(icon: .trans).frame(width: 13, height: 13)
                            }
                            Text(running ? "Generating…" : "Generate")
                                .font(.manrope(12.5, .semibold))
                        }
                        .foregroundStyle(canGenerate ? Palette.accentInk : Palette.inkFaint)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 9)
                        .background(
                            RoundedRectangle(cornerRadius: Radius.sm)
                                .fill(canGenerate ? Palette.accent : Palette.cardHover))
                    }
                    .buttonStyle(PressScaleButtonStyle())
                    .disabled(!canGenerate)

                    if selectedTemplateID == nil {
                        Text("Pick a shape above first")
                            .font(.manrope(11.5))
                            .foregroundStyle(Palette.inkFaint)
                    }
                    Spacer()
                    if !inputText.isEmpty {
                        Button("Clear") { inputText = ""; result = "" }
                            .buttonStyle(GhostButtonStyle())
                    }
                }
                .padding(.top, 12)
            }

            if !result.isEmpty {
                SectionHead(title: "Result")
                Card {
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
                        .foregroundStyle(Palette.ink)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            RelatedLink(
                prefix: "Want a template applied automatically in one app?",
                linkTitle: "App Profiles",
                suffix: "set it there, no trigger phrase needed."
            ) { page = .appProfiles }
        }
        .onAppear(perform: consumePendingText)
        .onChange(of: app.pendingTemplateText) { _, _ in consumePendingText() }
        .sheet(isPresented: $showingEditor) { templateEditor }
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
                        .foregroundStyle(selected ? Palette.onInk : Palette.ink)
                    Spacer()
                    if let onDelete {
                        IconButton(icon: .trash, size: 20, iconSize: 11,
                                   tint: selected ? Palette.onInk.opacity(0.7) : Palette.inkSoft,
                                   help: "Delete", action: onDelete)
                            .opacity(hovering ? 1 : 0)
                    }
                }
                if !blurb.isEmpty {
                    Text(blurb)
                        .font(.manrope(11))
                        .foregroundStyle(selected ? Palette.onInk.opacity(0.7) : Palette.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 2)
                if !template.voiceTrigger.isEmpty {
                    Text("Say “\(template.voiceTrigger)”")
                        .font(.manrope(10.5))
                        .foregroundStyle(selected ? Palette.onInk.opacity(0.75) : Palette.accentText)
                        .opacity(voiceEnabled ? 1 : 0.35)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 78, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: Radius.md)
                    .fill(selected ? Palette.ink : (hovering ? Palette.cardHover : Palette.panel)))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.md)
                    .stroke(selected ? Color.clear : Palette.border, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(PressScaleButtonStyle(scale: 0.98))
        .onHover { hovering = $0 }
        .animation(.murmurEase(0.12), value: hovering)
    }
}
