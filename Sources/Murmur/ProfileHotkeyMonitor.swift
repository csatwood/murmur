import AppKit
import Carbon.HIToolbox
import Foundation

/// One of nine Control+Shift+digit combos a user can bind an `AppProfile`
/// to, so dictating with that profile's style/template doesn't depend on
/// whichever app happens to be frontmost. Control+Shift is deliberately
/// disjoint from every other global-hotkey consumer: `TransformManager`
/// already owns Option+digit (⌥1/⌥2), and critically, `HotkeyMonitor`'s
/// "Right Option" mode fires on the bare physical Option key via
/// `.flagsChanged` regardless of what else is held — any combo that
/// includes Option would risk that monitor firing independently on the
/// same keypress.
enum ProfileHotkeySlot: Int, Codable, CaseIterable {
    case one = 1, two, three, four, five, six, seven, eight, nine

    var keyCode: UInt16 {
        switch self {
        case .one: return UInt16(kVK_ANSI_1)
        case .two: return UInt16(kVK_ANSI_2)
        case .three: return UInt16(kVK_ANSI_3)
        case .four: return UInt16(kVK_ANSI_4)
        case .five: return UInt16(kVK_ANSI_5)
        case .six: return UInt16(kVK_ANSI_6)
        case .seven: return UInt16(kVK_ANSI_7)
        case .eight: return UInt16(kVK_ANSI_8)
        case .nine: return UInt16(kVK_ANSI_9)
        }
    }

    var label: String { "⌃⇧\(rawValue)" }
}

/// Global Control+Shift+1…9 hotkeys, each toggling a force-started
/// dictation resolved against one `AppProfile`, regardless of the frontmost
/// app. A toggle — press to start, the same combo to stop — rather than
/// hold-to-talk: a profile combo needs a non-modifier key to be
/// distinguishable per profile, and holding a multi-key chord for a full
/// dictation is uncomfortable in a way holding the single main-hotkey
/// modifier isn't. No separate hands-free mode is needed either — a toggle
/// already is one.
///
/// Mirrors `TransformManager`'s monitor shape (global `NSEvent` monitor +
/// modifier/keyCode match, not a Carbon-registered hotkey) rather than
/// inventing a third mechanism.
@MainActor
final class ProfileHotkeyMonitor {
    private var monitor: Any?
    var onTrigger: ((ProfileHotkeySlot) -> Void)?

    func startMonitoring() {
        stopMonitoring()
        monitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) {
            [weak self] event in
            guard let self else { return }
            let modifiers = event.modifierFlags.intersection(
                [.command, .option, .control, .shift])
            guard modifiers == [.control, .shift] else { return }
            guard let slot = ProfileHotkeySlot.allCases.first(
                where: { $0.keyCode == event.keyCode }) else { return }
            Task { @MainActor in self.onTrigger?(slot) }
        }
    }

    func stopMonitoring() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
        monitor = nil
    }
}
