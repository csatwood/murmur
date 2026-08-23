import SwiftUI

// MARK: - Snippets
//
// Searchable list with a live count and inline add/edit/delete, matching
// Dictionary's treatment — replacing the old stack of always-open editors.

struct SnippetsPage: View {
    @Binding var page: Page
    @State private var snippets: [Snippet] = []
    @State private var searchText = ""
    @State private var editingID: UUID?
    @State private var draftTrigger = ""
    @State private var draftExpansion = ""
    @State private var addingNew = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PageHeader(
                title: "Snippets",
                subtitle: "Say a trigger phrase, get a saved block pasted instead.")

            PageTip(text: "Say the trigger phrase exactly, ideally as its own pause — snippets "
                    + "don't fuzzy-match like Dictionary does, so Murmur only expands it when "
                    + "it hears the whole phrase.")
                .padding(.bottom, 16)

            HStack {
                SearchField(placeholder: "Search snippets…", text: $searchText)
                Spacer()
                Text("\(snippets.count) \(snippets.count == 1 ? "snippet" : "snippets")")
                    .font(.manrope(11.5))
                    .foregroundStyle(Palette.inkFaint)
            }
            .padding(.bottom, 12)

            if visible.isEmpty {
                Text(snippets.isEmpty
                     ? "No snippets yet — add signatures, addresses, or canned replies."
                     : "No matches.")
                    .font(.manrope(12.5))
                    .italic()
                    .foregroundStyle(Palette.inkFaint)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(visible.enumerated()), id: \.element.id) { index, snippet in
                        if editingID == snippet.id {
                            snippetForm(onSave: { commitEdit(snippet) },
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
                            Rectangle().fill(Palette.border).frame(height: 1)
                        }
                    }
                }
            }

            if addingNew {
                snippetForm(onSave: commitNew, onCancel: { addingNew = false })
                    .padding(.top, 6)
            } else {
                AddRowButton(title: "Add snippet") {
                    draftTrigger = ""
                    draftExpansion = ""
                    addingNew = true
                }
                .padding(.top, 8)
            }

            RelatedLink(
                prefix: "Need to reshape what you just said, not insert fixed text?",
                linkTitle: "Templates",
                suffix: "restructure the transcript itself."
            ) { page = .templates }
        }
        .onAppear { snippets = SnippetStore.load() }
    }

    private func snippetForm(onSave: @escaping () -> Void, onCancel: @escaping () -> Void) -> some View {
        HStack(alignment: .top, spacing: 8) {
            TextField("Say this…", text: $draftTrigger)
                .textFieldStyle(.plain)
                .font(.manrope(12.5))
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(Palette.panel, in: RoundedRectangle(cornerRadius: Radius.sm))
                .overlay(RoundedRectangle(cornerRadius: Radius.sm).stroke(Palette.border, lineWidth: 1))
                .frame(width: 140)
            Text("→").foregroundStyle(Palette.inkFaint).padding(.top, 8)
            TextEditor(text: $draftExpansion)
                .font(.manrope(12.5))
                .scrollContentBackground(.hidden)
                .padding(6)
                .frame(minHeight: 60)
                .background(Palette.panel, in: RoundedRectangle(cornerRadius: Radius.sm))
                .overlay(RoundedRectangle(cornerRadius: Radius.sm).stroke(Palette.border, lineWidth: 1))
            IconButton(icon: .check, help: "Save", action: onSave).padding(.top, 2)
            IconButton(icon: .plus, rotated: true, help: "Cancel", action: onCancel).padding(.top, 2)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 9)
    }

    private var visible: [Snippet] {
        let term = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        guard !term.isEmpty else { return snippets }
        return snippets.filter {
            $0.trigger.lowercased().contains(term) || $0.expansion.lowercased().contains(term)
        }
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
                .foregroundStyle(Palette.accentText)
                .frame(width: 140, alignment: .leading)
            Text(snippet.expansion.replacingOccurrences(of: "\n", with: " "))
                .font(.manrope(13))
                .foregroundStyle(Palette.ink)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
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
                .fill(hovering ? Palette.cardHover : Color.clear))
        // See HomeView.swift's historyRow for why this is needed: a .clear
        // background makes SwiftUI treat the row's empty space as outside
        // the hoverable region until this forces the whole padded frame to
        // count, regardless of what's actually drawn there.
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
    }
}
