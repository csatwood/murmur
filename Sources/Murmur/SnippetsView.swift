import SwiftUI

// MARK: - Snippets
//
// Redesigned per the "Main" canvas (Snippets.dc.html): same `GlassPanelPage`
// shell as Dictionary, warm palette instead of the shared dynamic
// `Palette`. Functionally unchanged — searchable list with a live count
// and inline add/edit/delete.
//
// The tip banner, search field, add-row button, and related-link row are
// bespoke to this page rather than the shared `PageTip`/`SearchField`/
// `AddRowButton`/`RelatedLink` components, matching Dictionary's own
// reasoning: those are still tuned for the old dynamic/lime palette and
// shared with pages that haven't been redesigned yet.

struct SnippetsPage: View {
    @Binding var page: Page
    @State private var snippets: [Snippet] = []
    @State private var searchText = ""
    @State private var editingID: UUID?
    @State private var draftTrigger = ""
    @State private var draftExpansion = ""
    @State private var addingNew = false

    var body: some View {
        GlassPanelPage {
            // `ThinScrollView`, not a plain `ScrollView` — see
            // ScratchpadView.swift's own note on why: a bare
            // `.scrollIndicators(.hidden)` doesn't reliably suppress
            // macOS's native scroller by itself.
            ThinScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    header
                    hero
                        .padding(.top, 18)
                    tipBanner
                        .padding(.top, 16)
                    searchBar
                        .padding(.top, 16)
                    listCard
                        .padding(.top, 14)

                    if addingNew {
                        snippetEditRow(onSave: commitNew, onCancel: { addingNew = false })
                            .padding(.top, 10)
                    } else {
                        addRowButton
                            .padding(.top, 10)
                    }

                    relatedLink
                        .padding(.top, 14)
                }
            }
        }
        .onAppear { snippets = SnippetStore.load() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Snippets")
                .font(.manrope(22, .medium))
                .tracking(-0.33)
                .foregroundStyle(Palette.warmInk)
            Text("Say a trigger phrase, get a saved block pasted instead.")
                .font(.manrope(12.5))
                .foregroundStyle(Palette.warmInkFaint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Teaches by example rather than by the tip banner's one sentence
    /// alone — a new user staring at an empty list has no real sense of
    /// what's worth saving. Three deliberately different use cases, not
    /// three variations on "an address": a link, a reusable AI-prompt
    /// opener (the one genuinely non-obvious idea — a snippet doesn't have
    /// to be a fact, it can be an instruction you say before dictating
    /// into Ask Murmur or any other AI chat), and a boilerplate template.
    /// Solid `sunset` fill, no shadow — same call as Scratchpad's own hero,
    /// the closer sibling to this "explain a tool, then list what it's
    /// made" page than Notetaker's own (which does carry a shadow).
    private var hero: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Say it once, never type it again")
                .font(.manrope(19, .medium))
                .tracking(-0.2)
                .foregroundStyle(.white)
            Text("Save an address, a canned reply, even a reusable AI prompt — say the "
                 + "trigger phrase mid-dictation and Murmur drops in the full text.")
                .font(.manrope(12.5))
                .foregroundStyle(.white.opacity(0.85))
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 460, alignment: .leading)
            // A real saved snippet's row (`SnippetRow`, below) uses this
            // exact same chip-pair shape — without this label, nothing
            // told the two apart, and these three read as if they were
            // already active rather than illustrative. None of them do
            // anything until you've actually created a snippet with that
            // trigger yourself.
            Text("TRY SOMETHING LIKE")
                .font(.manrope(10, .bold))
                .kerning(0.8)
                .foregroundStyle(.white.opacity(0.6))
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 8) {
                exampleRow(trigger: "my calendly", expansion: "https://calendly.com/yourname/30min")
                exampleRow(trigger: "tighten this up",
                           expansion: "Rewrite the following to be more concise and direct:")
                exampleRow(trigger: "standup update",
                           expansion: "Yesterday I worked on ___. Today: ___. No blockers.")
            }
            .padding(.top, 2)
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.sunset, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private func exampleRow(trigger: String, expansion: String) -> some View {
        HStack(spacing: 8) {
            Text(trigger)
                .font(.manrope(11.5, .semibold))
                .foregroundStyle(Palette.warmInk)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 7))
            MurmurIconView(icon: .arrowRight)
                .frame(width: 10, height: 10)
                .foregroundStyle(.white.opacity(0.6))
            Text(expansion)
                .font(.manrope(11.5))
                .foregroundStyle(.white)
                .lineLimit(1)
                .truncationMode(.tail)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.white.opacity(0.16), in: RoundedRectangle(cornerRadius: 7))
                .frame(maxWidth: 320, alignment: .leading)
        }
    }

    private var tipBanner: some View {
        HStack(alignment: .top, spacing: 8) {
            MurmurIconView(icon: .help)
                .frame(width: 13, height: 13)
                .foregroundStyle(Palette.warmInkSoft)
                .padding(.top, 1)
            Text("Say the trigger phrase exactly, ideally as its own pause — snippets "
                 + "don't fuzzy-match like Dictionary does, so Murmur only expands it when "
                 + "it hears the whole phrase.")
                .font(.manrope(12.5))
                .lineSpacing(3)
                .foregroundStyle(Palette.warmInkSoft)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var searchBar: some View {
        HStack {
            HStack(spacing: 8) {
                MurmurIconView(icon: .search)
                    .frame(width: 13, height: 13)
                    .foregroundStyle(Palette.warmInkFaint)
                TextField("Search snippets…", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.manrope(12.5))
                    .foregroundStyle(Palette.warmInk)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Color.white, in: RoundedRectangle(cornerRadius: Radius.sm))
            .overlay(RoundedRectangle(cornerRadius: Radius.sm).stroke(Palette.warmRowBorder, lineWidth: 1))
            .frame(width: 260)
            Spacer()
            Text(countLabel)
                .font(.manrope(11.5))
                .foregroundStyle(Palette.warmInkFaint)
        }
    }

    private var listCard: some View {
        Group {
            if visible.isEmpty {
                Text(snippets.isEmpty
                     ? "No snippets yet — add signatures, addresses, or canned replies."
                     : "No matches.")
                    .font(.manrope(12.5))
                    .italic()
                    .foregroundStyle(Palette.warmInkFaint)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(visible.enumerated()), id: \.element.id) { index, snippet in
                        if editingID == snippet.id {
                            snippetEditRow(onSave: { commitEdit(snippet) },
                                           onCancel: { editingID = nil })
                        } else {
                            SnippetRow(
                                snippet: snippet,
                                onEdit: {
                                    draftTrigger = snippet.trigger
                                    draftExpansion = snippet.expansion
                                    editingID = snippet.id
                                },
                                onDelete: {
                                    snippets.removeAll { $0.id == snippet.id }
                                    save()
                                })
                        }
                        if index != visible.count - 1 {
                            Rectangle().fill(Palette.warmRowBorder).frame(height: 1)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 2)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            }
        }
    }

    private func snippetEditRow(onSave: @escaping () -> Void, onCancel: @escaping () -> Void) -> some View {
        HStack(alignment: .top, spacing: 8) {
            TextField("Say this…", text: $draftTrigger)
                .textFieldStyle(.plain)
                .font(.manrope(12.5))
                .foregroundStyle(Palette.warmInk)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(Palette.warmRowBorder, in: RoundedRectangle(cornerRadius: Radius.sm))
                .overlay(RoundedRectangle(cornerRadius: Radius.sm).stroke(Palette.warmDivider, lineWidth: 1))
                .frame(width: 140)
            Text("→").foregroundStyle(Palette.warmInkFaint).padding(.top, 8)
            TextEditor(text: $draftExpansion)
                .font(.manrope(12.5))
                .foregroundStyle(Palette.warmInk)
                .scrollContentBackground(.hidden)
                .padding(6)
                .frame(minHeight: 60)
                .background(Palette.warmRowBorder, in: RoundedRectangle(cornerRadius: Radius.sm))
                .overlay(RoundedRectangle(cornerRadius: Radius.sm).stroke(Palette.warmDivider, lineWidth: 1))
            IconButton(icon: .check, help: "Save", action: onSave).padding(.top, 2)
            IconButton(icon: .plus, rotated: true, help: "Cancel", action: onCancel).padding(.top, 2)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 9)
    }

    private var addRowButton: some View {
        Button {
            draftTrigger = ""
            draftExpansion = ""
            addingNew = true
        } label: {
            HStack(spacing: 8) {
                MurmurIconView(icon: .plus).frame(width: 13, height: 13)
                Text("Add snippet").font(.manrope(12.5, .semibold))
            }
            .foregroundStyle(Palette.warmInkSoft)
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Radius.sm)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                    .foregroundStyle(Palette.warmDivider))
            .contentShape(Rectangle())
        }
        .buttonStyle(PressScaleButtonStyle(scale: 0.98))
    }

    private var relatedLink: some View {
        HStack(spacing: 4) {
            Text("Need to reshape what you just said, not insert fixed text?")
                .font(.manrope(12))
                .foregroundStyle(Palette.warmInkSoft)
            Button { page = .templates } label: {
                Text("Templates")
                    .font(.manrope(12, .medium))
                    .foregroundStyle(Palette.sunsetDeep)
            }
            .buttonStyle(.plain)
            Text("restructure the transcript itself.")
                .font(.manrope(12))
                .foregroundStyle(Palette.warmInkSoft)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private var visible: [Snippet] {
        let term = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        guard !term.isEmpty else { return snippets }
        return snippets.filter {
            $0.trigger.lowercased().contains(term) || $0.expansion.lowercased().contains(term)
        }
    }

    private var countLabel: String {
        "\(snippets.count) \(snippets.count == 1 ? "snippet" : "snippets")"
    }

    private func commitEdit(_ snippet: Snippet) {
        guard let index = snippets.firstIndex(where: { $0.id == snippet.id }) else { return }
        let trigger = draftTrigger.trimmingCharacters(in: .whitespaces)
        guard !trigger.isEmpty else { editingID = nil; return }
        snippets[index].trigger = trigger
        snippets[index].expansion = draftExpansion
        editingID = nil
        save()
    }

    private func commitNew() {
        let trigger = draftTrigger.trimmingCharacters(in: .whitespaces)
        guard !trigger.isEmpty, !draftExpansion.isEmpty else { addingNew = false; return }
        snippets.append(Snippet(trigger: trigger, expansion: draftExpansion))
        addingNew = false
        save()
    }

    private func save() {
        SnippetStore.save(snippets.filter {
            !$0.trigger.trimmingCharacters(in: .whitespaces).isEmpty
        })
    }
}

private struct SnippetRow: View {
    let snippet: Snippet
    let onEdit: () -> Void
    let onDelete: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Text(snippet.trigger)
                .font(.manrope(13, .medium))
                .foregroundStyle(Palette.sunsetDeep)
                .frame(width: 140, alignment: .leading)
            Text(snippet.expansion.replacingOccurrences(of: "\n", with: " "))
                .font(.manrope(13))
                .foregroundStyle(Palette.warmInk)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
            // Always visible, not hover-only like the actions beside it —
            // this is the one thing on the row that says whether a
            // snippet is actually earning its keep, not just a control to
            // reveal on demand.
            if snippet.useCount > 0 {
                Text("\(snippet.useCount) \(snippet.useCount == 1 ? "use" : "uses")")
                    .font(.manrope(11))
                    .foregroundStyle(Palette.warmInkFaint)
                    .frame(width: 46, alignment: .trailing)
            }
            HStack(spacing: 6) {
                IconButton(icon: .edit, size: 22, iconSize: 12, help: "Edit", action: onEdit)
                IconButton(icon: .trash, size: 22, iconSize: 12, help: "Delete", action: onDelete)
            }
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
