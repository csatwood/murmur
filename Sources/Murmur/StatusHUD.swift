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

    // One fixed size, not a base/expanded pair — this HUD no longer shows
    // a live transcript that needs room to grow into (see this file's own
    // removal note on `LiveTranscriptText`), so there's nothing left that
    // ever needs the panel taller than its icon/wave/label footer alone.
    // Wide enough for the longest status label ("Listening — hands-free")
    // to sit comfortably next to a full-width waveform without crowding.
    private static let size = NSSize(width: 320, height: 58)

    func update(_ state: HUDState) {
        guard state != .hidden else {
            hide()
            return
        }
        model.state = state
        show()
    }

    /// Set once, from `AppDelegate.startRecording()`, to the frontmost
    /// app's own `NSRunningApplication.icon` at the moment recording
    /// starts — the icon shown in the HUD's footer is *who this dictation
    /// is going to*, not Murmur's own icon. Only actually cleared in
    /// `hide()`, so it stays put through the brief `.processing` moment.
    func setTargetAppIcon(_ icon: NSImage?) {
        model.targetAppIcon = icon
    }

    private func show() {
        let panel = existingOrNewPanel()
        panel.setFrame(
            NSRect(origin: HUDDock.origin(for: Self.size), size: Self.size),
            display: true, animate: false)
        // `orderFrontRegardless` rather than `makeKeyAndOrderFront`: the HUD
        // must never take key status. Dictation pastes into whatever app was
        // frontmost when recording started, so stealing focus here would
        // send the text to Murmur instead of the user's actual target.
        panel.orderFrontRegardless()
    }

    private func hide() {
        panel?.orderOut(nil)
        model.targetAppIcon = nil
    }

    private func existingOrNewPanel() -> NSPanel {
        if let panel { return panel }

        let hosting = NSHostingView(rootView: StatusHUDView(model: model))
        hosting.frame = NSRect(origin: .zero, size: Self.size)

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
}

/// Separate observable so the panel's SwiftUI content updates without the
/// controller having to rebuild the hosting view on every state change.
@MainActor
private final class HUDModel: ObservableObject {
    @Published var state: HUDState = .hidden
    /// The target app's own icon — see `StatusHUDController.setTargetAppIcon`.
    @Published var targetAppIcon: NSImage?
}

/// Icon / wave / label only — this used to also show a live-transcript
/// preview above this row (`LiveTranscriptText`, removed), decoded by a
/// separate, faster-but-lower-quality model (Parakeet Flash) than whichever
/// engine the user actually has selected. In practice that meant two real
/// problems, not just a styling one: it was often several seconds behind
/// (sometimes never appearing at all for a short dictation) and, being a
/// different model, could show words visibly different from the real
/// transcript that replaced it — reading as "this got it wrong" right
/// before the correct text appeared, which undermined trust rather than
/// building it. The waveform below already answers the one question a live
/// preview was trying to: "is it actually hearing me" — without ever being
/// able to look *wrong*.
private struct StatusHUDView: View {
    @ObservedObject var model: HUDModel

    var body: some View {
        statusRow
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .background(hudShape.fill(Palette.navActivePill))
            .overlay(hudShape.stroke(.white.opacity(0.14), lineWidth: 1))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Target-app icon, then a waveform/dots that stretches to fill the
    /// middle, then the state label fixed to its own natural width on the
    /// right — icon-left / wave-centered / label-right.
    private var statusRow: some View {
        HStack(spacing: 12) {
            if let icon = model.targetAppIcon {
                Image(nsImage: icon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 24, height: 24)
            }
            if model.state.isRecording {
                MiniWaveform(color: Palette.sunset)
            } else {
                ProcessingDots(color: Palette.sunset)
            }
            Text(model.state.label)
                .font(.manrope(14, .medium))
                .foregroundStyle(.white)
                .lineLimit(1)
                .fixedSize()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    // A capsule, always — with no more taller "expanded" card state to
    // distinguish from, this is back to being a single fixed-height pill
    // in every way that matters, the same as before the live-transcript
    // feature (and its own two-shape `hudShape`) existed.
    private var hudShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: Self.dockedCornerRadius, style: .continuous)
    }

    private static let dockedCornerRadius: CGFloat = 25
}

/// A small animated audio-level waveform — the floating HUD's recording
/// indicator. Matches the compact, waveform-style indicator Wispr Flow
/// uses for the same "actively listening" moment, in place of the single
/// pulsing dot this used before — more legible at this pill's now-smaller
/// size, and it's what the most widely used app in this category already
/// trained users to recognize. Sunset orange rather than the red
/// "recording" conventionally uses elsewhere, matching the "Main" redesign's
/// own accent (Home's hero, the sidebar's active pill) rather than the
/// OS-level recording convention.
private struct MiniWaveform: View {
    let color: Color
    @State private var tall = false

    // 11 bars, not 5 — the icon/wave/label footer redesign puts this in
    // the middle of a much wider row (it now stretches via `maxWidth:
    // .infinity` below to fill the space between the app icon and the
    // state label, matching the reference's noticeably denser, wider
    // waveform, instead of sitting as a small fixed-width glyph next to
    // the label the way it did before.
    private static let bars: [(delay: Double, short: CGFloat, tall: CGFloat)] = [
        (0.00, 0.3, 0.55), (0.08, 0.45, 0.85), (0.16, 0.3, 0.6), (0.04, 0.5, 1.0),
        (0.20, 0.35, 0.7), (0.12, 0.55, 0.95), (0.02, 0.3, 0.55), (0.18, 0.45, 0.85),
        (0.10, 0.3, 0.65), (0.06, 0.4, 0.75), (0.14, 0.3, 0.5),
    ]

    var body: some View {
        HStack(alignment: .center, spacing: 3) {
            ForEach(Array(Self.bars.enumerated()), id: \.offset) { _, bar in
                Capsule()
                    .fill(color)
                    .frame(width: 3, height: 22 * (tall ? bar.tall : bar.short))
                    .animation(
                        .easeInOut(duration: 0.45).repeatForever(autoreverses: true)
                            .delay(bar.delay),
                        value: tall)
            }
        }
        .frame(height: 22)
        .frame(maxWidth: .infinity)
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
        .frame(height: 13)
        // `maxWidth: .infinity`, matching `MiniWaveform`'s own — so the
        // footer's middle slot stays centered between the app icon and
        // the state label the same way regardless of which of the two
        // indicators is showing, rather than the label shifting left
        // whenever a processing state swaps the wave out for these dots.
        .frame(maxWidth: .infinity)
        .onAppear { up = true }
    }
}
