import AppKit
import Speech
import SwiftUI

// MARK: - Nav Bar HUD
//
// A second floating element, separate from `StatusHUDController`, docked at
// the identical screen spot. The two are mutually exclusive: this one only
// ever exists while the status HUD is hidden (`AppDelegate.updateHUD`'s own
// `state == .hidden` check drives both), and disappears the instant a
// dictation starts. Invisible until hovered — discovering it means moving
// the pointer to the dock spot while idle.
//
// Unlike the status HUD, this one has to accept mouse events (hover to
// reveal, clicks on its icons), so it can't use `ignoresMouseEvents`. That
// means its panel frame is a real, if small and idle-only, hit-testable
// strip at the bottom of the screen — clicks there go to Murmur, not
// whatever's underneath. The panel stays at a small fixed size until a
// popover actually opens, and only grows for that (see `resize`), so the
// footprint stays as small as it can while still being discoverable.

@MainActor
final class NavBarHUDController {
    private var panel: NSPanel?
    private let model = NavBarHUDModel()

    private static let smallSize = NSSize(width: 260, height: 54)
    private static let largeSize = NSSize(width: 260, height: 300)

    init() {
        model.onPopoverChange = { [weak self] open in
            self?.resize(forPopover: open)
        }
    }

    func setActive(_ active: Bool, app: AppDelegate) {
        if active {
            let panel = existingOrNewPanel(app: app)
            panel.setFrameOrigin(HUDDock.origin(for: panel.frame.size))
            panel.orderFrontRegardless()
        } else {
            panel?.orderOut(nil)
        }
    }

    private func resize(forPopover open: Bool) {
        guard let panel else { return }
        let size = open ? Self.largeSize : Self.smallSize
        // Not animated — confirmed via a real crash report
        // (EXC_BAD_ACCESS in AppKit's NSMoveHelper animation machinery).
        // `setActive(false)` can call `orderOut` on this same panel at any
        // moment (dictation can start mid-hover), and ordering out a
        // window with an in-flight *animated* setFrame corrupts AppKit's
        // window-animation state. An instant resize has no in-flight
        // window for that race to land in.
        panel.setFrame(
            NSRect(origin: HUDDock.origin(for: size), size: size),
            display: true, animate: false)
    }

    private func existingOrNewPanel(app: AppDelegate) -> NSPanel {
        if let panel { return panel }

        let hosting = NSHostingView(rootView: NavBarHUDView(app: app, model: model))
        hosting.frame = NSRect(origin: .zero, size: Self.smallSize)

        let newPanel = NSPanel(
            contentRect: hosting.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false)
        newPanel.contentView = hosting
        newPanel.isOpaque = false
        newPanel.backgroundColor = .clear
        newPanel.hasShadow = false
        newPanel.level = .statusBar
        newPanel.ignoresMouseEvents = false
        newPanel.hidesOnDeactivate = false
        newPanel.isReleasedWhenClosed = false
        // Clicks that navigate (Ask Murmur, Settings, …) call
        // `app.showMainWindow()` themselves, which activates deliberately —
        // this just keeps merely *hovering* the bar from stealing focus.
        newPanel.becomesKeyOnlyIfNeeded = true
        newPanel.collectionBehavior = [
            .canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle,
        ]
        panel = newPanel
        return newPanel
    }
}

/// Just a closure passthrough from the SwiftUI content back to the
/// controller (which popover being open drives the panel's size) — no
/// `@Published` state, so no `ObservableObject` needed.
private final class NavBarHUDModel {
    var onPopoverChange: ((Bool) -> Void)?
}

// MARK: - Content

private enum NavPopoverKind {
    case listen, quick, more
}

/// Fixed dark, white-based colors throughout — matches `StatusHUDView`'s own
/// reasoning: this floats over arbitrary desktop content, not app UI, so it
/// stays legible the same way regardless of Murmur's own light/dark setting.
private enum HUDStyle {
    static let pillFill = Color(nsColor: NSColor(white: 0.08, alpha: 0.92))
    static let pillBorder = Color.white.opacity(0.14)
    static let popoverFill = Color(nsColor: NSColor(white: 0.10, alpha: 0.97))
    static let iconIdle = Color.white.opacity(0.55)
    static let iconHoverBG = Color.white.opacity(0.10)
}

private struct NavBarHUDView: View {
    @ObservedObject var app: AppDelegate
    let model: NavBarHUDModel

