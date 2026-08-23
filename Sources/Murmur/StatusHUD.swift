import AppKit
import SwiftUI

// MARK: - Status HUD
//
// Dictation's whole point is that you're working in *another* app, which
// means the main window — where `transformStatus` and the status pill live
// — is behind whatever you're typing into. During a Whisper transcription
// plus a rewrite pass, that left a menu-bar icon as the only sign the app
// was doing anything at all.
//
// This is a small floating pill that appears over everything while a
// dictation is in flight and disappears when it lands.

/// What the HUD is currently reporting.
enum HUDState: Equatable {
    case hidden
    case recording(handsFree: Bool)
    case processing(String)

    var label: String {
        switch self {
        case .hidden: return ""
        case .recording(let handsFree):
            return handsFree ? "Listening — hands-free" : "Listening"
        case .processing(let message): return message
        }
    }

    var isRecording: Bool {
        if case .recording = self { return true }
        return false
    }
}

/// Shared by `StatusHUDController` and `NavBarHUDController` — the two
/// panels dock at the identical screen spot (they're mutually exclusive,
/// never both visible), so both compute their origin the same way.
enum HUDDock {
    /// Bottom-centre of whichever screen the pointer is on. Anchoring to the
    /// text caret would need an Accessibility round-trip per frame and jumps
    /// around as text reflows; a fixed spot is calmer and always findable.
    ///
    /// The gap above the bottom edge is a small fraction of screen height
    /// (0.8%, floored at 6pt) rather than one fixed number — a flat gap
    /// looks right on a laptop display but noticeably oversized floating
    /// under everything on a large external monitor; scaling it keeps the
    /// pill reading as "just above the edge" on both. `visibleFrame` already
    /// excludes the Dock and menu bar, so this is a gap above whichever of
    /// those is actually the nearest boundary, not a fixed screen coordinate.
    static func origin(for size: NSSize) -> NSPoint {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) }
            ?? NSScreen.main
        guard let frame = screen?.visibleFrame else { return .zero }
        let bottomGap = max(6, frame.height * 0.008)
        return NSPoint(x: frame.midX - size.width / 2, y: frame.minY + bottomGap)
    }
}

@MainActor
final class StatusHUDController {
    private var panel: NSPanel?
    private let model = HUDModel()

    func update(_ state: HUDState) {
        guard state != .hidden else {
            hide()
            return
        }
        model.state = state
        show()
    }

    private func show() {
        let panel = existingOrNewPanel()
        position(panel)
        // `orderFrontRegardless` rather than `makeKeyAndOrderFront`: the HUD
        // must never take key status. Dictation pastes into whatever app was
        // frontmost when recording started, so stealing focus here would
        // send the text to Murmur instead of the user's actual target.
        panel.orderFrontRegardless()
    }

    private func hide() {
        panel?.orderOut(nil)
    }

    private func existingOrNewPanel() -> NSPanel {
        if let panel { return panel }

        let hosting = NSHostingView(rootView: StatusHUDView(model: model))
        hosting.frame = NSRect(x: 0, y: 0, width: 260, height: 46)

        let newPanel = NSPanel(
            contentRect: hosting.frame,
            // .nonactivatingPanel is the load-bearing flag — without it,
            // showing this window activates Murmur and breaks the paste.
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false)
        newPanel.contentView = hosting
        newPanel.isOpaque = false
        newPanel.backgroundColor = .clear
        newPanel.hasShadow = false
        newPanel.level = .statusBar
        newPanel.ignoresMouseEvents = true
        newPanel.hidesOnDeactivate = false
        newPanel.isReleasedWhenClosed = false
        // Belt-and-braces with .nonactivatingPanel: dictation pastes into
        // whichever app was frontmost, so this window must never become key.
        newPanel.becomesKeyOnlyIfNeeded = true
        // Follow the user across Spaces and sit above full-screen apps —
        // otherwise the HUD is invisible in exactly the full-screen editors
        // people dictate into most.
        newPanel.collectionBehavior = [
            .canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle,
        ]
        panel = newPanel
        return newPanel
    }

