import AppKit
import SwiftUI

// MARK: - Scratchpad
//
// The design turned the bare text box into a real buffer: live word count,
// a visible autosave confirmation (the page promised "saved automatically"
// with nothing on screen proving it), copy/clear, and a hand-off into
// Transforms instead of a dead end.

struct ScratchpadPage: View {
    @Binding var page: Page
    @State private var text = ""
    @State private var showSaved = false
    @State private var justCopied = false
    @State private var saveTask: Task<Void, Never>?
    /// `resize: vertical` — the design lets you drag the box taller from
    /// its bottom-right corner instead of scrolling a fixed-height field.
    @State private var editorHeight: CGFloat = 220
    @State private var dragStartHeight: CGFloat?

    private static let minEditorHeight: CGFloat = 220
    private static let maxEditorHeight: CGFloat = 620

    private var fileURL: URL {
        AppPaths.supportDirectory.appendingPathComponent("scratchpad.txt")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PageHeader(
                title: "Scratchpad",
                subtitle: "A place to park text — saved automatically.")

            VStack(spacing: 0) {
                TextEditor(text: $text)
                    .font(.manrope(14))
                    .lineSpacing(3.5)
                    .scrollContentBackground(.hidden)
                    .padding(.horizontal, 22)
                    .padding(.vertical, 20)
                    .frame(height: editorHeight)
                    .overlay(alignment: .topLeading) {
                        if text.isEmpty {
                            Text("Start typing or dictate…")
                                .font(.manrope(14))
                                .italic()
                                .foregroundStyle(Palette.inkFaint)
                                .padding(.horizontal, 27)
                                .padding(.vertical, 28)
                                .allowsHitTesting(false)
                        }
                    }
                    .overlay(alignment: .bottomTrailing) {
                        resizeGrip
                    }

                Rectangle().fill(Palette.border).frame(height: 1)

                HStack(spacing: 14) {
                    Text("\(wordCount) \(wordCount == 1 ? "word" : "words")")
                        .font(.manrope(12))
                        .foregroundStyle(Palette.inkSoft)
                    HStack(spacing: 6) {
                        Circle().fill(Palette.chartMark).frame(width: 5, height: 5)
                        Text("Saved").font(.manrope(12)).foregroundStyle(Palette.inkSoft)
                    }
                    .opacity(showSaved ? 1 : 0)
                    .animation(.easeOut(duration: 0.2), value: showSaved)

                    Spacer()

                    IconButton(icon: justCopied ? .check : .copy,
                               tint: justCopied ? Palette.chartMark : nil,
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
                        .foregroundStyle(Palette.accentText)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 7)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
            }
            .background(Palette.card, in: RoundedRectangle(cornerRadius: Radius.lg))
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

    /// The corner grip a `resize: vertical` textarea gets for free in a
    /// browser: three hairline diagonals, drag to change the box height.
    private var resizeGrip: some View {
        ResizeGripShape()
            .stroke(Palette.inkFaint, style: StrokeStyle(lineWidth: 1, lineCap: .round))
            .frame(width: 11, height: 11)
            .padding(6)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let start = dragStartHeight ?? editorHeight
                        if dragStartHeight == nil { dragStartHeight = start }
                        editorHeight = min(
                            Self.maxEditorHeight,
                            max(Self.minEditorHeight, start + value.translation.height))
                    }
                    .onEnded { _ in dragStartHeight = nil })
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
