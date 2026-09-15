import AppKit
import SwiftUI

// MARK: - Scratchpad
//
// Rebuilt to match what Wispr Flow's own Scratchpad actually is (confirmed
// by opening it directly, not going off the name): a fast, location-
// independent quick-capture tool, not one more page holding one more
// text box. The real editing surface is `ScratchpadPanelController`'s
// floating panel — summonable with Control+Shift+Space from anywhere,
// no need to even have Murmur's window open. This page is what Wispr
// Flow's own main-window Scratchpad screen is: a hero explaining the
// idea plus "Start new note", and "Recents" — every note, searchable,
// click one to reopen it in the floating panel.
//
// The previous version's single autosaving buffer (`scratchpad.txt`) is
// migrated into this store's first note on first launch — see
// `ScratchpadStore`'s own note on that.

struct ScratchpadPage: View {
    @ObservedObject var app: AppDelegate
    @State private var searchOpen = false
    @State private var searchText = ""
    @State private var showingHotkeyEditor = false
    // `Settings.scratchpadHotkey*` is plain `UserDefaults`, not
    // `@Published` — mirrored here so the chip actually re-renders once
    // the editor sheet saves a rebind, instead of silently going stale
    // until this page happens to reload some other way.
    @State private var hotkeyKeyCode = Settings.scratchpadHotkeyKeyCode
    @State private var hotkeyModifiers = Settings.scratchpadHotkeyModifiers