    @State private var pillHovered = false
    @State private var openPopover: NavPopoverKind?
    @State private var useVoiceProfile = Settings.useVoiceProfile
    @State private var supportedLocaleIDs: [String] = []

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            pill.padding(.bottom, 9)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .contentShape(Rectangle())
        .onHover { inside in
            withAnimation(.murmurEase(0.16)) { pillHovered = inside }
            if !inside { openPopover = nil }
        }
        .onChange(of: openPopover) { _, new in
            model.onPopoverChange?(new != nil)
        }
        .task {
            let locales = await SpeechTranscriber.supportedLocales
            supportedLocaleIDs = locales
                .map { $0.identifier(.bcp47) }
                .sorted {
                    (Locale.current.localizedString(forIdentifier: $0) ?? $0)
                    < (Locale.current.localizedString(forIdentifier: $1) ?? $1)
                }
        }
    }

    private var pill: some View {
        HStack(spacing: 2) {
            micIcon
            listenIcon
            voiceProfileIcon
            Rectangle().fill(HUDStyle.pillBorder).frame(width: 1, height: 16)
                .padding(.horizontal, 6)
            quickActionsIcon
            moreIcon
        }
        .padding(9)
        .background(Capsule().fill(HUDStyle.pillFill))
        .overlay(Capsule().stroke(HUDStyle.pillBorder, lineWidth: 1))
        .opacity(pillHovered ? 1 : 0)
        .scaleEffect(pillHovered ? 1 : 0.96, anchor: .bottom)
        .allowsHitTesting(pillHovered)
    }

    // MARK: Mic — display only, no popover

    private var micIcon: some View {
        NavIconButton(badgeText: nil, icon: .mic, active: false) {}
            .murmurHUDTooltip("Dictate \(app.hotkey.displayName)")
    }

    // MARK: Listen — language + recognition engine

    private var listenIcon: some View {
        NavIconButton(
            badgeText: String(app.localeID.prefix(2)).uppercased(), icon: nil,
            active: openPopover == .listen
        ) {}
        .onHover { inside in openPopover = inside ? .listen : (openPopover == .listen ? nil : openPopover) }
        .overlay(alignment: .bottom) {
            if openPopover == .listen {
                NavPopover {
                    NavPopoverHeader("Language")
                    ScrollView {
                        VStack(spacing: 0) {
                            ForEach(supportedLocaleIDs, id: \.self) { id in
                                NavPopoverRow(
                                    title: Locale.current.localizedString(forIdentifier: id) ?? id,
                                    selected: id == app.localeID
                                ) { app.setLocale(id) }
                            }
                        }
                    }
                    .frame(maxHeight: 108)
                    NavPopoverDivider()
                    NavPopoverHeader("Recognition engine")
                    NavPopoverRow(title: "Apple", selected: app.engine == "apple") {
                        app.setEngine("apple")
                    }
                    NavPopoverRow(title: "Whisper", selected: app.engine == "whisper") {
                        app.setEngine("whisper")
                    }
                    NavPopoverRow(title: "whisper.cpp", selected: app.engine == "whispercpp") {
                        app.setEngine("whispercpp")
                    }
                }
                .offset(y: -44)
            }
        }
    }

    // MARK: Voice Profile — plain toggle, no popover

    private var voiceProfileIcon: some View {
        NavIconButton(badgeText: nil, icon: .wave, active: useVoiceProfile) {
            useVoiceProfile.toggle()
            Settings.useVoiceProfile = useVoiceProfile
        }
        .murmurHUDTooltip("Voice Profile \(useVoiceProfile ? "On" : "Off")")
    }

    // MARK: Quick actions — templates + transforms

    private var quickActionsIcon: some View {
        NavIconButton(badgeText: nil, icon: .trans, active: openPopover == .quick) {}
            .onHover { inside in openPopover = inside ? .quick : (openPopover == .quick ? nil : openPopover) }
            .overlay(alignment: .bottom) {
                if openPopover == .quick {
                    NavPopover {
                        NavPopoverHeader("Templates")
                        ForEach(NoteTemplateStore.all().prefix(4)) { template in
                            NavPopoverRow(title: template.name) {
                                navigate(to: .templates)
                            }
                        }
                        NavPopoverRow(title: "All templates →", muted: true) {
                            navigate(to: .templates)
                        }
                        NavPopoverDivider()
                        NavPopoverHeader("Transforms")
                        ForEach(Transform.all) { transform in
                            NavPopoverRow(title: transform.name, trailing: transform.keyLabel) {
                                navigate(to: .transforms)
                            }
                        }
                    }
                    .offset(y: -44)
                }
            }
    }

    // MARK: More — everything else real but unthemed, plus Settings

    private var moreIcon: some View {
        NavIconButton(badgeText: nil, icon: .more, active: openPopover == .more) {}
            .onHover { inside in openPopover = inside ? .more : (openPopover == .more ? nil : openPopover) }
            .overlay(alignment: .bottom) {
                if openPopover == .more {
                    NavPopover {
                        NavPopoverRow(title: "Ask Murmur", icon: .ask) {
                            navigate(to: .ask)
                        }
                        NavPopoverRow(title: "New note", icon: .scratch, trailing: "⌥M") {
                            navigate(to: .scratchpad)
                        }
                        NavPopoverRow(title: "Copy last dictation", icon: .copy) {
                            copyLastDictation()
                            openPopover = nil
                        }
                        NavPopoverDivider()
                        NavPopoverRow(title: "Settings", icon: .settings, muted: true) {
                            navigate(to: .settings)
                        }
                    }
                    .offset(y: -44)
                }
            }
    }

    private func navigate(to page: Page) {
        app.pendingNavigateToPage = page
        app.showMainWindow()
        openPopover = nil
    }

    private func copyLastDictation() {
        guard let text = app.entries.first?.text else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }
}

