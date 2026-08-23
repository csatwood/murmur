import SwiftUI

// MARK: - Help
//
// Grouped by what you're doing, with the real global shortcuts, the
// features that happen automatically, and a troubleshooting FAQ — the old
// page listed three lines.

struct HelpPage: View {
    @ObservedObject var app: AppDelegate
    @Binding var page: Page

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PageHeader(
                title: "Help",
                subtitle: "Every shortcut and quiet automatic feature, plus what to check "
                    + "when something isn't working.")

            SectionHead(title: "While you dictate")
            Card(flat: true) {
                helpItem(.mic, "Push-to-talk",
                         "Hold \(app.hotkey.displayName), speak, release — the cleaned-up text "
                         + "lands at your cursor. A tap too short to count as a hold is ignored, "
                         + "so a stray touch never starts a recording.")
                divider
                helpItem(.wave, "Hands-free",
                         "Tap \(app.hotkey.displayName) twice quickly to keep recording without "
                         + "holding it down. One more tap stops and transcribes.")
                divider
                helpItem(.edit, "Voice commands",
                         "Say “new line” or “new paragraph” mid-dictation to add line breaks. "
                         + "Punctuation is added automatically from your pauses and tone.")
            }

            SectionHead(title: "Global shortcuts", trailing: "any app, not just Murmur")
            Card(flat: true) {
                ForEach(Transform.all) { transform in
                    ShortcutRow(key: transform.keyLabel,
                                text: "\(transform.name) — \(transform.description)")
                    if transform.id != Transform.all.last?.id { divider }
                }
            }

            SectionHead(title: "Happens automatically")
            Card(flat: true) {
                helpItem(.tpl, "Templates by voice",
                         "Start a dictation with a template's trigger phrase, like “meeting notes,” "
                         + "and everything you say after it is reshaped into that document.",
                         link: ("Templates", { page = .templates }))
                divider
                helpItem(.snip, "Snippets",
                         "Say a saved trigger phrase mid-dictation and it expands into the full "
                         + "saved text. Say it as one phrase — snippets match exact wording.",
                         link: ("Snippets", { page = .snippets }))
                divider
                helpItem(.dict, "Learned corrections",
                         "Fix a transcript in History and Murmur learns the misheard-to-intended "
                         + "word for next time. Prefer an exact replacement you set yourself?",
                         link: ("Dictionary", { page = .dictionary }))
                divider
                helpItem(.profile, "Voice Profile",
                         "Builds a picture of how you write from your dictation history, and "
                         + "quietly refreshes itself as you dictate more — no setup needed.",
                         link: ("Voice Profile", { page = .training }))
            }

            SectionHead(title: "Recognition & per-app behavior")
            Card(flat: true) {
                helpItem(.mic, "Two recognition engines",
                         "Apple's engine is instant and built into macOS. Whisper starts up slower "
                         + "but is stronger on accents and jargon.",
                         link: ("Settings", { page = .settings }))
                divider
                helpItem(.style, "Per-app behavior",
                         "Terminals and code editors get your exact words with zero AI cleanup. "
                         + "Any other app can be given its own tone and its own template — "
                         + "Murmur reshapes what you say differently depending on where you're "
                         + "dictating into.",
                         link: ("App Profiles", { page = .appProfiles }))
            }

            SectionHead(title: "Privacy")
            Card(flat: true) {
                helpItem(.lock, "Private by design",
                         "Recognition and rewriting both run entirely on this Mac — Apple's "
                         + "on-device speech model, and Apple Intelligence for Polish, Prompt "
                         + "Engineer, Style and voice-triggered templates. No audio or text ever "
                         + "leaves your Mac.")
            }

            SectionHead(title: "Troubleshooting")
            Card(flat: true) {
                FAQItem(
                    question: "Text landed on my clipboard instead of being typed",
                    answer: "Accessibility isn't granted yet, so Murmur can't paste automatically — "
                        + "it copies the result instead. Press ⌘V now, then grant Accessibility so "
                        + "future dictations paste themselves.")
                divider
                FAQItem(
                    question: "⌥1 or ⌥2 aren't doing anything",
                    answer: "Polish and Prompt Engineer need Apple Intelligence turned on in System "
                        + "Settings, plus some text selected before you press the shortcut.")
                divider
                FAQItem(
                    question: "Dictation feels slow right after switching to Whisper",
                    answer: "The model downloads on first use — up to about 1.6 GB for the largest "
                        + "one. Apple's engine covers your dictation until it's ready, so nothing "
                        + "is lost while you wait.")
                divider
                FAQItem(
                    question: "Holding the dictation key does nothing",
                    answer: "The global hotkey needs Accessibility permission to be monitored "
                        + "system-wide. Grant it, then relaunch Murmur once.")
            }
        }
    }

    private var divider: some View {
        Rectangle().fill(Palette.border).frame(height: 1)
    }

    private func helpItem(
        _ icon: MurmurIcon, _ title: String, _ detail: String,
        link: (title: String, action: () -> Void)? = nil
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            MurmurIconView(icon: icon)
                .frame(width: 18, height: 18)
                .foregroundStyle(Palette.accentText)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.manrope(13.5, .medium))
                    .foregroundStyle(Palette.ink)
                Text(detail)
                    .font(.manrope(12.5))
                    .foregroundStyle(Palette.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
                if let link {
                    Button(action: link.action) {
                        Text("\(link.title) →")
                            .font(.manrope(12, .medium))
                            .foregroundStyle(Palette.accentText)
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 2)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 11)
    }
}