    var body: some View {
        GlassPanelPage {
            ThinScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    header
                    hero.padding(.top, 20)
                    notesHeader.padding(.top, 28)
                    notesList.padding(.top, 10)
                }
            }
        }
        .sheet(isPresented: $showingHotkeyEditor, onDismiss: {
            hotkeyKeyCode = Settings.scratchpadHotkeyKeyCode
            hotkeyModifiers = Settings.scratchpadHotkeyModifiers
        }) { ScratchpadHotkeyEditor() }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Scratchpad")
                    .font(.manrope(22, .medium))
                    .tracking(-0.33)
                    .foregroundStyle(Palette.warmInk)
                Text("A fast place to park a thought — dictate or type it, come back and develop it later.")
                    .font(.manrope(12.5))
                    .foregroundStyle(Palette.warmInkFaint)
            }
            Spacer(minLength: 12)
            shortcutChip
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The panel's hotkey, shown so it's discoverable from the page it
    /// belongs to — matching where Wispr Flow's own Scratchpad surfaces its
    /// shortcut. Click opens `ScratchpadHotkeyEditor` to rebind it, same as
    /// Wispr Flow's own "Click to enable shortcut".
    private var shortcutChip: some View {
        Button { showingHotkeyEditor = true } label: {
            HStack(spacing: 8) {
                Text("Open from anywhere")
                    .font(.manrope(11.5))
                    .foregroundStyle(Palette.warmInkFaint)
                HStack(spacing: 3) {
                    ForEach(KeyComboLabel.symbols(for: hotkeyModifiers), id: \.self) { symbol in
                        keycap(symbol)
                    }
                    keycap(KeyComboLabel.keyName(for: hotkeyKeyCode))
                }
                MurmurIconView(icon: .edit)
                    .frame(width: 10, height: 10)
                    .foregroundStyle(Palette.warmInkFaint)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Palette.warmRowBorder, in: RoundedRectangle(cornerRadius: Radius.md))
        }
        .buttonStyle(.plain)
    }

    private func keycap(_ label: String) -> some View {
        Text(label)
            .font(.manrope(11, .semibold))
            .foregroundStyle(Palette.warmInk)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 5))
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("For quick thoughts you want to come back to")
                .font(.manrope(19, .medium))
                .tracking(-0.2)
                .foregroundStyle(.white)
            Text("Drop a to-do list, polish a message before you send it, brain dump an idea. "
                 + "Hold \(app.hotkey.displayName) to dictate straight into it — no need to have "
                 + "Murmur's window open at all.")
                .font(.manrope(12.5))
                .foregroundStyle(.white.opacity(0.85))
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 460, alignment: .leading)
            Button {
                app.openScratchpadPanel(noteID: app.scratchpadStore.createNote().id)
            } label: {
                Text("Start new note")
                    .font(.manrope(12.5, .semibold))
                    .foregroundStyle(Palette.warmInk)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 9)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: Radius.md))
            }
            .buttonStyle(PressScaleButtonStyle(scale: 0.97))
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        // Flat, not the gradient Home/Insights use for their own hero
        // cards, by request — just `sunset`, the gradient's own darker
        // stop, as a solid fill.
        .background(Palette.sunset, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    /// Search / new-note / refresh — matches Wispr Flow's own "Recents"
    /// row exactly, reusing icons already in the app's own set rather than
    /// adding new ones. Search is a toggle, not an always-open field, the
    /// same pattern (and the same icon swap) as Home's own history search.
    private var notesHeader: some View {
        HStack(spacing: 8) {
            Text("Recents")
                .font(.manrope(13, .semibold))
                .foregroundStyle(Palette.warmInk)
            Spacer()
            if searchOpen {
                HStack(spacing: 8) {
                    MurmurIconView(icon: .search)
                        .frame(width: 12, height: 12)
                        .foregroundStyle(Palette.warmInkFaint)
                    TextField("Search notes", text: $searchText)
                        .textFieldStyle(.plain)
                        .font(.manrope(12.5))
                        .foregroundStyle(Palette.warmInk)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Palette.warmRowBorder, in: RoundedRectangle(cornerRadius: Radius.sm))
                .frame(width: 200)
            }
            IconButton(icon: searchOpen ? .plus : .search,
                       rotated: searchOpen,
                       help: searchOpen ? "Close search" : "Search notes") {
                searchOpen.toggle()
                if !searchOpen { searchText = "" }
            }
            IconButton(icon: .plus, help: "New note") {
                app.openScratchpadPanel(noteID: app.scratchpadStore.createNote().id)
            }
            IconButton(icon: .refresh, help: "Refresh") {
                app.scratchpadStore.reload()
            }
        }
    }

    private var filteredNotes: [ScratchpadNote] {
        ScratchpadStore.matching(searchText, in: app.scratchpadStore.notesByRecency)
    }

    private var notesList: some View {
        Group {
            if app.scratchpadStore.notes.isEmpty {
                emptyState("No notes yet — click \u{201c}Start new note\u{201d} above, "
                           + "or press \u{2303}\u{21e7}Space from anywhere.")
            } else if filteredNotes.isEmpty {
                emptyState("No notes match \u{201c}\(searchText)\u{201d}.")
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(filteredNotes.enumerated()), id: \.element.id) { index, note in
                        ScratchpadNoteRow(
                            note: note,
                            onOpen: { app.openScratchpadPanel(noteID: note.id) },
                            onDelete: { app.scratchpadStore.delete(id: note.id) })
                        if index != filteredNotes.count - 1 {
                            Rectangle().fill(Palette.warmRowBorder).frame(height: 1)
                                .padding(.horizontal, 16)
                        }
                    }
                }
                .background(Color.white, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            }
        }
    }

    private func emptyState(_ text: String) -> some View {
        Text(text)
            .font(.manrope(12.5))
            .italic()
            .foregroundStyle(Palette.warmInkFaint)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 28)
            .background(Palette.warmRowBorder, in: RoundedRectangle(cornerRadius: Radius.lg))
    }
}

private struct ScratchpadNoteRow: View {
    let note: ScratchpadNote
    let onOpen: () -> Void
    let onDelete: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: onOpen) {
            HStack(alignment: .top, spacing: 13) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(note.title)
                        .font(.manrope(13, .semibold))
                        .foregroundStyle(Palette.warmInk)
                        .lineLimit(1)
                    Text(note.isEmpty ? "Empty note" : note.text.replacingOccurrences(of: "\n", with: " "))
                        .font(.manrope(12))
                        .foregroundStyle(Palette.warmInkSoft)
                        .lineLimit(1)
                }
                Spacer(minLength: 10)
                Text(note.updatedAt, format: .relative(presentation: .named))
                    .font(.manrope(11.5))
                    .foregroundStyle(Palette.warmInkFaint)
                    .frame(width: 76, alignment: .trailing)
                IconButton(icon: .trash, size: 24, iconSize: 12, help: "Delete", action: onDelete)
                    .opacity(hovering ? 1 : 0)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 13)
            .background(hovering ? Palette.cardHover : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}