// MARK: - Small building blocks

private struct NavIconButton: View {
    let badgeText: String?
    let icon: MurmurIcon?
    let active: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Group {
                if let badgeText {
                    Text(badgeText).font(.manrope(10.5, .bold)).kerning(0.2)
                } else if let icon {
                    MurmurIconView(icon: icon).frame(width: 15, height: 15)
                }
            }
            .foregroundStyle(active ? .white : HUDStyle.iconIdle)
            .frame(width: 30, height: 30)
            .background(Circle().fill(active ? HUDStyle.iconHoverBG : .clear))
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
    }
}

private struct NavPopover<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) { content }
            .padding(6)
            .frame(width: 190)
            .background(RoundedRectangle(cornerRadius: 12).fill(HUDStyle.popoverFill))
            .shadow(color: .black.opacity(0.32), radius: 20, y: 10)
    }
}

private struct NavPopoverHeader: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text)
            .font(.manrope(10, .semibold))
            .foregroundStyle(.white.opacity(0.35))
            .padding(.horizontal, 10)
            .padding(.top, 6)
            .padding(.bottom, 3)
    }
}

private struct NavPopoverDivider: View {
    var body: some View {
        Rectangle().fill(.white.opacity(0.10)).frame(height: 1).padding(.vertical, 5)
    }
}

private struct NavPopoverRow: View {
    var title: String
    var icon: MurmurIcon? = nil
    var trailing: String? = nil
    var selected: Bool = false
    var muted: Bool = false
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let icon {
                    MurmurIconView(icon: icon)
                        .frame(width: 13, height: 13)
                        .foregroundStyle(.white.opacity(0.6))
                }
                Text(title)
                    .font(.manrope(12.5, .semibold))
                    .lineLimit(1)
                Spacer(minLength: 8)
                if let trailing {
                    Text(trailing)
                        .font(.manrope(9, .bold))
                        .foregroundStyle(.white.opacity(0.4))
                        .padding(.horizontal, 5).padding(.vertical, 2)
                        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 4))
                }
                if selected {
                    MurmurIconView(icon: .check)
                        .frame(width: 11, height: 11)
                        .foregroundStyle(Palette.accent)
                }
            }
            .foregroundStyle(muted ? .white.opacity(0.5) : .white.opacity(0.85))
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(hovering ? .white.opacity(0.08) : .clear, in: RoundedRectangle(cornerRadius: 7))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

// MARK: - Fixed-dark tooltip

/// `murmurTooltip` (DesignSystem.swift) sits on `Palette.ink`, which flips
/// with app appearance — wrong here, same reasoning as `HUDStyle` above.
private struct MurmurHUDTooltip: ViewModifier {
    let text: String
    @State private var hovering = false

    func body(content: Content) -> some View {
        content
            .onHover { hovering = $0 }
            .overlay(alignment: .top) {
                if hovering {
                    Text(text)
                        .font(.manrope(11, .medium))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .fixedSize()
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(HUDStyle.popoverFill, in: RoundedRectangle(cornerRadius: 6))
                        .shadow(color: .black.opacity(0.3), radius: 8, y: 4)
                        .offset(y: -38)
                        .allowsHitTesting(false)
                        .transition(.opacity)
                }
            }
    }
}

extension View {
    fileprivate func murmurHUDTooltip(_ text: String) -> some View {
        modifier(MurmurHUDTooltip(text: text))
    }
}
