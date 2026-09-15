import Foundation

/// What Insights' "Usage by category" card groups dictation targets into.
/// Deliberately not a literal copy of Wispr Flow's own bucket set
/// (AI Prompts / Documents / Work messages / Email / Other) — Murmur's own
/// users skew toward dictating into code, going by this app's own recent
/// history (Xcode, Claude, terminals), so Code editors gets its own
/// category rather than folding into "Documents" the way Wispr's does.
enum UsageCategory: String, CaseIterable, Identifiable {
    case aiAssistants = "AI assistants"
    case codeEditors = "Code editors"
    case messaging = "Messaging"
    case email = "Email"
    case notesAndDocs = "Notes & docs"
    case other = "Other"

    var id: String { rawValue }

    var icon: MurmurIcon {
        switch self {
        case .aiAssistants: return .ask
        case .codeEditors: return .trans
        case .messaging: return .lines
        case .email: return .tpl
        case .notesAndDocs: return .dict
        case .other: return .apps
        }
    }
}

/// Bundle ID → category, for grouping `HistoryEntry.targetBundleID`.
/// A starting set of the apps this kind of user most plausibly dictates
/// into, not an exhaustive registry — anything unrecognized (and anything
/// with no `targetBundleID` at all, e.g. history from before that field
/// existed) falls into `.other` rather than being guessed at.
enum AppCategoryClassifier {
    private static let categories: [String: UsageCategory] = [
        // AI assistants
        "com.anthropic.claudefordesktop": .aiAssistants,
        "com.openai.chat": .aiAssistants,
        "com.openai.codex": .aiAssistants,
        "com.electron.chatgpt": .aiAssistants,

        // Code editors / terminals
        "com.apple.dt.Xcode": .codeEditors,
        "com.microsoft.VSCode": .codeEditors,
        "com.todesktop.230313mzl4w4u92": .codeEditors, // Cursor
        "com.apple.Terminal": .codeEditors,
        "com.googlecode.iterm2": .codeEditors,
        "dev.warp.Warp-Stable": .codeEditors,
        "com.github.atom": .codeEditors,
        "com.jetbrains.intellij": .codeEditors,

        // Messaging
        "com.tinyspeck.slackmacgap": .messaging,
        "com.microsoft.teams2": .messaging,
        "com.apple.MobileSMS": .messaging,
        "net.whatsapp.WhatsApp": .messaging,
        "com.hnc.Discord": .messaging,
        "us.zoom.xos": .messaging,
        "com.readdle.spark": .messaging,

        // Email
        "com.apple.mail": .email,
        "com.microsoft.Outlook": .email,
        "com.google.Chrome.app.fmgjjmmmlfnkbppncabfkddbjimcfncm": .email, // Gmail (installed as a Chrome PWA)

        // Notes & docs
        "com.apple.Notes": .notesAndDocs,
        "com.apple.TextEdit": .notesAndDocs,
        "com.apple.iWork.Pages": .notesAndDocs,
        "com.microsoft.Word": .notesAndDocs,
        "notion.id": .notesAndDocs,
        "md.obsidian": .notesAndDocs,
        "com.local.murmur": .notesAndDocs, // Murmur's own Scratchpad/Ask
        "local.murmur": .notesAndDocs,
    ]

    static func category(forBundleID bundleID: String?) -> UsageCategory {
        guard let bundleID else { return .other }
        return categories[bundleID] ?? .other
    }
}
