import AppKit
import SwiftUI

// MARK: - App Profiles
//
// One page answering one question: "what happens when I dictate into this
// app?" Style and Templates each used to own half the answer on separate
// pages, with an undocumented rule that the template half silently won.
// Both halves now live on one row, and the row spells out the result.

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

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PageHeader(
                title: "App Profiles",
                subtitle: "What Murmur does when you dictate into a particular app.")

            PageTip(text: "Everything without a profile uses your default tone "
                    + "(\(StyleSettings.defaultStyle.displayName)) and no template. "
                    + "A profile can set either half, or both.")
                .padding(.bottom, 16)

            if let note = app.rewriteEngine.availabilityNote {
                PageTip(text: note).padding(.bottom, 12)
            }

            if profiles.isEmpty && !addingRule {
                emptyState
            } else {
                let sorted = profiles.sorted { $0.value.appName < $1.value.appName }
                VStack(spacing: 0) {
                    ForEach(Array(sorted.enumerated()), id: \.element.key) { index, item in
                        profileRow(bundleID: item.key, profile: item.value)
                        if index != sorted.count - 1 {
                            Rectangle().fill(Palette.border).frame(height: 1)
                        }
                    }
                }
            }

            if addingRule {
                addRow
            } else {
                AddRowButton(title: "Add an app profile") {
                    draftBundleID = ""
                    runningApps = RunningApps.list
                    addingRule = true
                }
                .padding(.top, 8)
            }

            RelatedLink(
                prefix: "Want to reshape text on demand instead of automatically?",
                linkTitle: "Transforms",
                suffix: "run when you trigger them."
            ) { page = .transforms }
        }
        .onAppear { templates = NoteTemplateStore.all() }
    }

    private var emptyState: some View {
        Text("No app profiles yet — every app uses your defaults.")
            .font(.manrope(12.5))
            .italic()
            .foregroundStyle(Palette.inkFaint)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
    }

    // MARK: Rows

    private func profileRow(bundleID: String, profile: AppProfile) -> some View {
        ProfileRow(
            profile: profile,
            templates: templates,
            summary: summary(for: profile),
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

    private var addRow: some View {
        HStack(spacing: 8) {
            FieldSelect(
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
    let onChange: (AppProfile) -> Void
    let onDelete: () -> Void

    @State private var hovering = false

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
                    .foregroundStyle(Palette.ink)
                Text(summary)
                    .font(.manrope(11))
                    .foregroundStyle(Palette.inkSoft)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            FieldSelect(
                options: styleOptions,
                label: { $0?.displayName ?? "Default tone" },
                selection: Binding(
                    get: { profile.style },
                    set: { newValue in
                        var updated = profile
                        updated.style = newValue
                        onChange(updated)
                    }))

            FieldSelect(
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

            FieldSelect(
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
                .opacity(hovering ? 1 : 0)
                .animation(.easeOut(duration: 0.1), value: hovering)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 11)
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
