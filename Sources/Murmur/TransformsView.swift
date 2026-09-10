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

    private let minEditorHeight: CGFloat = 90
    private let maxEditorHeight: CGFloat = 480

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
                              + "Slack, or your editor and press the shortcut.")
                        .padding(.top, 18)

                    shortcutList
                        .padding(.top, 16)

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

    /// A bare flat list directly on the glass panel — no card — matching
    /// the mockup's own treatment of the two global shortcuts.
    private var shortcutList: some View {
        VStack(spacing: 0) {
            ForEach(Transform.all) { transform in
                HStack(alignment: .top, spacing: 10) {
                    Keycap(text: transform.keyLabel,
                           tint: Palette.warmInk, background: .white, borderColor: Palette.warmRowBorder)
                    (Text(transform.name).font(.manrope(13, .bold))
                     + Text(" — \(transform.description)").font(.manrope(13)))
                        .foregroundStyle(Palette.warmInk)
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 8)
                if transform.id != Transform.all.last?.id {
                    Rectangle().fill(Palette.warmRowBorder).frame(height: 1)
                }
            }
        }
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
                        // One state, always orange — matching the mockup,
                        // which never depicts a disabled look for these.
                        // `.disabled` below still blocks the tap itself
                        // when there's nothing to run.
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(RoundedRectangle(cornerRadius: Radius.sm).fill(Palette.sunset))
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
