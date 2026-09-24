import AppKit
import Speech
import SwiftUI

// MARK: - Nav Bar HUD
//
// A second floating element, separate from `StatusHUDController`, docked at
// the identical screen spot. The two are mutually exclusive: this one only
// ever exists while the status HUD is hidden (`AppDelegate.updateHUD`'s own
// `state == .hidden` check drives both), and disappears the instant a
// dictation starts.
//
// Unlike the status HUD, this one has to accept mouse events (hover to
// reveal, clicks on its icons), so it can't use `ignoresMouseEvents`. That
// means its panel frame is a real, hit-testable strip at the bottom of the
// screen for as long as it exists at a given size — clicks there go to
// Murmur, not whatever's underneath, *even where the panel is fully
// transparent*. That cost a user with another bottom-docked utility (a
// launcher like Magpie, sitting in the same screen strip): their clicks on
// it were swallowed by empty Murmur space they couldn't even see, because
// the idle panel was already the full 260×54 nav-bar footprint despite
// showing nothing but a two-pixel sliver of pill.
//
// So idle state now gets its own, much smaller tier — a small reveal-pill
// (`restingSize`) that's the only thing hit-testable while nothing's being
// used. Hovering *that* grows the panel to the full pill (`smallSize`),
// which behaves exactly as it always has; hovering an icon within the full
// pill grows it again for a popover (`largeSize`). Three tiers, same
// grow-on-hover mechanism throughout (see `resize`) — this just adds one
// below what already existed, matching the always-visible-small-pill
// pattern Wispr Flow uses for the same reason.

@MainActor
final class NavBarHUDController {
    private var panel: NSPanel?
    private let model = NavBarHUDModel()

    // The idle footprint: just the small reveal-pill itself, plus hover
    // forgiveness — not the full nav bar. See the file header for why this
    // needs to be its own, deliberately tiny tier. Confirmed live that a
    // 12pt-tall target is too thin to actually land a real cursor on —
    // sitting right at the screen's bottom edge, ordinary hand tremor
    // overshoots it, so the reveal never gets a chance to register before
    // the cursor's past it. 20pt gives real forgiveness while staying a
    // small fraction of the old 54pt-tall footprint.
    private static let restingSize = NSSize(width: 64, height: 20)
    private static let smallSize = NSSize(width: 260, height: 54)
    // Sized for the tallest popover ("Quick actions": a Templates header,
    // up to 4 rows, "All templates", a divider, a Transforms header, and
    // its rows) plus headroom for its shadow (20pt blur, 10pt y-offset).
    // The panel's NSHostingView clips to these bounds, so anything shorter
    // or narrower than this just leaves unused transparent margin — but
    // anything that doesn't fit gets its rounded corners and shadow
    // sheared off flat against the edge. Width has to clear the *widest*
    // trigger-icon offset, not just the popover's own 190pt width: each
    // popover centers on the icon that opened it rather than on the panel,
    // and "More" (the rightmost icon) sits ~72pt right of the panel's own
    // centre.
    private static let largeSize = NSSize(width: 400, height: 420)

