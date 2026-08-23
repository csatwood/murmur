import AppKit
import SwiftUI

// MARK: - Transforms

struct TransformsPage: View {
    @ObservedObject var app: AppDelegate
    @Binding var page: Page
    @State private var tryText = ""
    @State private var result = ""
    @State private var running = false
    @State private var editorHeight: CGFloat = 90
    @State private var dragBaseHeight: CGFloat = 90

    private let minEditorHeight: CGFloat = 90
    private let maxEditorHeight: CGFloat = 480

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PageHeader(
                title: "Transforms",
                subtitle: "Select text anywhere, press a shortcut, rewritten in place.")

            PageTip(text: "These work in any app, not just Murmur — select text in Mail, Slack, "
                    + "or your editor and press the shortcut.")
                .padding(.bottom, 16)

            Card(flat: true) {
                ForEach(Transform.all) { transform in
                    ShortcutRow(key: transform.keyLabel,
                                text: "\(transform.name) — \(transform.description)")
                    if transform.id != Transform.all.last?.id {
                        Rectangle().fill(Palette.border).frame(height: 1)
                    }
                }
            }

            if let note = app.rewriteEngine.availabilityNote {
                PageTip(text: note).padding(.top, 12)
            }

            SectionHead(title: "Try it here")
            VStack(spacing: 0) {
                TextEditor(text: $tryText)
                    .font(.manrope(13))
                    .scrollContentBackground(.hidden)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .frame(height: editorHeight)
                    .overlay(alignment: .topLeading) {
                        if tryText.isEmpty {
                            Text("Paste or type some text, then run a transform below…")
                                .font(.manrope(13))
                                .italic()
                                .foregroundStyle(Palette.inkFaint)
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
                Rectangle().fill(Palette.border).frame(height: 1)
                HStack(spacing: 8) {
                    ForEach(Transform.all) { transform in
                        Button {
                            runTransform(transform)
                        } label: {
                            HStack(spacing: 6) {
                                Text(transform.keyLabel)
                                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                Text(transform.name).font(.manrope(12, .semibold))
                            }
                            .foregroundStyle(canRun ? Palette.accentInk : Palette.inkFaint)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(
                                RoundedRectangle(cornerRadius: Radius.sm)
                                    .fill(canRun ? Palette.accent : Palette.cardHover))
                        }
                        .buttonStyle(PressScaleButtonStyle())
                        .disabled(!canRun)
                    }
                    if running { ProgressView().controlSize(.small) }
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            }
            .background(Palette.panel, in: RoundedRectangle(cornerRadius: Radius.md))
            .overlay(RoundedRectangle(cornerRadius: Radius.md).stroke(Palette.border, lineWidth: 1))

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
                        IconButton(icon: .arrowRight,
                                   help: "Paste at cursor in the app behind Murmur") {
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
                prefix: "Want tone applied automatically as you dictate instead?",
                linkTitle: "Style",
                suffix: "does it per app, with no shortcut."
            ) { page = .style }
        }
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
            context.stroke(path, with: .color(Palette.inkFaint), lineWidth: 1.2)
        }
    }
}
