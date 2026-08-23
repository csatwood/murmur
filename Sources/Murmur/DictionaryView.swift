import SwiftUI

// MARK: - Dictionary
//
// Per the design: explains the mechanism up front, is searchable, shows a
// live count, and every row is genuinely editable/deletable — replacing
// the old always-editable field grid.

struct DictionaryPage: View {
    @Binding var page: Page
    @State private var rows: [DictionaryRow] = []
    @State private var searchText = ""
    @State private var editingID: UUID?
    @State private var draftFrom = ""
    @State private var draftTo = ""
    @State private var addingNew = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PageHeader(
                title: "Dictionary",
                subtitle: "Spoken phrases replaced in every transcript.")

            PageTip(text: "Say it roughly right — Murmur matches by sound, not exact wording, "
                    + "and swaps in the correction anywhere it lands in a sentence.")
                .padding(.bottom, 16)

            HStack {
                SearchField(placeholder: "Search words and phrases…", text: $searchText)
                Spacer()
                Text(countLabel)
                    .font(.manrope(11.5))
                    .foregroundStyle(Palette.inkFaint)
            }
            .padding(.bottom, 12)

            if visibleRows.isEmpty {
                Text(rows.isEmpty
                     ? "No words yet — add the names and jargon Murmur keeps getting wrong."
                     : "No matches.")
                    .font(.manrope(12.5))
                    .italic()
                    .foregroundStyle(Palette.inkFaint)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(visibleRows.enumerated()), id: \.element.id) { index, row in
                        if editingID == row.id {
                            EditPairRow(
                                fromPlaceholder: "Say this…",
                                toPlaceholder: "Get this instead",
                                from: $draftFrom, to: $draftTo,
                                onSave: { commitEdit(row) },
                                onCancel: { editingID = nil })
                        } else {
                            DictListRow(
                                from: row.spoken, to: row.replacement,
                                onEdit: {
                                    draftFrom = row.spoken
                                    draftTo = row.replacement
                                    editingID = row.id
                                },
                                onDelete: {
                                    rows.removeAll { $0.id == row.id }
                                    save()
                                })
                        }
                        if index != visibleRows.count - 1 {
                            Rectangle().fill(Palette.border).frame(height: 1)
                        }
                    }
                }
            }

            if addingNew {
                EditPairRow(
                    fromPlaceholder: "Say this…",
                    toPlaceholder: "Get this instead",
                    from: $draftFrom, to: $draftTo,
                    onSave: { commitNew() },
                    onCancel: { addingNew = false })
                    .padding(.top, 6)
            } else {
                AddRowButton(title: "Add word or phrase") {
                    draftFrom = ""
                    draftTo = ""
                    addingNew = true
                }
                .padding(.top, 8)
            }

            RelatedLink(
                prefix: "Mishearing your accent or a name, not a specific word?",
                linkTitle: "Voice Profile",
                suffix: learnedCorrectionsCount > 0
                    ? "learns those automatically — \(learnedCorrectionsCount) so far."
                    : "learns those automatically."
            ) { page = .training }
        }
        .onAppear(perform: load)
    }

    private var learnedCorrectionsCount: Int {
        LearnedStore.load().corrections.count
    }

    private var visibleRows: [DictionaryRow] {
        let term = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        guard !term.isEmpty else { return rows }
        return rows.filter {
            $0.spoken.lowercased().contains(term) || $0.replacement.lowercased().contains(term)
        }
    }

    private var countLabel: String {
        let n = rows.count
        return "\(n) \(n == 1 ? "entry" : "entries")"
    }

    private func commitEdit(_ row: DictionaryRow) {
        guard let index = rows.firstIndex(where: { $0.id == row.id }) else { return }
        let from = draftFrom.trimmingCharacters(in: .whitespaces)
        guard !from.isEmpty else { editingID = nil; return }
        rows[index].spoken = from
        rows[index].replacement = draftTo.trimmingCharacters(in: .whitespaces)
        editingID = nil
        save()
    }

    private func commitNew() {
        let from = draftFrom.trimmingCharacters(in: .whitespaces)
        guard !from.isEmpty else { addingNew = false; return }
        rows.append(DictionaryRow(
            spoken: from, replacement: draftTo.trimmingCharacters(in: .whitespaces)))
        addingNew = false
        save()
    }

    private func load() {
        rows = TextFormatter.loadDictionary()
            .sorted { $0.key < $1.key }
            .map { DictionaryRow(spoken: $0.key, replacement: $0.value) }
    }

    private func save() {
        var dictionary: [String: String] = [:]
        for row in rows {
            let spoken = row.spoken.trimmingCharacters(in: .whitespaces)
            if !spoken.isEmpty { dictionary[spoken] = row.replacement }
        }
        if let data = try? JSONEncoder().encode(dictionary) {
            try? data.write(to: TextFormatter.dictionaryURL, options: .atomic)
        }
    }
}

struct DictionaryRow: Identifiable {
    let id = UUID()
    var spoken: String
    var replacement: String
}

// MARK: - Shared row views

/// A read-only "spoken → replacement" row with hover-revealed actions.
struct DictListRow: View {
    let from: String
    let to: String
    let onEdit: () -> Void
    let onDelete: () -> Void

    @State private var hovering = false

    var body: some View {
        HStack(spacing: 16) {
            Text(from)
                .font(.manrope(13))
                .foregroundStyle(Palette.inkSoft)
                .frame(width: 140, alignment: .leading)
            HStack(spacing: 6) {
                Text("→").foregroundStyle(Palette.inkFaint)
                Text(to)
                    .font(.manrope(13, .medium))
                    .foregroundStyle(Palette.ink)
            }
            .font(.manrope(13))
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

/// The inline add/edit form used by Dictionary and Style.
struct EditPairRow: View {
    let fromPlaceholder: String
    let toPlaceholder: String
    @Binding var from: String
    @Binding var to: String
    let onSave: () -> Void
    let onCancel: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            TextField(fromPlaceholder, text: $from)
                .textFieldStyle(.plain)
                .font(.manrope(12.5))
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(Palette.panel, in: RoundedRectangle(cornerRadius: Radius.sm))
                .overlay(RoundedRectangle(cornerRadius: Radius.sm).stroke(Palette.border, lineWidth: 1))
                .frame(width: 140)
                .onSubmit(onSave)
            Text("→").foregroundStyle(Palette.inkFaint)
            TextField(toPlaceholder, text: $to)
                .textFieldStyle(.plain)
                .font(.manrope(12.5))
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(Palette.panel, in: RoundedRectangle(cornerRadius: Radius.sm))
                .overlay(RoundedRectangle(cornerRadius: Radius.sm).stroke(Palette.border, lineWidth: 1))
                .onSubmit(onSave)
            IconButton(icon: .check, help: "Save", action: onSave)
            IconButton(icon: .plus, rotated: true, help: "Cancel", action: onCancel)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 9)
    }
}
