import AppKit
import Carbon.HIToolbox
import Foundation

struct Transform: Identifiable {
    let id: String
    let name: String
    let keyLabel: String
    let keyCode: UInt16
    let description: String
    let instructions: String
    /// Only true for `CustomTransform`-backed entries — gates the edit/
    /// delete affordances `TransformsPage` shows on a card, so a built-in
    /// never offers to delete itself.
    var isCustom = false

    static let all: [Transform] = [
        Transform(
            id: "polish",
            name: "Polish",
            keyLabel: "⌥1",
            keyCode: UInt16(kVK_ANSI_1),
            description: "Fixes grammar, spelling and punctuation and tightens " +
                         "the wording without changing meaning or tone.",
            instructions: "Polish the user's text: fix grammar, spelling and " +
                "punctuation, and improve clarity and flow. Keep the meaning, " +
                "tone, formatting and language unchanged."),
        Transform(
            id: "promptEngineer",
            name: "Prompt Engineer",
            keyLabel: "⌥2",
            keyCode: UInt16(kVK_ANSI_2),
            description: "Turns a rough idea into a clear, well-structured " +
                         "prompt for an AI assistant.",
            instructions: "Rewrite the user's rough notes as a clear, " +
                "well-structured prompt for an AI assistant: organize the " +
                "content into labeled sections — Goal, Context, " +
                "Instructions, and Constraints/Format — inferring structure " +
                "the notes imply but don't state outright. Unlike a light " +
                "copyedit, restructuring and expanding short notes into " +
                "full labeled sections is the job here, not elaboration: a " +
                "short input producing a longer, organized output is " +
                "correct, as long as every stated fact and intent traces " +
                "back to what was actually said."),
    ]

    /// ⌥1/⌥2 are the two built-ins' own territory (see `ProfileHotkeySlot`'s
    /// own comment on why Option+digit is `TransformManager`'s) — a custom
    /// transform gets the next slot up, ⌥3 through ⌥9, assigned by its
    /// position in `CustomTransformStore.load()` rather than stored on the
    /// transform itself, so deleting one automatically closes the gap
    /// instead of leaving a dead slot behind. An 8th+ custom transform is
    /// still fully usable from the page itself, just without a global
    /// shortcut — seven is what the keyboard's own top row has left.
    private static let customSlotKeyCodes: [UInt16] = [
        UInt16(kVK_ANSI_3), UInt16(kVK_ANSI_4), UInt16(kVK_ANSI_5), UInt16(kVK_ANSI_6),
        UInt16(kVK_ANSI_7), UInt16(kVK_ANSI_8), UInt16(kVK_ANSI_9),
    ]

    /// `Transform.all` plus a given list of custom ones, mapped into the
    /// same display/runnable shape — the one place slot-to-shortcut
    /// assignment happens, shared by `allIncludingCustom` below (reads the
    /// store fresh) and `TransformsPage` (passes its own `@State` mirror,
    /// so the card grid updates immediately on edit/delete without a
    /// round-trip through disk).
    static func merging(_ customs: [CustomTransform]) -> [Transform] {
        let mapped = customs.enumerated().map { index, custom -> Transform in
            let keyCode = customSlotKeyCodes.indices.contains(index) ? customSlotKeyCodes[index] : nil
            return Transform(
                id: "custom-\(custom.id.uuidString)",
                name: custom.name,
                keyLabel: keyCode.map { _ in "⌥\(index + 3)" } ?? "—",
                keyCode: keyCode ?? .max,
                description: custom.instructions,
                instructions: custom.instructions,
                isCustom: true)
        }
        return all + mapped
    }

    /// `Transform.all` plus every saved `CustomTransform`, freshly resolved
    /// — never cached, the same "read the store, don't hold a stale copy"
    /// rule every other `*Store.load()` in this app already follows.
    static var allIncludingCustom: [Transform] { merging(CustomTransformStore.load()) }

    // MARK: - Self test (slot assignment)

    static func runSelfTest() -> Bool {
        var passed = true
        func check(_ ok: Bool, _ label: String) {
            if !ok { passed = false }
            print("\(ok ? "PASS" : "FAIL"): \(label)")
        }

        check(merging([]).count == all.count,
              "no customs: merging([]) is exactly the two built-ins")

        let three = (1...3).map { CustomTransform(name: "Custom \($0)", instructions: "Do thing \($0)") }
        let mergedThree = merging(three)
        check(mergedThree.count == all.count + 3, "three customs appended after the built-ins")
        check(mergedThree[2].keyLabel == "⌥3" && mergedThree[3].keyLabel == "⌥4"
              && mergedThree[4].keyLabel == "⌥5",
              "custom slots start at ⌥3 and count up in order")
        check(mergedThree[2].isCustom && !mergedThree[0].isCustom,
              "isCustom distinguishes a custom entry from a built-in")
        check(mergedThree[2].id == "custom-\(three[0].id.uuidString)",
              "a custom entry's id round-trips its own CustomTransform.id")

        // Only 7 slots (⌥3…9) exist — an 8th custom transform is still
        // listed (runnable manually) but gets no working shortcut.
        let eight = (1...8).map { CustomTransform(name: "Custom \($0)", instructions: "x") }
        let mergedEight = merging(eight)
        check(mergedEight.count == all.count + 8, "an 8th custom transform still appears in the list")
        check(mergedEight.last?.keyLabel == "—", "the 8th custom transform has no shortcut slot left")

        // No keyCode collisions between built-ins and customs, or between
        // two customs — a real hotkey monitor picks the *first* match, so
        // a collision would silently make one transform unreachable.
        let keyCodes = mergedEight.map(\.keyCode).filter { $0 != .max }
        check(Set(keyCodes).count == keyCodes.count, "every assigned keyCode is unique, no collisions")

        return passed
    }
}

