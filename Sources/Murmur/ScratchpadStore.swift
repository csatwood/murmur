import Foundation

struct ScratchpadNote: Codable, Identifiable, Equatable {
    let id: UUID
    var text: String
    let createdAt: Date
    var updatedAt: Date

    init(id: UUID = UUID(), text: String = "", createdAt: Date = Date(), updatedAt: Date = Date()) {
        self.id = id
        self.text = text
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    /// There's no separate title field — like Wispr Flow's own notes, a
    /// note's name is just its own first line.
    var title: String {
        let firstLine = text.split(separator: "\n", maxSplits: 1).first.map(String.init) ?? ""
        let trimmed = firstLine.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return "Untitled" }
        return trimmed.count > 60 ? String(trimmed.prefix(60)) + "…" : trimmed
    }

    var isEmpty: Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

/// Murmur's quick-capture notes: dictate or type a thought without leaving
/// (or even opening) the app, then come back later to develop it further —
/// modeled on Wispr Flow's own Scratchpad. Multiple short-lived notes, not
/// the single overwritable buffer this page used to be; see `legacyFileURL`
/// for how an existing buffer survives the upgrade.
@MainActor
final class ScratchpadStore: ObservableObject {
    @Published private(set) var notes: [ScratchpadNote] = []

    private var fileURL: URL {
        AppPaths.supportDirectory.appendingPathComponent("scratchpad_notes.json")
    }
    /// Where the previous single-buffer version of this page saved. Read
    /// once, only when there's no multi-note file yet, so upgrading from
    /// that version turns whatever was already sitting there into this
    /// store's first note instead of silently dropping it.
    private var legacyFileURL: URL {
        AppPaths.supportDirectory.appendingPathComponent("scratchpad.txt")
    }

    /// Newest-edited first — what "Recents" means, and also which note a
    /// freshly opened panel lands on.
    var notesByRecency: [ScratchpadNote] {
        notes.sorted { $0.updatedAt > $1.updatedAt }
    }

    init() {
        if let data = try? Data(contentsOf: fileURL),
           let saved = try? JSONDecoder().decode([ScratchpadNote].self, from: data) {
            notes = saved
        } else if let legacyText = try? String(contentsOf: legacyFileURL, encoding: .utf8),
                  !legacyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            notes = [ScratchpadNote(text: legacyText)]
            save()
        }
    }

    /// Re-reads from disk — the in-app page's "Recents" refresh icon calls
    /// this. Everything here already flows through `notes` reactively, so
    /// in practice this only matters if the file changed some other way
    /// (a restored backup, hand-editing the JSON) since this store loaded.
    func reload() {
        guard let data = try? Data(contentsOf: fileURL),
              let saved = try? JSONDecoder().decode([ScratchpadNote].self, from: data)
        else { return }
        notes = saved
    }

    @discardableResult
    func createNote() -> ScratchpadNote {
        let note = ScratchpadNote()
        notes.insert(note, at: 0)
        save()
        return note
    }

    func update(id: UUID, text: String) {
        guard let index = notes.firstIndex(where: { $0.id == id }) else { return }
        notes[index].text = text
        notes[index].updatedAt = Date()
        save()
    }

    func delete(id: UUID) {
        notes.removeAll { $0.id == id }
        save()
    }

    func note(id: UUID) -> ScratchpadNote? {
        notes.first { $0.id == id }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(notes) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    static func matching(_ query: String, in notes: [ScratchpadNote]) -> [ScratchpadNote] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return notes }
        return notes.filter { $0.text.localizedCaseInsensitiveContains(trimmed) }
    }
}
