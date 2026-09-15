import AppKit
import SwiftUI

// MARK: - Transforms
//
// Redesigned per the "Main" canvas (Transforms.dc.html): same
// `GlassPanelPage` shell as the other redesigned pages, warm palette
// instead of the shared dynamic `Palette`. Functionally unchanged — select
// text anywhere, press a shortcut, rewritten in place; the same two
// transforms are also runnable inline against pasted/typed text here.

struct TransformsPage: View {
    @ObservedObject var app: AppDelegate
    @Binding var page: Page
    @State private var tryText = ""
    @State private var result = ""
    @State private var running = false
    @State private var editorHeight: CGFloat = 90
    @State private var dragBaseHeight: CGFloat = 90

    @State private var customTransforms: [CustomTransform] = CustomTransformStore.load()
    @State private var editingCustomID: UUID?
    @State private var showingEditor = false
    @State private var showingResetConfirm = false
    @State private var draftName = ""
    @State private var draftInstructions = ""

    private let minEditorHeight: CGFloat = 90
    private let maxEditorHeight: CGFloat = 480

    /// Built-ins plus every custom transform, in the exact order/slot
    /// assignment the global ⌥3…9 hotkeys actually use — see
    /// `Transform.merging(_:)`'s own doc comment for why this reads the
    /// page's own `@State` mirror rather than the store directly.
    private var displayTransforms: [Transform] { Transform.merging(customTransforms) }

