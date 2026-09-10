import SwiftUI

// MARK: - Help
//
// Redesigned per the "Main" canvas (Help.dc.html): same `GlassPanelPage`
// shell as the other redesigned pages, warm palette instead of the shared
// dynamic `Palette`. Structurally different from the previous pass, not
// just reskinned — the old page laid every answer out flat, always
// visible; the mockup groups everything into six collapsed category
// tiles (icon, title, one-line summary) that expand to their own list of
// collapsible questions, mirroring the mockup's own two-level `<details>`
// nesting. Tiles are a mutually-exclusive accordion (opening one closes
// whichever else was open, matching the mockup's shared `name="help-cat"`
// on every `<details class="tile">`); the questions inside a tile are
// each independent, same as the old page's own `FAQItem` already worked.
// All copy is unchanged from the previous pass.

struct HelpPage: View {
    @ObservedObject var app: AppDelegate
    @Binding var page: Page
    @State private var openTile: Int?

    var body: some View {
        GlassPanelPage {
            // `ThinScrollView`, not a plain `ScrollView` — see
            // ScratchpadView.swift's own note on why: a bare
            // `.scrollIndicators(.hidden)` doesn't reliably suppress
            // macOS's native scroller by itself.
            ThinScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    header
                    tiles.padding(.top, 18)
                }
            }
        }
        // Applied once, here, rather than per `DisclosureGroup` — this
        // style is what actually moves the row-level chevron to the
        // trailing edge; macOS's own default `DisclosureGroup` puts its
        // indicator on the *leading* side, which put the caret before
        // the icon instead of after the title like the mockup and the
        // tile-level disclosures above it.
        .disclosureGroupStyle(TrailingCaretDisclosureStyle())
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Help")
                .font(.manrope(22, .medium))
                .tracking(-0.33)
                .foregroundStyle(Palette.warmInk)
            Text("Every shortcut and quiet automatic feature, plus what to check when "
                 + "something isn't working.")
                .font(.manrope(12.5))
                .foregroundStyle(Palette.warmInkFaint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var tiles: some View {
        VStack(spacing: 12) {
            tile(
                id: 0, icon: .mic, title: "While you dictate",
                summary: "3 topics · Push-to-talk · Hands-free · Voice commands"
            ) {
                helpRow(icon: .mic, title: "Push-to-talk",
                        detail: "Hold \(app.hotkey.displayName), speak, release — the "
                            + "cleaned-up text lands at your cursor. A tap too short to "
                            + "count as a hold is ignored, so a stray touch never starts "
                            + "a recording.")
                rowDivider
                helpRow(icon: .wave, title: "Hands-free",
                        detail: "Tap \(app.hotkey.displayName) twice quickly to keep "
                            + "recording without holding it down. One more tap stops "
                            + "and transcribes.")
                rowDivider
                helpRow(icon: .edit, title: "Voice commands",
                        detail: "Say “new line” or “new paragraph” mid-dictation to add "
                            + "line breaks. Punctuation is added automatically from your "
                            + "pauses and tone.")
            }

            tile(
                id: 1, icon: .trans, title: "Global shortcuts",
                summary: "2 shortcuts · Polish (⌥1) · Prompt Engineer (⌥2)"
            ) {
                ForEach(Array(Transform.all.enumerated()), id: \.element.id) { index, transform in
                    keycapHelpRow(key: transform.keyLabel, title: transform.name,
                                  detail: transform.description)
                    if index != Transform.all.count - 1 { rowDivider }
                }
            }

            tile(
                id: 2, icon: .refresh, title: "Happens automatically",
                summary: "4 features · Templates · Snippets · Corrections · Voice Profile"
            ) {
                helpRow(icon: .tpl, title: "Templates by voice",
                        detail: "Start a dictation with a template's trigger phrase, "
                            + "like “meeting notes,” and everything you say after it is "
                            + "reshaped into that document.",
                        link: ("Templates", { page = .templates }))
                rowDivider
                helpRow(icon: .snip, title: "Snippets",
                        detail: "Say a saved trigger phrase mid-dictation and it expands "
                            + "into the full saved text. Say it as one phrase — snippets "
                            + "match exact wording.",
                        link: ("Snippets", { page = .snippets }))
                rowDivider
                helpRow(icon: .dict, title: "Learned corrections",
                        detail: "Fix a transcript in History and Murmur learns the "
                            + "misheard-to-intended word for next time. Prefer an exact "
                            + "replacement you set yourself?",
                        link: ("Dictionary", { page = .dictionary }))
                rowDivider
                helpRow(icon: .profile, title: "Voice Profile",
                        detail: "Builds a picture of how you write from your dictation "
                            + "history, and quietly refreshes itself as you dictate "
                            + "more — no setup needed.",
                        link: ("Voice Profile", { page = .training }))
            }

            tile(
                id: 3, icon: .apps, title: "Recognition & per-app behavior",
                summary: "2 topics · Recognition engines · Per-app behavior"
            ) {
                helpRow(icon: .mic, title: "Two recognition engines",
                        detail: "Apple's engine is instant and built into macOS. Whisper "
                            + "starts up slower but is stronger on accents and jargon.",
                        link: ("Settings", { page = .settings }))
                rowDivider
                helpRow(icon: .style, title: "Per-app behavior",
                        detail: "Terminals and code editors get your exact words with "
                            + "zero AI cleanup. Any other app can be given its own tone "
                            + "and its own template — Murmur reshapes what you say "
                            + "differently depending on where you're dictating into.",
                        link: ("App Profiles", { page = .appProfiles }))
            }

            // Privacy opens straight to its one fact — no second click,
            // same as the mockup's own single-item tile.
            tile(
                id: 4, icon: .lock, title: "Privacy",
                summary: "Recognition and rewriting run entirely on this Mac"
            ) {
                HStack(alignment: .top, spacing: 12) {
                    MurmurIconView(icon: .lock)
                        .frame(width: 16, height: 16)
                        .foregroundStyle(Palette.sunsetDeep)
                        .padding(.top, 1)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Private by design")
                            .font(.manrope(13.5, .semibold))
                            .foregroundStyle(Palette.warmInk)
                        Text("Recognition and rewriting both run entirely on this Mac — "
                             + "Apple's on-device speech model, and Apple Intelligence "
                             + "for Polish, Prompt Engineer, Style and voice-triggered "
                             + "templates. No audio or text ever leaves your Mac.")
                            .font(.manrope(12.5))
                            .foregroundStyle(Palette.warmInkSoft)
                            .lineSpacing(3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.vertical, 4)
            }

            tile(
                id: 5, icon: .help, title: "Troubleshooting",
                summary: "4 questions · Clipboard paste · Shortcuts not working · "
                    + "Slow startup · Hotkey issues"
            ) {
                plainHelpRow(
                    question: "Text landed on my clipboard instead of being typed",
                    answer: "Accessibility isn't granted yet, so Murmur can't paste "
                        + "automatically — it copies the result instead. Press ⌘V now, "
                        + "then grant Accessibility so future dictations paste "
                        + "themselves.")
                rowDivider
                plainHelpRow(
                    question: "⌥1 or ⌥2 aren't doing anything",
                    answer: "Polish and Prompt Engineer need Apple Intelligence turned "
                        + "on in System Settings, plus some text selected before you "
                        + "press the shortcut.")
                rowDivider
                plainHelpRow(
                    question: "Dictation feels slow right after switching to Whisper",
                    answer: "The model downloads on first use — up to about 1.6 GB for "
                        + "the largest one. Apple's engine covers your dictation until "
                        + "it's ready, so nothing is lost while you wait.")
                rowDivider
                plainHelpRow(
                    question: "Holding the dictation key does nothing",
                    answer: "The global hotkey needs Accessibility permission to be "
                        + "monitored system-wide. Grant it, then relaunch Murmur once.")
            }
        }
    }

    // MARK: Tile (category-level disclosure)

    /// Hand-rolled rather than a `DisclosureGroup` — the mockup gives the
    /// label and body different horizontal padding and only draws a
    /// divider between them once expanded, which `DisclosureGroup`'s own
    /// single content/label layout doesn't cleanly support.
    private func tile<Content: View>(
        id: Int, icon: MurmurIcon, title: String, summary: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        let isOpen = openTile == id
        return VStack(spacing: 0) {
            Button {
                withAnimation(.murmurEase()) { openTile = isOpen ? nil : id }
            } label: {
                HStack(spacing: 16) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 15, style: .continuous)
                            .fill(Palette.sunsetSoft)
                        MurmurIconView(icon: icon)
                            .frame(width: 24, height: 24)
                            .foregroundStyle(Palette.sunsetDeep)
                    }
                    .frame(width: 52, height: 52)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(title)
                            .font(.manrope(17, .bold))
                            .foregroundStyle(Palette.warmInk)
                        Text(summary)
                            .font(.manrope(12))
                            .foregroundStyle(Palette.warmInkFaint)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    Spacer(minLength: 8)
                    MurmurIconView(icon: .caret)
                        .frame(width: 13, height: 13)
                        .foregroundStyle(Palette.warmInkFainter)
                        .rotationEffect(.degrees(isOpen ? 90 : 0))
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 20)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isOpen {
                VStack(spacing: 0) { content() }
                    .padding(.horizontal, 20)
                    .padding(.top, 4)
                    .padding(.bottom, 18)
                    .overlay(alignment: .top) {
                        Rectangle().fill(Palette.warmRowBorder).frame(height: 1)
                    }
            }
        }
        .background(Color.white, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Palette.warmRowBorder, lineWidth: 1))
    }

    // MARK: Rows (question-level disclosure)

    private var rowDivider: some View {
        Rectangle().fill(Palette.warmRowBorder).frame(height: 1)
    }

    private func helpRow(
        icon: MurmurIcon, title: String, detail: String,
        link: (title: String, action: () -> Void)? = nil
    ) -> some View {
        warmDisclosure(detail: detail, indent: 28, link: link) {
            HStack(spacing: 12) {
                MurmurIconView(icon: icon)
                    .frame(width: 16, height: 16)
                    .foregroundStyle(Palette.sunsetDeep)
                Text(title)
                    .font(.manrope(13.5, .semibold))
                    .foregroundStyle(Palette.warmInk)
                Spacer(minLength: 0)
            }
        }
    }

    private func keycapHelpRow(key: String, title: String, detail: String) -> some View {
        warmDisclosure(detail: detail, indent: 38) {
            HStack(spacing: 10) {
                Keycap(text: key, tint: Palette.warmInk,
                       background: .white, borderColor: Palette.warmRowBorder)
                Text(title)
                    .font(.manrope(13.5, .semibold))
                    .foregroundStyle(Palette.warmInk)
                Spacer(minLength: 0)
            }
        }
    }

    private func plainHelpRow(question: String, answer: String) -> some View {
        warmDisclosure(detail: answer, indent: 0) {
            Text(question)
                .font(.manrope(13.5, .medium))
                .foregroundStyle(Palette.warmInk)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Shared disclosure mechanics behind all three row flavors above —
    /// native `DisclosureGroup`, same mechanism the old page's `FAQItem`
    /// already used, just reskinned and extended with an optional
    /// leading icon/keycap and trailing related-page link. Independent
    /// per row (no shared binding), matching `FAQItem`'s own original
    /// comment: unlike the tiles, these were never meant to be mutually
    /// exclusive.
    private func warmDisclosure<Label: View>(
        detail: String, indent: CGFloat, link: (title: String, action: () -> Void)? = nil,
        @ViewBuilder label: () -> Label
    ) -> some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 6) {
                Text(detail)
                    .font(.manrope(12.5))
                    .foregroundStyle(Palette.warmInkSoft)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                if let link {
                    Button(action: link.action) {
                        Text("\(link.title) →")
                            .font(.manrope(12, .medium))
                            .foregroundStyle(Palette.sunsetDeep)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.leading, indent)
            .padding(.top, 2)
            .padding(.bottom, 10)
        } label: {
            label()
        }
        .padding(.vertical, 6)
    }
}

/// Moves `DisclosureGroup`'s indicator to the trailing edge of its label,
/// matching the mockup's own `<summary>` layout (icon/keycap, title, then
/// the chevron) — macOS's own default style puts it on the leading edge
/// instead, ahead of the label entirely.
private struct TrailingCaretDisclosureStyle: DisclosureGroupStyle {
    func makeBody(configuration: Configuration) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.murmurEase(0.15)) { configuration.isExpanded.toggle() }
            } label: {
                HStack(spacing: 8) {
                    configuration.label
                    Spacer(minLength: 8)
                    MurmurIconView(icon: .caret)
                        .frame(width: 9, height: 9)
                        .foregroundStyle(Palette.warmInkFainter)
                        .rotationEffect(.degrees(configuration.isExpanded ? 90 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if configuration.isExpanded {
                configuration.content
            }
        }
    }
}
