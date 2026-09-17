import Foundation

/// Downloads a release's `.zip` asset and replaces the running app bundle
/// with it in place, entirely inside this already-approved process.
///
/// This is the piece that makes "Update Now" a real install without an
/// Apple Developer ID. Gatekeeper's "unidentified developer" block only
/// triggers on files a *quarantine-aware* client wrote (Safari, Mail,
/// Chrome, a `.dmg` someone downloaded by hand) — a plain `URLSession`
/// download never sets that flag, so the app we unpack here launches
/// clean on relaunch. Settings live in `UserDefaults` under the app's
/// stable bundle ID, not inside the bundle itself, and Accessibility/
/// Microphone grants are tied to the stable "WhisperFlow Dev" signing
/// identity (see `make_signing_cert.sh`) — both survive this replace
/// untouched, same as they survive any other rebuild.
enum AppInstaller {
    enum InstallError: LocalizedError {
        case noInstallerAsset
        case unzipFailed
        case bundleNotFound
        case wrongBundleID
        case replaceFailed

        var errorDescription: String? {
            switch self {
            case .noInstallerAsset: return "This release has no installable .zip asset."
            case .unzipFailed: return "Couldn't unpack the downloaded update."
            case .bundleNotFound: return "The downloaded update didn't contain an app."
            case .wrongBundleID: return "The downloaded update doesn't look like Murmur."
            case .replaceFailed: return "Couldn't replace the installed app — check permissions on /Applications."
            }
        }
    }

    /// Replaces `Bundle.main`'s own .app with `update`'s zipped asset.
    /// Reports coarse progress via `onProgress` for the sheet's button
    /// label. Throws on any failure — callers should fall back to
    /// `update.downloadURL` in the browser rather than leaving the user
    /// stuck mid-update.
    static func install(_ update: AppUpdate, onProgress: @escaping (String) -> Void) async throws {
        guard let zipURL = update.installerZipURL else {
            throw InstallError.noInstallerAsset
        }

        onProgress("Downloading Murmur \(update.version)…")
        let (downloadedFile, _) = try await URLSession.shared.download(from: zipURL)

        let workDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("MurmurUpdate-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workDir) }

        // `download(from:)` only guarantees the file exists at
        // `downloadedFile` until this call returns, so it has to be moved
        // into our own workDir before anything else touches the run loop.
        let zipPath = workDir.appendingPathComponent("Murmur.zip")
        try FileManager.default.moveItem(at: downloadedFile, to: zipPath)

        onProgress("Unpacking…")
        let unzipDir = workDir.appendingPathComponent("unzipped")
        try FileManager.default.createDirectory(at: unzipDir, withIntermediateDirectories: true)
        let ditto = Process()
        ditto.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        ditto.arguments = ["-x", "-k", zipPath.path, unzipDir.path]
        try ditto.run()
        ditto.waitUntilExit()
        guard ditto.terminationStatus == 0 else { throw InstallError.unzipFailed }

        guard let newAppURL = try FileManager.default
            .contentsOfDirectory(at: unzipDir, includingPropertiesForKeys: nil)
            .first(where: { $0.pathExtension == "app" })
        else { throw InstallError.bundleNotFound }

        guard let newBundle = Bundle(url: newAppURL),
              newBundle.bundleIdentifier == Bundle.main.bundleIdentifier
        else { throw InstallError.wrongBundleID }

        onProgress("Installing…")
        try replace(Bundle.main.bundleURL, with: newAppURL)
    }

    /// Trashes the old bundle (reversible, rather than deleting outright)
    /// and moves the new one into its place. Safe to do while the old
    /// bundle is the process currently running from it — on macOS an
    /// executable's file can be unlinked or replaced while it's mapped
    /// into memory; only the *next* launch sees the new one on disk.
    private static func replace(_ currentAppURL: URL, with newAppURL: URL) throws {
        let fm = FileManager.default
        do {
            try fm.trashItem(at: currentAppURL, resultingItemURL: nil)
            try fm.moveItem(at: newAppURL, to: currentAppURL)
        } catch {
            throw InstallError.replaceFailed
        }
    }
}
