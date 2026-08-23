import AppKit
import SwiftUI

// MARK: - Style
//
// The design added a live preview so you can see what each tone actually
// does to your text before committing — the old page was five unexplained
// labels. This page now owns only the *global* default; per-app tone moved
// to App Profiles, where it sits next to the app's template instead of
// being configured on a separate screen from it.

struct StylePage: View {
    @ObservedObject var app: AppDelegate
    @Binding var page: Page
    @State private var defaultStyle: WritingStyle = StyleSettings.defaultStyle

    /// The one sample sentence every tone is previewed against, so the
    /// differences between them are directly comparable.
    private let sourceText =
        "um so i think we should send them the updated file when you get a chance"

    private func preview(for style: WritingStyle) -> String {
        switch style {
        case .none:
            return "So I think we should send them the updated file when you get a chance."
        case .casual:
            return "Think we should send them the updated file when you get a chance."
        case .formal:
            return "I believe we should send them the updated file at your earliest convenience."
        case .veryCasual:
            return "Prob should send them the updated file whenever!"
        case .raw:
            return sourceText
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PageHeader(title: "Style", subtitle: "Tone, by default and per app.")

            PageTip(text: "\(defaultStyle.displayName) is your default tone everywhere — "
                    + "an app with its own profile uses that instead.")
                .padding(.bottom, 16)

            SegmentedPicker(
                options: WritingStyle.allCases,
                label: { $0.displayName },
                selection: $defaultStyle)
                .onChange(of: defaultStyle) { _, newValue in
                    StyleSettings.defaultStyle = newValue
                }

            Card {
                Text("SAMPLE, UNPROCESSED")
                    .font(.manrope(11, .medium))
                    .kerning(0.7)
                    .foregroundStyle(Palette.inkFaint)
                Text("\"\(sourceText)\"")
                    .font(.manrope(12.5))
                    .italic()
                    .foregroundStyle(Palette.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 6)
                Divider().overlay(Palette.border).padding(.vertical, 14)
                Text("PREVIEW — \(defaultStyle.displayName.uppercased())")
                    .font(.manrope(11, .medium))
                    .kerning(0.7)
                    .foregroundStyle(Palette.inkFaint)
                Text(preview(for: defaultStyle))
                    .font(.manrope(14))
                    .foregroundStyle(Palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 6)
            }
            .padding(.top, 16)

            if defaultStyle == .raw {
                PageTip(text: "Raw skips all cleanup — no capitalization, punctuation, "
                        + "spoken commands, or rewriting. Best for terminals and code editors.")
                    .padding(.top, 12)
            }

            if let note = app.rewriteEngine.availabilityNote {
                PageTip(text: note).padding(.top, 12)
            }

            RelatedLink(
                prefix: "Need a different tone in one particular app?",
                linkTitle: "App Profiles",
                suffix: "override this per app."
            ) { page = .appProfiles }
        }
    }
}

