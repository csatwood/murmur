import Foundation

/// A real, available release — never fabricated. Everything here comes
/// from GitHub's own Releases API for this repo; there's no appcast, no
/// Sparkle. "Update Now" installs for real when the release publishes a
/// `.zip` asset (see `AppInstaller`) — `installerZipURL` — and falls back
/// to opening `downloadURL` (the `.dmg`, or the release page) in the
/// browser if that asset is missing or the install fails partway.
struct AppUpdate: Identifiable, Equatable {
    var version: String
    /// Raw bullet lines from the release body, marker stripped. Not
    /// split into a title/detail pair per row like the mockup's own
    /// illustration — that presumes a two-part structure a real release
    /// body may not have, so each line renders as one plain row instead.
    var notes: [String]
    var sizeBytes: Int64?
    var publishedAt: Date?
    /// Manual fallback: the release's `.dmg` if it has one, otherwise the
    /// release page itself. Opened in the browser only when the real
    /// in-place install (below) isn't possible or fails.
    var downloadURL: URL
    /// The release's `.zip` asset, if it published one — `AppInstaller`
    /// downloads and unpacks this to replace the running app bundle in
    /// place. `nil` for a release built before this existed, or one
    /// someone forgot to attach it to.
    var installerZipURL: URL?
    var id: String { version }
}

enum UpdateChecker {
    private static let repo = "janisbelozerovs-dev/murmur"

    /// Fetches the latest GitHub release and returns it only if its tag
    /// is newer than the running app's own `CFBundleShortVersionString`.
    /// Returns `nil` on any failure (offline, rate-limited, no releases
    /// yet) — a failed check should never surface as an error to the
    /// user, just silently mean "nothing to show."
    static func checkLatest() async -> AppUpdate? {
        guard let url = URL(string: "https://api.github.com/repos/\(repo)/releases/latest") else {
            return nil
        }
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse, http.statusCode == 200,
              let release = try? JSONDecoder().decode(GitHubRelease.self, from: data)
        else { return nil }

        let latestVersion = release.tagName.hasPrefix("v")
            ? String(release.tagName.dropFirst()) : release.tagName
        let runningVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
        guard isNewer(latestVersion, than: runningVersion) else { return nil }

        // Prefer the .dmg for the manual/fallback link — that's the
        // friendlier drag-to-Applications experience for anyone who ends
        // up downloading it by hand. The .zip is a separate asset, picked
        // out below, purely for the in-place installer to consume.
        let dmgAsset = release.assets.first { $0.name.hasSuffix(".dmg") }
        let zipAsset = release.assets.first { $0.name.hasSuffix(".zip") }
        guard let downloadURL = (dmgAsset ?? zipAsset).flatMap({ URL(string: $0.browserDownloadURL) })
            ?? URL(string: release.htmlURL)
        else { return nil }
        let installerZipURL = zipAsset.flatMap { URL(string: $0.browserDownloadURL) }

        let notes = (release.body ?? "")
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.hasPrefix("-") || $0.hasPrefix("*") || $0.hasPrefix("•") }
            .map { $0.drop(while: { "-*• ".contains($0) }) }
            .map(String.init)

        let formatter = ISO8601DateFormatter()
        return AppUpdate(
            version: latestVersion,
            notes: notes,
            sizeBytes: (dmgAsset ?? zipAsset)?.size,
            publishedAt: release.publishedAt.flatMap(formatter.date(from:)),
            downloadURL: downloadURL,
            installerZipURL: installerZipURL)
    }

    /// Dotted-numeric comparison ("1.10.0" > "1.9.0"), padding whichever
    /// side has fewer components with zeros rather than requiring both
    /// tags to share the same shape.
    private static func isNewer(_ a: String, than b: String) -> Bool {
        let partsA = a.split(separator: ".").map { Int($0) ?? 0 }
        let partsB = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(partsA.count, partsB.count) {
            let x = i < partsA.count ? partsA[i] : 0
            let y = i < partsB.count ? partsB[i] : 0
            if x != y { return x > y }
        }
        return false
    }
}

private struct GitHubRelease: Decodable {
    let tagName: String
    let htmlURL: String
    let body: String?
    let publishedAt: String?
    let assets: [Asset]

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case htmlURL = "html_url"
        case body
        case publishedAt = "published_at"
        case assets
    }

    struct Asset: Decodable {
        let name: String
        let size: Int64
        let browserDownloadURL: String

        enum CodingKeys: String, CodingKey {
            case name, size
            case browserDownloadURL = "browser_download_url"
        }
    }
}
