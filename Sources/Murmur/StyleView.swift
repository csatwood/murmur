import AppKit
import SwiftUI

// MARK: - Style
//
// Redesigned per the "Main" canvas (Style.dc.html): same `GlassPanelPage`
// shell as the other redesigned pages, warm palette instead of the shared
// dynamic `Palette`. Functionally unchanged from the previous pass — this
// page still owns only the *global* default; per-app tone lives on App
// Profiles, next to that app's own template.

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
        GlassPanelPage {
            // `ThinScrollView`, not a plain `ScrollView` — see
            // ScratchpadView.swift's own note on why: a bare
            // `.scrollIndicators(.hidden)` doesn't reliably suppress
            // macOS's native scroller by itself.
            ThinScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    header

                    tipBanner("\(defaultStyle.displayName) is your default tone everywhere — "
                              + "an app with its own profile uses that instead.")
                        .padding(.top, 18)

                    segmentedPicker
                        .padding(.top, 16)

                    sampleCard
                        .padding(.top, 16)

                    if defaultStyle == .raw {
                        tipBanner("Raw skips all cleanup — no capitalization, punctuation, "
                                  + "spoken commands, or rewriting. Best for terminals and code editors.")
                            .padding(.top, 12)
                    }

                    if let note = app.rewriteEngine.availabilityNote {
                        tipBanner(note)
                            .padding(.top, 12)
                    }

                    relatedLink
                        .padding(.top, 14)
                }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Style")
                .font(.manrope(22, .medium))
                .tracking(-0.33)
                .foregroundStyle(Palette.warmInk)
            Text("Tone, by default and per app.")
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

    /// A borderless pill-in-pill control, unlike the shared `SegmentedPicker`
    /// (divided segments, square corners) that Settings still uses — the
    /// mockup's own tone switcher is a single rounded capsule with only the
    /// selected segment filled, no dividers between the others.
    private var segmentedPicker: some View {
        HStack(spacing: 2) {
            ForEach(WritingStyle.allCases) { style in
                Button {
                    defaultStyle = style
                    StyleSettings.defaultStyle = style
                } label: {
                    Text(style.displayName)
                        .font(.manrope(12, style == defaultStyle ? .semibold : .regular))
                        .foregroundStyle(style == defaultStyle ? .white : Palette.warmInkSoft)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 7)
                        .background {
                            if style == defaultStyle {
                                Capsule().fill(Palette.sunset)
                            }
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(Color.white, in: Capsule())
        .overlay(Capsule().stroke(Palette.warmRowBorder, lineWidth: 1))
        .fixedSize()
    }

    private var sampleCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("SAMPLE, UNPROCESSED")
                .font(.manrope(11, .medium))
                .kerning(0.7)
                .foregroundStyle(Palette.warmInkFaint)
            Text("\"\(sourceText)\"")
                .font(.manrope(12.5))
                .italic()
                .foregroundStyle(Palette.warmInkSoft)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 6)
            Rectangle().fill(Palette.warmRowBorder).frame(height: 1).padding(.vertical, 14)
            Text("PREVIEW — \(defaultStyle.displayName.uppercased())")
                .font(.manrope(11, .medium))
                .kerning(0.7)
                .foregroundStyle(Palette.warmInkFaint)
            Text(preview(for: defaultStyle))
                .font(.manrope(14))
                .foregroundStyle(Palette.warmInk)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 6)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 20)
        .frame(maxWidth: .infinity, alignment: .leading)
        // No drop shadow, by request — same call as every other white card
        // floating on the glass panel in this redesign.
        .background(Color.white, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var relatedLink: some View {
        HStack(spacing: 4) {
            Text("Need a different tone in one particular app?")
                .font(.manrope(12))
                .foregroundStyle(Palette.warmInkSoft)
            Button { page = .appProfiles } label: {
                Text("App Profiles")
                    .font(.manrope(12, .medium))
                    .foregroundStyle(Palette.sunsetDeep)
            }
            .buttonStyle(.plain)
            Text("override this per app.")
                .font(.manrope(12))
                .foregroundStyle(Palette.warmInkSoft)
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}