    init() {
        model.onHoverStateChange = { [weak self] pillHovered, popoverOpen in
            self?.resize(pillHovered: pillHovered, popoverOpen: popoverOpen)
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

    private func resize(pillHovered: Bool, popoverOpen: Bool) {
        guard let panel else { return }
        let size = popoverOpen ? Self.largeSize : (pillHovered ? Self.smallSize : Self.restingSize)
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
        hosting.frame = NSRect(origin: .zero, size: Self.restingSize)

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
/// controller (whose panel-size tier depends on both whether the pill is
/// revealed and whether a popover is open) — no `@Published` state, so no
/// `ObservableObject` needed.
private final class NavBarHUDModel {
    var onHoverStateChange: ((_ pillHovered: Bool, _ popoverOpen: Bool) -> Void)?
}

// MARK: - Content

private enum NavPopoverKind {
    case listen, quick, more
}

/// Fixed dark, white-based colors throughout — matches `StatusHUDView`'s own
/// reasoning: this floats over arbitrary desktop content, not app UI, so it
/// stays legible the same way regardless of Murmur's own light/dark setting.
/// `pillFill`/`popoverFill` are two distinct darks straight from
/// Main.dc.html's HUD artboard, not a shared near-black — solid, not
/// translucent, so legibility never depends on what's behind them.
private enum HUDStyle {
    static let pillFill = Palette.navActivePill
    static let pillBorder = Color.white.opacity(0.14)
    static let popoverFill = Palette.warmInk
    static let iconIdle = Color.white.opacity(0.55)
    static let iconHoverBG = Color.white.opacity(0.10)
}

private struct NavBarHUDView: View {
    @ObservedObject var app: AppDelegate
    let model: NavBarHUDModel

    // The two capsule states this HUD morphs between — defined once so the
    // animated shape and the icon overlay's own fixed size agree exactly.
    // `pillSize` matches the pill content's natural HStack size (5 icons ×
    // 30pt + a 13pt divider + inter-item spacing + `.padding(9)`).
    private static let restingSize = CGSize(width: 48, height: 6)
    private static let pillSize = CGSize(width: 191, height: 48)

    @State private var pillHovered = false
    @State private var openPopover: NavPopoverKind?
    // The icon that opens a popover is a 30pt button; the popover itself
    // renders ~44pt below it (`.offset(y: 44)`), so there's a real gap of
    // dead space between the two. Closing the instant the cursor leaves the
    // icon (as a plain `onHover` would) means the popover vanishes before a
    // cursor moving from the icon down into it ever arrives — you could see
    // "Meeting Notes" or "Summary" but never actually reach and click one.
    // `closeTask` gives that transit a grace window: leaving the icon *or*
    // the popover schedules a close a moment later, but arriving at either
    // one cancels it, so a deliberate move from one to the other survives
    // the gap while an actual mouse-away still closes things promptly.
    @State private var closeTask: Task<Void, Never>?
    // Same reasoning as `closeTask`, one tier further out: the resting
    // target a cursor has to land on to reveal the pill at all is small
    // (64×20) and sits right at the screen's bottom edge, where ordinary
    // hand tremor is enough to cross its boundary several times a second.
    // Toggling `pillHovered` — and therefore resizing the panel — on every
    // one of those crossings never let the pill stay open long enough to
    // read as open at all; it just looked like flicker. Debouncing the
    // *close* side here fixes that the same way `closeTask` already fixes
    // the icon-to-popover gap.
    @State private var pillCloseTask: Task<Void, Never>?
    @State private var useVoiceProfile = Settings.useVoiceProfile
    @State private var supportedLocaleIDs: [String] = []

    // What actually renders the grow/shrink: one capsule whose own frame is
    // animated between `restingSize` and `pillSize`, instead of two
    // differently-shaped views crossfading. A crossfade always reads as two
    // objects handing off, no matter how its scale/anchor is tuned — this
    // is the same shape the whole time, so there's nothing to hand off.
    // Width and height animate on their own staggered springs (see
    // `expand()`/`collapse()`) so it visibly grows tall *then* wide, rather
    // than every dimension changing at once.
    @State private var shapeSize = Self.restingSize
    @State private var iconsVisible = false

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .top) {
                Capsule()
                    .fill(HUDStyle.pillFill)
                    .overlay(Capsule().stroke(HUDStyle.pillBorder, lineWidth: 1))
                    .frame(width: shapeSize.width, height: shapeSize.height)
                    // Main.dc.html's HUD artboard shows a shadow here —
                    // tried, and reverted by request, same as StatusHUDView's
                    // pill: it read as a box under the pill, not the pill
                    // floating.
                pillIcons
                    .opacity(iconsVisible ? 1 : 0)
                    .allowsHitTesting(pillHovered)
            }
            // Pin the ZStack's own width to the current capsule size. Without
            // this the ZStack sizes to its widest child — `pillIcons`, always
            // 191pt even while hidden — so at rest a 191pt stack is centred
            // inside the 64pt panel and its overflow anchoring pushed the
            // 48pt reveal-pill off the panel's centre (visibly right of the
            // notch). Framing to `shapeSize.width` makes the stack track the
            // capsule, so `maxWidth: .infinity` below centres the pill the
            // panel is actually sized for. `pillIcons` still overflows this
            // frame while expanding, which is fine: it is only shown
            // (`iconsVisible`) once the capsule has grown to its full width.
            .frame(width: shapeSize.width)
            .padding(.top, 8)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .contentShape(Rectangle())
        .onHover { inside in
            if inside {
                pillCloseTask?.cancel()
                pillCloseTask = nil
                pillHovered = true
                expand()
                reportHoverState()
            } else {
                pillCloseTask?.cancel()
                pillCloseTask = Task {
                    try? await Task.sleep(nanoseconds: 250_000_000)
                    guard !Task.isCancelled else { return }
                    pillHovered = false
                    openPopover = nil
                    collapse()
                    // The panel/hit-region must not shrink to the resting
                    // tier until the visual collapse has actually finished
                    // — shrinking it the instant `pillHovered` flips false
                    // (the panel resize itself is synchronous, unlike the
                    // ~0.4s `collapse()` animation) means the still-large,
                    // still-animating pill briefly has to render inside an
                    // already-tiny panel: exactly the "snaps to a corner"
                    // glitch this was doing. Waiting out the animation
                    // first means the panel is never smaller than the
                    // content it's currently showing.
                    try? await Task.sleep(nanoseconds: 400_000_000)
                    guard !Task.isCancelled else { return }
                    reportHoverState()
                }
            }
        }
        .onChange(of: openPopover) { _, new in
            // Popover open needs to grow the panel immediately (there's
            // room to spare — `largeSize` was already sized to fit the
            // pill). Popover *closing* while the pill stays hovered only
            // shrinks back to `smallSize`, not all the way to resting, and
            // that popover content doesn't gradually resize the way the
            // pill does — it's just removed — so it has none of the
            // pill's shrink-timing problem and can report immediately too.
            if new != nil { reportHoverState() } else if pillHovered { reportHoverState() }
        }
        .task {
            let locales = await SpeechTranscriber.supportedLocales
            supportedLocaleIDs = sortedByLocalizedName(locales.map { $0.identifier(.bcp47) })
        }
    }

    /// Mirrors `SettingsPage.pickerLocaleIDs`: the languages on offer
    /// depend on the active recognition engine (and, for Whisper/Parakeet,
    /// its selected model), not just Apple's fixed on-device asset list —
    /// see `AppDelegate.supportedLanguageIDs()`.
    private var languageOptions: [String] {
        var ids = sortedByLocalizedName(app.supportedLanguageIDs() ?? supportedLocaleIDs)
        if !ids.contains(app.localeID) { ids.insert(app.localeID, at: 0) }
        return ids
    }

    private func sortedByLocalizedName(_ ids: [String]) -> [String] {
        ids.sorted {
            (Locale.current.localizedString(forIdentifier: $0) ?? $0)
            < (Locale.current.localizedString(forIdentifier: $1) ?? $1)
        }
    }

    /// Grows the capsule from the resting line into the full pill: height
    /// leads, width follows close behind, icons fading in only once the
    /// shape is nearly done widening so they never look stretched — they
    /// just weren't drawn yet. Springs rather than a fixed-duration curve,
    /// per Apple's own motion guidance for this exact kind of move/resize:
    /// critically damped (`dampingFraction: 1`, no bounce — this is a hover
    /// reveal, not a flick with real momentum to carry) and slow enough at
    /// this size to actually read as growth rather than a snap. Springs
    /// also retarget smoothly mid-flight, so rapid hover in/out (this runs
    /// again on every `expand()`/`collapse()` call) never leaves a visible
    /// seam — confirmed this was worth having after `0.4`s on a plain
    /// timing curve still read as too fast and mechanical.
    private func expand() {
        withAnimation(.spring(response: 0.28, dampingFraction: 1)) {
            shapeSize.height = Self.pillSize.height
        }
        withAnimation(.spring(response: 0.4, dampingFraction: 1).delay(0.12)) {
            shapeSize.width = Self.pillSize.width
        }
        withAnimation(.easeOut(duration: 0.22).delay(0.18)) {
            iconsVisible = true
        }
    }

    /// Mirrors `expand()` in reverse — icons fade out first, then width,
    /// then height — so the collapse reads as the same motion undoing
    /// itself rather than a different animation (Apple's own guidance:
    /// enter and exit should share a path).
    private func collapse() {
        withAnimation(.easeIn(duration: 0.12)) {
            iconsVisible = false
        }
        withAnimation(.spring(response: 0.26, dampingFraction: 1)) {
            shapeSize.width = Self.restingSize.width
        }
        withAnimation(.spring(response: 0.26, dampingFraction: 1).delay(0.1)) {
            shapeSize.height = Self.restingSize.height
        }
    }

    /// Fixed at the full pill's own size — it only ever fades in or out
    /// (`iconsVisible`), it never resizes itself. Resizing along with the
    /// capsule underneath is what would make the icons look stretched.
    private var pillIcons: some View {
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
        .frame(width: Self.pillSize.width, height: Self.pillSize.height)
    }

    private func reportHoverState() {
        model.onHoverStateChange?(pillHovered, openPopover != nil)
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
        .onHover { inside in
            if inside { openPopoverNow(.listen) } else { scheduleClose(.listen) }
        }
        .overlay(alignment: .top) {
            if openPopover == .listen {
                NavPopover {
                    NavPopoverHeader("Language")
                    ScrollView {
                        VStack(spacing: 0) {
                            ForEach(languageOptions, id: \.self) { id in
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
                    NavPopoverRow(title: "Parakeet", selected: app.engine == "parakeet") {
                        app.setEngine("parakeet")
                    }
                }
                .offset(y: 44)
                .onHover { inside in
                    if inside { openPopoverNow(.listen) } else { scheduleClose(.listen) }
                }
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
            .onHover { inside in
                if inside { openPopoverNow(.quick) } else { scheduleClose(.quick) }
            }
            .overlay(alignment: .top) {
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
                    .offset(y: 44)
                    .onHover { inside in
                        if inside { openPopoverNow(.quick) } else { scheduleClose(.quick) }
                    }
                }
            }
    }

    // MARK: More — everything else real but unthemed, plus Settings

    private var moreIcon: some View {
        NavIconButton(badgeText: nil, icon: .more, active: openPopover == .more) {}
            .onHover { inside in
                if inside { openPopoverNow(.more) } else { scheduleClose(.more) }
            }
            .overlay(alignment: .top) {
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
                    .offset(y: 44)
                    .onHover { inside in
                        if inside { openPopoverNow(.more) } else { scheduleClose(.more) }
                    }
                }
            }
    }

    private func navigate(to page: Page) {
        app.pendingNavigateToPage = page
        app.showMainWindow()
        openPopover = nil
    }

    /// Hovering the trigger icon *or* the popover itself both route here —
    /// either one arriving cancels a pending `scheduleClose` from the other.
    private func openPopoverNow(_ kind: NavPopoverKind) {
        closeTask?.cancel()
        closeTask = nil
        withAnimation(.murmurEase(0.16)) { openPopover = kind }
    }

    /// Leaving the trigger icon *or* the popover both route here, rather
    /// than closing immediately — see `closeTask`'s own comment for why.
    private func scheduleClose(_ kind: NavPopoverKind) {
        closeTask?.cancel()
        closeTask = Task {
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.murmurEase(0.16)) {
                if openPopover == kind { openPopover = nil }
            }
        }
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
            // `0 20px 40px rgba(20,20,19,.32)` in Main.dc.html.
            .shadow(color: .black.opacity(0.32), radius: 20, y: 20)
            .transition(.opacity.combined(with: .scale(0.96, anchor: .top)))
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
                        .foregroundStyle(Palette.sunset)
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
