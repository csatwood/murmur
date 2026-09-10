import AppKit
import SwiftUI

// MARK: - Scratchpad
//
// Redesigned per the "Main" canvas (Scratchpad.dc.html): same `GlassPanelPage`
// shell as Home/Insights, warm palette instead of the shared dynamic
// `Palette`. Functionally unchanged from the previous pass — this design
// turned the bare text box into a real buffer: live word count, a visible
// autosave confirmation (the page promised "saved automatically" with
// nothing on screen proving it), copy/clear, and a hand-off into
// Transforms instead of a dead end.

struct ScratchpadPage: View {
    @Binding var page: Page
    @State private var text = ""
    @State private var showSaved = false
    @State private var justCopied = false
    @State private var saveTask: Task<Void, Never>?
    /// `resize: vertical` — the design lets you drag the box taller from
    /// its bottom-right corner instead of scrolling a fixed-height field.
    /// Sized a third bigger than the mockup's own 220/620 by request.
    @State private var editorHeight: CGFloat = 293
    @State private var dragStartHeight: CGFloat?
    /// The pointer's own global position when the current drag began — see
    /// `resizeGrip`'s gesture for why this (not `DragGesture`'s default
    /// `.local`-space `translation`) is what the resize is computed from.
    @State private var dragStartLocation: CGPoint?

    private static let minEditorHeight: CGFloat = 293
    private static let maxEditorHeight: CGFloat = 827

    private var fileURL: URL {
        AppPaths.supportDirectory.appendingPathComponent("scratchpad.txt")
    }