    var body: some View {
        GlassPanelPage {
            // `ThinScrollView`, not a plain `ScrollView` — see
            // ScratchpadView.swift's own note on why: a bare
            // `.scrollIndicators(.hidden)` doesn't reliably suppress
            // macOS's native scroller by itself.
            ThinScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    header

                    tipBanner("These work in any app, not just Murmur — select text in Mail, "
                              + "Slack, or your editor, press the shortcut, and ⌥⇧Z undoes the "
                              + "last one if it wasn't what you wanted.")
                        .padding(.top, 18)

                    myTransformsHeader
                        .padding(.top, 20)
                    transformGrid
                        .padding(.top, 12)

                    if let note = app.rewriteEngine.availabilityNote {
                        tipBanner(note).padding(.top, 12)
                    }

                    Text("Try it here")
                        .font(.manrope(14, .semibold))
                        .foregroundStyle(Palette.warmInk)
                        .padding(.top, 20)
                    tryItCard
                        .padding(.top, 8)

                    if !result.isEmpty {
                        Text("Result")
                            .font(.manrope(14, .semibold))
                            .foregroundStyle(Palette.warmInk)
                            .padding(.top, 20)
                        resultCard
                            .padding(.top, 8)
                    }

                    relatedLink
                        .padding(.top, 14)
                }
            }
        }
        .onAppear(perform: consumePendingText)
        .onChange(of: app.pendingTransformText) { _, _ in consumePendingText() }
        .sheet(isPresented: $showingEditor) {
            CustomTransformEditor(
                isNew: editingCustomID == nil, name: $draftName, instructions: $draftInstructions,
                onSave: saveDraft)
        }
        .confirmationDialog(
            "Remove all custom transforms?", isPresented: $showingResetConfirm, titleVisibility: .visible
        ) {
            Button("Remove All", role: .destructive, action: resetToDefaults)
        } message: {
            Text("This deletes every transform you've created. Polish and Prompt Engineer aren't affected.")
        }
    }

    /// Picks up a Scratchpad note sent here via "Send to Transforms" —
    /// mirrors `TemplatesView`'s own `consumePendingText`.
    private func consumePendingText() {
        guard let pending = app.pendingTransformText else { return }
        tryText = pending
        result = ""
        app.pendingTransformText = nil
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Transforms")
                .font(.manrope(22, .medium))
                .tracking(-0.33)
                .foregroundStyle(Palette.warmInk)
            Text("Select text anywhere, press a shortcut, rewritten in place.")
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

    private var myTransformsHeader: some View {
        HStack {
            Text("My Transforms")
                .font(.manrope(16, .semibold))
                .foregroundStyle(Palette.warmInk)
            Spacer()
            if !customTransforms.isEmpty {
                Button { showingResetConfirm = true } label: {
                    HStack(spacing: 5) {
                        MurmurIconView(icon: .refresh).frame(width: 11, height: 11)
                        Text("Reset to defaults").font(.manrope(11.5, .medium))
                    }
                    .foregroundStyle(Palette.warmInkSoft)
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// Built-ins first, then every custom transform in slot order, then a
    /// trailing "Create New" tile — matches Wispr Flow's own card grid,
    /// where the built-ins and anything you've added sit as equal-looking
    /// cards rather than the old page's plain shortcut list.
    private var transformGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 14)], spacing: 14) {
            ForEach(displayTransforms) { transform in
                transformCard(transform)
            }
            createCard
        }
    }

    private func transformCard(_ transform: Transform) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Keycap(text: transform.keyLabel,
                       tint: Palette.warmInk, background: Palette.warmRowBorder, borderColor: Palette.warmRowBorder)
                Spacer(minLength: 4)
                if transform.isCustom {
                    IconButton(icon: .edit, size: 22, iconSize: 11, help: "Edit") { beginEdit(transform) }
                    IconButton(icon: .trash, size: 22, iconSize: 11, help: "Delete") { delete(transform) }
                }
            }
            Text(transform.name)
                .font(.manrope(14, .bold))
                .foregroundStyle(Palette.warmInk)
            Text(transform.description)
                .font(.manrope(12))
                .foregroundStyle(Palette.warmInkSoft)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white, in: RoundedRectangle(cornerRadius: Radius.lg))
        .overlay(RoundedRectangle(cornerRadius: Radius.lg).stroke(Palette.warmRowBorder, lineWidth: 1))
    }

    private var createCard: some View {
        Button(action: beginCreate) {
            VStack(alignment: .leading, spacing: 10) {
                MurmurIconView(icon: .plus)
                    .frame(width: 15, height: 15)
                    .foregroundStyle(Palette.warmInkSoft)
                Text("Create New")
                    .font(.manrope(14, .bold))
                    .foregroundStyle(Palette.warmInk)
                Text("Write your own prompt — a custom shortcut you can run from any app.")
                    .font(.manrope(12))
                    .foregroundStyle(Palette.warmInkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Radius.lg)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                    .foregroundStyle(Palette.warmDivider))
            .contentShape(Rectangle())
        }
        .buttonStyle(PressScaleButtonStyle(scale: 0.98))
    }

    // MARK: Custom transform CRUD

    private func customID(from transform: Transform) -> UUID? {
        guard transform.isCustom, transform.id.hasPrefix("custom-") else { return nil }
        return UUID(uuidString: String(transform.id.dropFirst("custom-".count)))
    }

    private func beginCreate() {
        editingCustomID = nil
        draftName = ""
        draftInstructions = ""
        showingEditor = true
    }

    private func beginEdit(_ transform: Transform) {
        guard let id = customID(from: transform),
              let existing = customTransforms.first(where: { $0.id == id })
        else { return }
        editingCustomID = id
        draftName = existing.name
        draftInstructions = existing.instructions
        showingEditor = true
    }

    private func delete(_ transform: Transform) {
        guard let id = customID(from: transform) else { return }
        customTransforms.removeAll { $0.id == id }
        CustomTransformStore.save(customTransforms)
    }

    private func saveDraft() {
        let name = draftName.trimmingCharacters(in: .whitespaces)
        let instructions = draftInstructions.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !instructions.isEmpty else { return }
        if let editingCustomID, let index = customTransforms.firstIndex(where: { $0.id == editingCustomID }) {
            customTransforms[index].name = name
            customTransforms[index].instructions = instructions
        } else {
            customTransforms.append(CustomTransform(name: name, instructions: instructions))
        }
        CustomTransformStore.save(customTransforms)
        editingCustomID = nil
    }

    private func resetToDefaults() {
        customTransforms = []
        CustomTransformStore.save([])
    }

    private var tryItCard: some View {
        VStack(spacing: 0) {
            TextEditor(text: $tryText)
                .font(.manrope(13))
                .foregroundStyle(Palette.warmInk)
                .scrollContentBackground(.hidden)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .frame(height: editorHeight)
                .overlay(alignment: .topLeading) {
                    if tryText.isEmpty {
                        Text("Paste or type some text, then run a transform below…")
                            .font(.manrope(13))
                            .italic()
                            .foregroundStyle(Palette.warmInkFaint)
                            .padding(.horizontal, 19)
                            .padding(.vertical, 20)
                            .allowsHitTesting(false)
                    }
                }
                .overlay(alignment: .bottomTrailing) {
                    // `.transform-tryout textarea { resize: vertical }`
                    // — TextEditor has no native resize grip, so this
                    // rebuilds the same affordance: a corner handle
                    // dragged to grow/shrink just the editor, not the
                    // whole card.
                    ResizeGrip()
                        .frame(width: 14, height: 14)
                        .padding(3)
                        .contentShape(Rectangle())
                        .onHover { inside in
                            if inside { NSCursor.resizeUpDown.push() } else { NSCursor.pop() }
                        }
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { value in
                                    if value.translation == .zero { dragBaseHeight = editorHeight }
                                    editorHeight = min(max(minEditorHeight,
                                                            dragBaseHeight + value.translation.height),
                                                        maxEditorHeight)
                                })
                }
            Rectangle().fill(Palette.warmRowBorder).frame(height: 1)
            // `FlowLayout`, not `LazyVGrid` — a grid's adaptive columns are
            // all the *same* width, which stretched "Prompt Engineer" onto
            // two lines inside a column sized for "Polish" instead of
            // widening the button to fit. Flow gives each button its own
            // natural width and only wraps to a new row once it actually
            // runs out of horizontal room — still handles up to 9 buttons
            // without running off the card's edge.
            VStack(alignment: .leading, spacing: 8) {
                FlowLayout(spacing: 8) {
                    ForEach(displayTransforms) { transform in
                        Button {
                            runTransform(transform)
                        } label: {
                            HStack(spacing: 6) {
                                Text(transform.keyLabel)
                                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                Text(transform.name)
                                    .font(.manrope(12, .semibold))
                                    .lineLimit(1)
                            }
                            // One state, always orange — matching the mockup,
                            // which never depicts a disabled look for these.
                            // `.disabled` below still blocks the tap itself
                            // when there's nothing to run.
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(RoundedRectangle(cornerRadius: Radius.sm).fill(Palette.sunset))
                            .fixedSize()
                        }
                        .buttonStyle(PressScaleButtonStyle())
                        .disabled(!canRun)
                    }
                }
                if running {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small)
                        Text("Running…").font(.manrope(11.5)).foregroundStyle(Palette.warmInkFaint)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
        // Unlike the other cards in this redesign, the mockup gives this
        // one a visible hairline border instead of a shadow — it's a
        // workspace embedded in the flow, not a floating panel.
        .background(Color.white, in: RoundedRectangle(cornerRadius: Radius.md))
        .overlay(RoundedRectangle(cornerRadius: Radius.md).stroke(Palette.warmRowBorder, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: Radius.md))
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
                IconButton(icon: .arrowRight,
                           help: "Paste at cursor in the app behind Murmur") {
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
        // No drop shadow, by request — same call as every other white card
        // floating on the glass panel in this redesign.
        .background(Color.white, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var relatedLink: some View {
        HStack(spacing: 4) {
            Text("Want tone applied automatically as you dictate instead?")
                .font(.manrope(12))
                .foregroundStyle(Palette.warmInkSoft)
            Button { page = .style } label: {
                Text("Style")
                    .font(.manrope(12, .medium))
                    .foregroundStyle(Palette.sunsetDeep)
            }
            .buttonStyle(.plain)
            Text("does it per app, with no shortcut.")
                .font(.manrope(12))
                .foregroundStyle(Palette.warmInkSoft)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private var canRun: Bool {
        !running && !tryText.isEmpty && app.rewriteEngine.isAvailable
    }

    private func runTransform(_ transform: Transform) {
        running = true
        result = ""
        Task {
            defer { running = false }
            do {
                result = try await app.transformManager.apply(transform, to: tryText)
            } catch {
                result = "Failed: \(error.localizedDescription)"
            }
        }
    }
}

/// The diagonal three-line grip browsers draw in the corner of a
/// `resize: vertical` textarea — there's no SwiftUI/AppKit equivalent, so
/// this repaints it by hand.
private struct ResizeGrip: View {
    var body: some View {
        Canvas { context, size in
            var path = Path()
            let inset: CGFloat = 2
            let spacing: CGFloat = 3.5
            for i in 0..<3 {
                let offset = CGFloat(i) * spacing
                path.move(to: CGPoint(x: size.width - inset - offset, y: size.height - inset))
                path.addLine(to: CGPoint(x: size.width - inset, y: size.height - inset - offset))
            }
            context.stroke(path, with: .color(Palette.warmInkFainter), lineWidth: 1.2)
        }
    }
}

/// Lays out its children left-to-right at each one's own natural size,
/// wrapping to a new row only once a child genuinely doesn't fit — unlike
/// `LazyVGrid`'s adaptive columns, which are all forced to the *same*
/// width and were what stretched "Prompt Engineer" onto two lines inside a
/// column sized for "Polish" rather than letting the button itself grow.
private struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var rowWidth: CGFloat = 0
        var totalWidth: CGFloat = 0
        var totalHeight: CGFloat = 0
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if rowWidth > 0, rowWidth + spacing + size.width > maxWidth {
                totalHeight += rowHeight + spacing
                totalWidth = max(totalWidth, rowWidth)
                rowWidth = 0
                rowHeight = 0
            }
            rowWidth += (rowWidth > 0 ? spacing : 0) + size.width
            rowHeight = max(rowHeight, size.height)
        }
        totalHeight += rowHeight
        totalWidth = max(totalWidth, rowWidth)
        return CGSize(width: totalWidth, height: totalHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

/// Create/edit sheet for a custom transform — same shape as
/// `ScratchpadHotkeyEditor`/`NotetakerHotkeyEditor`'s own sheets: a plain
/// card, no page navigation, Done-style dismissal. `onSave` both commits
/// the draft and is responsible for clearing `editingCustomID` on the
/// caller's side; this view only owns the two text fields themselves.
private struct CustomTransformEditor: View {
    @Environment(\.dismiss) private var dismiss
    let isNew: Bool
    @Binding var name: String
    @Binding var instructions: String
    let onSave: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(isNew ? "Create Transform" : "Edit Transform")
                .font(.manrope(16, .semibold))
                .foregroundStyle(Palette.warmInk)
            Text("Write the prompt Murmur should apply to whatever text is selected when "
                 + "you run this — same as Polish or Prompt Engineer, just your own instructions.")
                .font(.manrope(12.5))
                .foregroundStyle(Palette.warmInkFaint)
                .fixedSize(horizontal: false, vertical: true)

            TextField("Name — e.g. \u{201c}Make it punchier\u{201d}", text: $name)
                .textFieldStyle(.plain)
                .font(.manrope(13))
                .foregroundStyle(Palette.warmInk)
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(Palette.warmRowBorder, in: RoundedRectangle(cornerRadius: Radius.md))

            TextEditor(text: $instructions)
                .font(.manrope(13))
                .foregroundStyle(Palette.warmInk)
                .scrollContentBackground(.hidden)
                .padding(8)
                .frame(height: 140)
                .overlay(alignment: .topLeading) {
                    if instructions.isEmpty {
                        Text("What should this transform do to the selected text?")
                            .font(.manrope(13))
                            .italic()
                            .foregroundStyle(Palette.warmInkFaint)
                            .padding(.horizontal, 13)
                            .padding(.vertical, 14)
                            .allowsHitTesting(false)
                    }
                }
                .background(Palette.warmRowBorder, in: RoundedRectangle(cornerRadius: Radius.md))

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .buttonStyle(GhostButtonStyle())
                Button {
                    onSave()
                    dismiss()
                } label: {
                    Text(isNew ? "Create" : "Save")
                        .font(.manrope(12.5, .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Palette.navActivePill, in: RoundedRectangle(cornerRadius: Radius.sm))
                }
                .buttonStyle(.plain)
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty
                          || instructions.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(22)
        .frame(width: 420)
        .environment(\.colorScheme, .light)
    }
}