    private func position(_ panel: NSPanel) {
        panel.setFrameOrigin(HUDDock.origin(for: panel.frame.size))
    }
}

/// Separate observable so the panel's SwiftUI content updates without the
/// controller having to rebuild the hosting view on every state change.
@MainActor
private final class HUDModel: ObservableObject {
    @Published var state: HUDState = .hidden
}

private struct StatusHUDView: View {
    @ObservedObject var model: HUDModel

    var body: some View {
        HStack(spacing: 7) {
            if model.state.isRecording {
                MiniWaveform(color: Palette.accent)
            } else {
                ProcessingDots(color: Palette.accent)
            }
            Text(model.state.label)
                .font(.manrope(11, .medium))
                .foregroundStyle(.white)
                .lineLimit(1)
        }
        // Wispr Flow — the reference point for this element — docks a
        // pill this size right at another app's own bottom toolbar
        // without it reading as broken; the previous size and shadow
        // here were tuned for standing alone on a bare desktop, which is
        // the uncommon case; a floating HUD spends nearly all its time
        // over some app's own UI, not over one. No shadow at all, by
        // request — even the softened one still read as a box under the
        // pill rather than the pill just floating.
        .padding(.horizontal, 11)
        .padding(.vertical, 7)
        .background(
            Capsule().fill(Color(nsColor: NSColor(white: 0.08, alpha: 0.92))))
        .overlay(Capsule().stroke(.white.opacity(0.14), lineWidth: 1))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// A small animated audio-level waveform — the floating HUD's recording
/// indicator. Matches the compact, waveform-style indicator Wispr Flow
/// uses for the same "actively listening" moment, in place of the single
/// pulsing dot this used before — more legible at this pill's now-smaller
/// size, and it's what the most widely used app in this category already
/// trained users to recognize. Brand lime rather than the red "recording"
/// conventionally uses elsewhere — by request, for consistency with the
/// rest of the app rather than the OS-level recording convention; matched
/// in Home's capture zone (`CaptureWaveform`, `HomeView.swift`) so the
/// two surfaces agree.
private struct MiniWaveform: View {
    let color: Color
    @State private var tall = false

    private static let bars: [(delay: Double, short: CGFloat, tall: CGFloat)] = [
        (0.00, 0.35, 0.85), (0.10, 0.45, 1.0), (0.20, 0.3, 0.65),
        (0.05, 0.4, 0.9), (0.15, 0.35, 1.0),
    ]

    var body: some View {
        HStack(alignment: .center, spacing: 2.5) {
            ForEach(Array(Self.bars.enumerated()), id: \.offset) { _, bar in
                Capsule()
                    .fill(color)
                    .frame(width: 2.5, height: 13 * (tall ? bar.tall : bar.short))
                    .animation(
                        .easeInOut(duration: 0.45).repeatForever(autoreverses: true)
                            .delay(bar.delay),
                        value: tall)
            }
        }
        .frame(width: 20, height: 13)
        .onAppear { tall = true }
    }
}

/// Three dots bouncing in sequence — the HUD's indicator for every
/// non-recording state (cleaning up, transcribing, applying a style,
/// downloading/loading a model). Previously a bare system `ProgressView`
/// spinner, which read as generic and off-brand sitting next to
/// `MiniWaveform`'s lime bars. Deliberately a *bounce* rather than a
/// height change: the motion itself, not just the color, tells recording
/// and processing apart at a glance.
private struct ProcessingDots: View {
    let color: Color
    @State private var up = false

    private static let delays: [Double] = [0, 0.12, 0.24]

    var body: some View {
        HStack(spacing: 3) {
            ForEach(Array(Self.delays.enumerated()), id: \.offset) { _, delay in
                Circle()
                    .fill(color)
                    .frame(width: 4, height: 4)
                    .offset(y: up ? -3 : 0)
                    .animation(
                        .easeInOut(duration: 0.4).repeatForever(autoreverses: true)
                            .delay(delay),
                        value: up)
            }
        }
        .frame(width: 20, height: 13)
        .onAppear { up = true }
    }
}