    var body: some View {
        GlassPanelPage {
            // A dragged-open editor (up to 620pt) plus header and footer
            // can exceed the glass panel's own height on a small window —
            // `GlassPanelPage` doesn't scroll its content for you (that's
            // the point of `managesOwnScrolling`: each page decides for
            // itself), so this supplies its own. `ThinScrollView`, not a
            // plain `ScrollView` — the app's own established way to get a
            // scrollable area with no visible scrollbar at all (a bare
            // `.scrollIndicators(.hidden)` doesn't reliably suppress
            // macOS's native scroller on its own; see `ThinScrollView`'s
            // own comment).
            ThinScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    header
                    editorCard
                        .padding(.top, 22)
                }
            }
        }
        .onAppear {
            text = (try? String(contentsOf: fileURL, encoding: .utf8)) ?? ""
        }
        .onChange(of: text) { _, newValue in
            try? newValue.write(to: fileURL, atomically: true, encoding: .utf8)
            showSaved = true
            saveTask?.cancel()
            saveTask = Task {
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                if !Task.isCancelled { showSaved = false }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Scratchpad")
                .font(.manrope(22, .medium))
                .tracking(-0.33)
                .foregroundStyle(Palette.warmInk)
            Text("A place to park text — saved automatically.")
                .font(.manrope(12.5))
                .foregroundStyle(Palette.warmInkFaint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var editorCard: some View {
        VStack(spacing: 0) {
            TextEditor(text: $text)
                .font(.manrope(14))
                .lineSpacing(3.5)
                .foregroundStyle(Palette.warmInk)
                .scrollContentBackground(.hidden)
                .padding(.horizontal, 22)
                .padding(.vertical, 20)
                .frame(height: editorHeight)
                .overlay(alignment: .topLeading) {
                    if text.isEmpty {
                        Text("Start typing or dictate…")
                            .font(.manrope(14))
                            .italic()
                            .foregroundStyle(Palette.warmInkFaint)
                            .padding(.horizontal, 27)
                            .padding(.vertical, 28)
                            .allowsHitTesting(false)
                    }
                }
                .overlay(alignment: .bottomTrailing) {
                    resizeGrip
                }

            Rectangle().fill(Palette.warmRowBorder).frame(height: 1)

            HStack(spacing: 14) {
                Text("\(wordCount) \(wordCount == 1 ? "word" : "words")")
                    .font(.manrope(12))
                    .foregroundStyle(Palette.warmInkSoft)
                HStack(spacing: 6) {
                    Circle().fill(Palette.sunset).frame(width: 5, height: 5)
                    Text("Saved").font(.manrope(12)).foregroundStyle(Palette.warmInkSoft)
                }
                .opacity(showSaved ? 1 : 0)
                .animation(.easeOut(duration: 0.2), value: showSaved)

                Spacer()

                IconButton(icon: justCopied ? .check : .copy,
                           tint: justCopied ? Palette.sunset : nil,
                           help: "Copy") {
                    let pb = NSPasteboard.general
                    pb.clearContents()
                    pb.setString(text, forType: .string)
                    justCopied = true
                    Task {
                        try? await Task.sleep(nanoseconds: 1_200_000_000)
                        justCopied = false
                    }
                }
                IconButton(icon: .trash, help: "Clear") { text = "" }
                Button {
                    page = .transforms
                } label: {
                    HStack(spacing: 5) {
                        MurmurIconView(icon: .trans).frame(width: 12, height: 12)
                        Text("Send to Transforms").font(.manrope(12, .medium))
                        MurmurIconView(icon: .arrowRight).frame(width: 11, height: 11)
                    }
                    .foregroundStyle(Palette.sunsetDeep)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 7)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
        }
        // No drop shadow, by request — it showed up as an odd smear along
        // the bottom edge of the card sitting on the frosted glass panel.
        .background(Color.white, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    /// The corner grip a `resize: vertical` textarea gets for free in a
    /// browser: three hairline diagonals, drag to change the box height.
    private var resizeGrip: some View {
        ResizeGripShape()
            .stroke(Palette.warmInkFainter, style: StrokeStyle(lineWidth: 1, lineCap: .round))
            .frame(width: 11, height: 11)
            .padding(6)
            .contentShape(Rectangle())
            // `.highPriorityGesture`, not `.gesture` — the editor card now
            // sits inside `body`'s own `ScrollView` (added so a dragged-
            // open editor can exceed the glass panel's height), and a
            // plain `.gesture` here left the scroll view's own drag-to-pan
            // recognizer free to compete with this one, reading as
            // stutter: the resize would occasionally stall or the whole
            // page would try to scroll a pixel mid-drag instead of just
            // resizing. Grabbing priority means a drag starting on the
            // grip is unambiguously a resize, never a scroll, so it
            // tracks the cursor 1:1 with nothing to fight.
            //
            // `.global` coordinate space, with the delta computed by hand
            // from `value.location`/`dragStartLocation` — not the default
            // `.local` space's own `value.translation`. This grip is an
            // `.overlay` bottom-anchored to the very box its drag is
            // resizing, so its *local* coordinate space is itself moving
            // throughout the gesture — `.local` translation is reported
            // relative to a frame that the gesture's own output is
            // simultaneously repositioning, a feedback loop that compounds
            // the longer the drag is held instead of settling, which is
            // exactly the flicker this was chased as. Global coordinates
            // are anchored to the window, not to this shifting view, so
            // the same drag no longer feeds back into its own reference
            // frame.
            .highPriorityGesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .global)
                    .onChanged { value in
                        if dragStartLocation == nil {
                            dragStartLocation = value.startLocation
                            dragStartHeight = editorHeight
                        }
                        let startY = dragStartLocation?.y ?? value.startLocation.y
                        let start = dragStartHeight ?? editorHeight
                        editorHeight = min(
                            Self.maxEditorHeight,
                            max(Self.minEditorHeight, start + (value.location.y - startY)))
                    }
                    .onEnded { value in
                        let startY = dragStartLocation?.y ?? value.startLocation.y
                        let start = dragStartHeight ?? editorHeight
                        editorHeight = min(
                            Self.maxEditorHeight,
                            max(Self.minEditorHeight, start + (value.location.y - startY)))
                        dragStartLocation = nil
                        dragStartHeight = nil
                    })
            .onHover { inside in
                if inside { NSCursor.resizeUpDown.push() } else { NSCursor.pop() }
            }
            .help("Drag to resize")
    }

    private var wordCount: Int {
        text.split(whereSeparator: { $0.isWhitespace }).count
    }
}

/// The three stacked diagonals of a browser textarea's resize corner.
private struct ResizeGripShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        for inset in stride(from: 0.0, through: rect.width, by: rect.width / 2.5) {
            path.move(to: CGPoint(x: rect.maxX - inset, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - inset))
        }
        return path
    }
}
