import AppKit
import SwiftUI

// MARK: - App Profiles
//
// Redesigned per the "Main" canvas (AppProfiles.dc.html): same
// `GlassPanelPage` shell as the other redesigned pages, warm palette
// instead of the shared dynamic `Palette`. Functionally unchanged — one
// page answering one question: "what happens when I dictate into this
// app?" Style and Templates each used to own half the answer on separate
// pages, with an undocumented rule that the template half silently won.
// Both halves still live on one row here, and the row still spells out
// the result.

struct AppProfilesPage: View {
    @ObservedObject var app: AppDelegate
    @Binding var page: Page

    @State private var profiles: [String: AppProfile] = AppProfileStore.profiles
    @State private var templates: [NoteTemplate] = NoteTemplateStore.all()
    @State private var addingRule = false
    @State private var draftBundleID = ""
    /// Snapshotted when the add row opens rather than read in `body`:
    /// `NSWorkspace.runningApplications` scans every process, and the add
    /// row reads the list three times per render.
    @State private var runningApps: [(bundleID: String, name: String)] = []
    /// Lifted out of `ProfileRow` (rather than a local `@State` there) so a
    /// hovering row can also suppress the hairline divider on *both* of its
    /// sides — see `profileList`'s own note on why.
    @State private var hoveredBundleID: String?

