import AppKit
import Speech
import SwiftUI

// MARK: - Pages

enum Page: Hashable {
    case home, insights, ask, notetaker, dictionary, training, snippets, style, transforms
    case templates, scratchpad, appProfiles
    case settings, help, legal

    var label: String {
        switch self {
        case .home: return "Home"
        case .insights: return "Insights"
        case .ask: return "Ask Murmur"
        case .notetaker: return "Notetaker"
        case .dictionary: return "Dictionary"
        case .training: return "Voice Profile"
        case .snippets: return "Snippets"
        case .style: return "Style"
        case .transforms: return "Transforms"
        case .templates: return "Templates"
        case .scratchpad: return "Scratchpad"
        case .appProfiles: return "App Profiles"
        case .settings: return "Settings"
        case .help: return "Help"
        case .legal: return "Legal"
        }
    }
}
