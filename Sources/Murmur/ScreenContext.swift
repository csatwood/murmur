import ApplicationServices
import AppKit

/// Reads on-screen text from whichever app is frontmost, via the
/// Accessibility API — the same local mechanism `TextInserter` already
/// uses to paste, so no new permission beyond what Murmur already
/// requires. This is the local, on-device analog of what Wispr Flow calls
/// "accessibility-text context": reading whatever's already visible in
/// the app you're dictating into, so Developer-mode vocabulary biasing
/// can adapt to the actual file/terminal/chat on screen instead of a
/// static word list.
///
/// DIAGNOSTIC ONLY for now — logs what it can actually extract from real
/// apps (Claude Desktop's terminal, specifically, since that's the
/// motivating case) before any extraction/biasing pipeline is built on
/// top of it. First pass found 282 elements but zero text via
/// `kAXValueAttribute`/`kAXSelectedTextAttribute` alone — this version
/// tallies roles and dumps every attribute name+value on a sample of
/// elements, to find out *why*, rather than guess.
enum ScreenContext {
    struct Snapshot {
        var texts: [String]
        var elementsVisited: Int
        var elapsedMs: Double
        var roleCounts: [String: Int]
        /// Up to a handful of elements' full attribute dumps, for whichever
        /// roles looked most likely to carry text but yielded nothing from
        /// the plain value/selected-text check.
        var sampleDumps: [String]
    }

    static func extractVisibleText(
        from app: NSRunningApplication, maxDepth: Int = 16, maxElements: Int = 2000
    ) -> Snapshot {
        let start = Date()
        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        var collected: [String] = []
        var seen = Set<String>()
        var visited = 0
        var roleCounts: [String: Int] = [:]
        var sampleDumps: [String] = []

        func record(_ text: String?) {
            guard let text, !text.isEmpty, !seen.contains(text) else { return }
            seen.insert(text)
            collected.append(text)
        }

        func role(of element: AXUIElement) -> String {
            var value: CFTypeRef?
            guard AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &value) == .success,
                  let role = value as? String
            else { return "?" }
            return role
        }

        func dumpAllAttributes(_ element: AXUIElement) -> String {
            var names: CFArray?
            guard AXUIElementCopyAttributeNames(element, &names) == .success,
                  let attributeNames = names as? [String]
            else { return "(no attribute names)" }
            var parts: [String] = []
            for name in attributeNames {
                var value: CFTypeRef?
                let status = AXUIElementCopyAttributeValue(element, name as CFString, &value)
                if status == .success, let value {
                    let description = String(describing: value)
                    parts.append("\(name)=\(description.prefix(120))")
                }
            }
            return parts.joined(separator: " | ")
        }

        func walk(_ element: AXUIElement, depth: Int) {
            guard depth <= maxDepth, visited < maxElements else { return }
            visited += 1

            let elementRole = role(of: element)
            roleCounts[elementRole, default: 0] += 1

            var value: CFTypeRef?
            if AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &value) == .success {
                record(value as? String)
            }
            var selected: CFTypeRef?
            if AXUIElementCopyAttributeValue(element, kAXSelectedTextAttribute as CFString, &selected) == .success {
                record(selected as? String)
            }
            var title: CFTypeRef?
            if AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &title) == .success {
                record(title as? String)
            }
            var desc: CFTypeRef?
            if AXUIElementCopyAttributeValue(element, kAXDescriptionAttribute as CFString, &desc) == .success {
                record(desc as? String)
            }

            // Sample a handful of text-plausible-but-empty-so-far roles for
            // a full attribute dump, so we can see what's actually there.
            let textPlausibleRoles: Set<String> = [
                "AXStaticText", "AXTextArea", "AXTextField", "AXWebArea",
                "AXGroup", "AXScrollArea", "AXRow", "AXCell", "AXGenericElement",
            ]
            if sampleDumps.count < 25, textPlausibleRoles.contains(elementRole) {
                sampleDumps.append("[\(elementRole)] \(dumpAllAttributes(element))")
            }

            // Skip the menu bar entirely — on Electron/Chromium apps like
            // Claude Desktop it's hundreds of AXMenuItem elements (File,
            // Edit, every app in "Open With", …) that burn the whole
            // element budget before the walk ever reaches real window
            // content. Confirmed empirically: 243 of 287 elements in the
            // first real run were menu bar noise.
            guard elementRole != "AXMenuBar" else { return }

            // Chromium's AX bridge (what Electron apps like Claude Desktop
            // render their whole UI through, per the AXWebArea found
            // pointing at .vite/renderer/main_window/index.html) exposes
            // its DOM tree via `AXChildrenInNavigationOrder`, not the
            // classic `kAXChildrenAttribute` — confirmed empirically: the
            // AXGroup elements under the AXWebArea had *only* the former
            // populated. Not a named constant in ApplicationServices, so
            // referenced by its raw string. Following both and merging
            // means this also still works for apps that only populate the
            // classic attribute.
            var childSets: [[AXUIElement]] = []
            var children: CFTypeRef?
            if AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &children) == .success,
               let childArray = children as? [AXUIElement] {
                childSets.append(childArray)
            }
            var navChildren: CFTypeRef?
            if AXUIElementCopyAttributeValue(element, "AXChildrenInNavigationOrder" as CFString, &navChildren) == .success,
               let navArray = navChildren as? [AXUIElement] {
                childSets.append(navArray)
            }
            for childArray in childSets {
                for child in childArray {
                    walk(child, depth: depth + 1)
                }
            }
        }

        walk(axApp, depth: 0)
        let elapsed = Date().timeIntervalSince(start) * 1000
        return Snapshot(
            texts: collected, elementsVisited: visited, elapsedMs: elapsed,
            roleCounts: roleCounts, sampleDumps: sampleDumps)
    }
}