    var body: some View {
        GlassPanelPage {
            // `ThinScrollView`, not a plain `ScrollView` — see
            // ScratchpadView.swift's own note on why: a bare
            // `.scrollIndicators(.hidden)` doesn't reliably suppress
            // macOS's native scroller by itself.
            ThinScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    header

                    tipBanner("Everything without a profile uses your default tone "
                              + "(\(StyleSettings.defaultStyle.displayName)) and no template. "
                              + "A profile can set either half, or both.")
                        .padding(.top, 18)

                    if let note = app.rewriteEngine.availabilityNote {
                        tipBanner(note).padding(.top, 12)
                    }

                    profileList
                        .padding(.top, 16)

                    if addingRule {
                        addRow.padding(.top, 10)
                    } else {
                        addProfileButton.padding(.top, 10)
                    }

                    relatedLink
                        .padding(.top, 14)
                }
            }
        }
        .onAppear { templates = NoteTemplateStore.all() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("App Profiles")
                .font(.manrope(22, .medium))
                .tracking(-0.33)
                .foregroundStyle(Palette.warmInk)
            Text("What Murmur does when you dictate into a particular app.")
                .font(.manrope(12.5))
                .foregroundStyle(Palette.warmInkFaint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func tipBanner(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            MurmurIconView(icon: .help)
                .frame(width: 13, height: 13)
                .foregroundStyle(Palette.warmInkSoft)
                .padding(.top, 1)
            Text(text)
                .font(.manrope(12.5))
                .lineSpacing(3)
                .foregroundStyle(Palette.warmInkSoft)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    @ViewBuilder
    private var profileList: some View {
        if profiles.isEmpty && !addingRule {
            Text("No app profiles yet — every app uses your defaults.")
                .font(.manrope(12.5))
                .italic()
                .foregroundStyle(Palette.warmInkFaint)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        } else {
            let sorted = profiles.sorted { $0.value.appName < $1.value.appName }
            VStack(spacing: 0) {
                ForEach(Array(sorted.enumerated()), id: \.element.key) { index, item in
                    profileRow(bundleID: item.key, profile: item.value)
                    // A divider sits on the boundary between two different
                    // row backgrounds, so it can never be color-matched
                    // away on both sides at once once either neighbor is
                    // hover-tinted — omitting it there (rather than always
                    // showing it) is the only fully seamless option; it
                    // stays everywhere else, between two plain rows.
                    if index != sorted.count - 1 {
                        let nextKey = sorted[index + 1].key
                        if hoveredBundleID != item.key && hoveredBundleID != nextKey {
                            Rectangle().fill(Palette.warmRowBorder).frame(height: 1)
                        }
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
    }

    // MARK: Rows

    private func profileRow(bundleID: String, profile: AppProfile) -> some View {
        ProfileRow(
            profile: profile,
            templates: templates,
            summary: summary(for: profile),
            isHovering: hoveredBundleID == bundleID,
            onHoverChange: { inside in
                hoveredBundleID = inside
                    ? bundleID
                    : (hoveredBundleID == bundleID ? nil : hoveredBundleID)
            },
            onChange: { updated in
                // Single-owner: assigning a hotkey slot already held by a
                // different profile silently takes it from that profile —
                // matches the store's own house style of silent conflict
                // handling (e.g. pruning empties below) rather than a
                // blocking-validation UI.
                if let slot = updated.hotkeySlot {
                    for key in profiles.keys where key != bundleID {
                        if profiles[key]?.hotkeySlot == slot {
                            profiles[key]?.hotkeySlot = nil
                        }
                    }
                }
                profiles[bundleID] = updated
                AppProfileStore.profiles = profiles
                // The store prunes profiles that no longer do anything;
                // mirror that here so the row disappears with it.
                if updated.isEmpty { profiles.removeValue(forKey: bundleID) }
            },
            onDelete: {
                profiles.removeValue(forKey: bundleID)
                AppProfileStore.profiles = profiles
            })
    }

    private var addProfileButton: some View {
        Button {
            draftBundleID = ""
            runningApps = RunningApps.list
            addingRule = true
        } label: {
            HStack(spacing: 8) {
                MurmurIconView(icon: .plus).frame(width: 13, height: 13)
                Text("Add an app profile").font(.manrope(12.5, .semibold))
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

    private var addRow: some View {
        HStack(spacing: 8) {
            WarmFieldSelect(
                options: [""] + runningApps.map(\.bundleID),
                label: { id in
                    id.isEmpty
                        ? "Choose a running app…"
                        : (runningApps.first { $0.bundleID == id }?.name ?? id)
                },
                selection: $draftBundleID)
            IconButton(icon: .check, help: "Save") {
                if let appInfo = runningApps.first(where: { $0.bundleID == draftBundleID }) {
                    // Starts with the current default tone made explicit, so
                    // the new row does something visible immediately.
                    profiles[appInfo.bundleID] = AppProfile(
                        appName: appInfo.name,
                        style: StyleSettings.defaultStyle,
                        templateID: nil)
                    AppProfileStore.profiles = profiles
                }
                addingRule = false
                draftBundleID = ""
            }
            .disabled(draftBundleID.isEmpty)
            IconButton(icon: .plus, rotated: true, help: "Cancel") {
                addingRule = false
                draftBundleID = ""
            }
            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 9)
    }

    private var relatedLink: some View {
        HStack(spacing: 4) {
            Text("Want to reshape text on demand instead of automatically?")
                .font(.manrope(12))
                .foregroundStyle(Palette.warmInkSoft)
            Button { page = .transforms } label: {
                Text("Transforms")
                    .font(.manrope(12, .medium))
                    .foregroundStyle(Palette.sunsetDeep)
            }
            .buttonStyle(.plain)
            Text("run when you trigger them.")
                .font(.manrope(12))
                .foregroundStyle(Palette.warmInkSoft)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    /// Plain-language statement of what this profile actually produces —
    /// the thing the old two-page split made impossible to see.
    private func summary(for profile: AppProfile) -> String {
        let templateName = profile.templateID.flatMap { id in
            templates.first { $0.id == id }?.name
        }
        let toneName = profile.style?.displayName

        switch (templateName, toneName) {
        case (nil, nil):
            return "Uses your defaults"
        case (nil, let tone?):
            return "\(tone) tone"
        case (let template?, nil):
            return "\(template) structure, default tone"
        case (let template?, let tone?):
            return "\(template) structure, \(tone) tone"
        }
    }
}

// MARK: - Row

private struct ProfileRow: View {
    let profile: AppProfile
    let templates: [NoteTemplate]
    let summary: String
    let isHovering: Bool
    let onHoverChange: (Bool) -> Void
    let onChange: (AppProfile) -> Void
    let onDelete: () -> Void

    /// `nil` first so "inherit the default" is the top choice rather than
    /// something buried under five concrete tones.
    private var styleOptions: [WritingStyle?] {
        [nil] + WritingStyle.allCases.map { Optional($0) }
    }

    private var templateOptions: [UUID?] {
        [nil] + templates.map { Optional($0.id) }
    }

    private var hotkeyOptions: [ProfileHotkeySlot?] {
        [nil] + ProfileHotkeySlot.allCases.map { Optional($0) }
    }

    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text(profile.appName)
                    .font(.manrope(13, .semibold))
                    .foregroundStyle(Palette.warmInk)
                Text(summary)
                    .font(.manrope(11))
                    .foregroundStyle(Palette.warmInkSoft)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            WarmFieldSelect(
                options: styleOptions,
                label: { $0?.displayName ?? "Default tone" },
                selection: Binding(
                    get: { profile.style },
                    set: { newValue in
                        var updated = profile
                        updated.style = newValue
                        onChange(updated)
                    }))

            WarmFieldSelect(
                options: templateOptions,
                label: { id in
                    guard let id else { return "No template" }
                    return templates.first { $0.id == id }?.name ?? "No template"
                },
                selection: Binding(
                    get: { profile.templateID },
                    set: { newValue in
                        var updated = profile
                        updated.templateID = newValue
                        onChange(updated)
                    }))

            WarmFieldSelect(
                options: hotkeyOptions,
                label: { $0?.label ?? "No hotkey" },
                selection: Binding(
                    get: { profile.hotkeySlot },
                    set: { newValue in
                        var updated = profile
                        updated.hotkeySlot = newValue
                        onChange(updated)
                    }))

            IconButton(icon: .trash, size: 22, iconSize: 12, help: "Delete", action: onDelete)
                .opacity(isHovering ? 1 : 0)
                .animation(.easeOut(duration: 0.1), value: isHovering)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 13)
        .background(
            RoundedRectangle(cornerRadius: Radius.sm)
                .fill(isHovering ? Palette.warmRowBorder.opacity(0.55) : Color.clear))
        // See HomeView.swift's historyRow for why this is needed: a .clear
        // background makes SwiftUI treat the row's empty space as outside
        // the hoverable region until this forces the whole padded frame to
        // count, regardless of what's actually drawn there.
        .contentShape(Rectangle())
        .onHover(perform: onHoverChange)
    }
}

// MARK: - Warm field select
//
// Same `Button` + `.popover` mechanics as the shared `FieldSelect` (Menu
// combined with `.menuStyle(.borderlessButton)` silently drops the custom
// background/border on this build — see that type's own note), reskinned
// in warm tokens throughout, including the popover's own list — the
// shared version bakes `Palette.ink`/`.cardHover` into that list with no
// override, so restyling only the trigger would leave a mismatched popover.

private struct WarmFieldSelect<T: Hashable>: View {
    let options: [T]
    let label: (T) -> String
    @Binding var selection: T
    @State private var isOpen = false

    var body: some View {
        Button {
            isOpen = true
        } label: {
            HStack(spacing: 6) {
                Text(label(selection))
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9, weight: .semibold))
            }
            .font(.manrope(12, .medium))
            .foregroundStyle(Palette.warmInkSoft)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.white, in: RoundedRectangle(cornerRadius: Radius.sm))
            .overlay(RoundedRectangle(cornerRadius: Radius.sm).stroke(Palette.warmRowBorder, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .fixedSize()
        .popover(isPresented: $isOpen, arrowEdge: .bottom) {
            WarmFieldSelectList(options: options, label: label, selection: $selection, isOpen: $isOpen)
        }
    }
}

private struct WarmFieldSelectList<T: Hashable>: View {
    let options: [T]
    let label: (T) -> String
    @Binding var selection: T
    @Binding var isOpen: Bool
    @State private var hovered: T?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(options, id: \.self) { option in
                Button {
                    selection = option
                    isOpen = false
                } label: {
                    Text(label(option))
                        .font(.manrope(12, .medium))
                        .foregroundStyle(option == selection ? Palette.warmInk : Palette.warmInkSoft)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(hovered == option ? Palette.warmRowBorder : Color.clear)
                }
                .buttonStyle(.plain)
                .onHover { inside in hovered = inside ? option : nil }
            }
        }
        .padding(.vertical, 4)
        .frame(minWidth: 160)
        .environment(\.colorScheme, .light)
    }
}

// MARK: - Shared

/// The user-facing apps currently running, for picking one to profile.
enum RunningApps {
    static var list: [(bundleID: String, name: String)] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .compactMap { application in
                guard let bundleID = application.bundleIdentifier,
                      let name = application.localizedName else { return nil }
                return (bundleID, name)
            }
            .sorted { $0.name < $1.name }
    }
}