struct CustomTransform: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var instructions: String
}

/// User-created Transforms — Wispr Flow's own "Create your own" / "Upload
/// your own prompt" card, which the two hardcoded built-ins above had no
/// equivalent of. Same file-backed JSON pattern as `SnippetStore`.
enum CustomTransformStore {
    static var fileURL: URL {
        AppPaths.supportDirectory.appendingPathComponent("custom_transforms.json")
    }

    static func load() -> [CustomTransform] {
        guard let data = try? Data(contentsOf: fileURL),
              let items = try? JSONDecoder().decode([CustomTransform].self, from: data)
        else { return [] }
        return items
    }

    static func save(_ items: [CustomTransform]) {
        if let data = try? JSONEncoder().encode(items) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }
}

/// Global ⌥1 / ⌥2 (plus ⌥3…9 for any custom transform) hotkeys that rewrite
/// the currently selected text in place, in any app — like Wispr Flow's
/// Transforms. Uses the on-device model.
@MainActor
final class TransformManager {
    private let engine: RewriteEngine
    private var monitor: Any?
    private var isRunning = false
    /// Set right after a transform successfully pastes its result, cleared
    /// once `undoLast()` is used (or another transform runs) — a plain
    /// flag rather than tracking the original text, since forwarding to
    /// the target app's own ⌘Z is what actually restores it correctly.
    /// Reconstructing the paste ourselves would need to know and re-select
    /// the exact range that's now on screen in an arbitrary third-party
    /// app, which nothing here has any way to do reliably.
    private var canUndo = false

    /// Status line for the UI; nil clears it.
    var onStatus: ((String?) -> Void)?
    var onError: ((String) -> Void)?

    init(engine: RewriteEngine) {
        self.engine = engine
    }

    func startMonitoring() {
        stopMonitoring()
        monitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) {
            [weak self] event in
            guard let self else { return }
            let modifiers = event.modifierFlags.intersection(
                [.command, .option, .control, .shift])
            // ⌥⇧Z: undo the last transform via the target app's own ⌘Z,
            // not a combo any other global-hotkey consumer in this app
            // touches (Option+digit is Transforms' own, Control+Shift+digit
            // is App Profiles', Scratchpad/Notetaker's own combos are both
            // user-rebindable away from this by default).
            if modifiers == [.option, .shift], event.keyCode == UInt16(kVK_ANSI_Z) {
                Task { @MainActor in self.undoLast() }
                return
            }
            guard modifiers == .option else { return }
            guard let transform = Transform.allIncludingCustom.first(
                where: { $0.keyCode == event.keyCode }) else { return }
            Task { @MainActor in self.run(transform) }
        }
    }

    func stopMonitoring() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
        monitor = nil
    }

    func run(_ transform: Transform) {
        guard !isRunning else { return }
        guard engine.isAvailable else {
            onError?(engine.availabilityNote ?? "On-device model unavailable.")
            NSSound(named: "Basso")?.play()
            return
        }
        isRunning = true
        onStatus?("\(transform.name): reading selection")

        Task {
            defer {
                isRunning = false
                onStatus?(nil)
            }
            let saved = TextInserter.saveClipboard()
            guard let selection = await TextInserter.copySelection(),
                  !selection.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else {
                TextInserter.restoreClipboard(saved)
                onError?("Select some text first, then press " +
                         "\(transform.keyLabel).")
                NSSound(named: "Basso")?.play()
                return
            }

            onStatus?("\(transform.name): rewriting")
            do {
                let rewritten = try await engine.edit(
                    selection, instructions: transform.instructions)
                guard !rewritten.isEmpty else {
                    throw NSError(domain: "Murmur", code: 2, userInfo: [
                        NSLocalizedDescriptionKey: "Model returned empty text",
                    ])
                }
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.setString(rewritten, forType: .string)
                TextInserter.sendKeystroke(kVK_ANSI_V, flags: .maskCommand)
                canUndo = true
                NSSound(named: "Tink")?.play()
                try? await Task.sleep(nanoseconds: 600_000_000)
                TextInserter.restoreClipboard(saved)
            } catch {
                TextInserter.restoreClipboard(saved)
                onError?("\(transform.name) failed: \(error.localizedDescription)")
                NSSound(named: "Basso")?.play()
            }
        }
    }

    /// Runs a transform on arbitrary text (used by the Transforms page).
    func apply(_ transform: Transform, to text: String) async throws -> String {
        try await engine.edit(text, instructions: transform.instructions)
    }

    /// Reverts the most recent transform by sending the target app its own
    /// ⌘Z — the safety net Transforms didn't have: a transform used to
    /// paste over your selection with no way back except whatever the
    /// target app's own undo happened to still remember unprompted.
    func undoLast() {
        guard canUndo, !isRunning else {
            onError?("Nothing to undo.")
            NSSound(named: "Basso")?.play()
            return
        }
        canUndo = false
        isRunning = true
        onStatus?("Undoing last transform")
        TextInserter.sendKeystroke(kVK_ANSI_Z, flags: .maskCommand)
        NSSound(named: "Tink")?.play()
        Task {
            try? await Task.sleep(nanoseconds: 500_000_000)
            isRunning = false
            onStatus?(nil)
        }
    }
}
