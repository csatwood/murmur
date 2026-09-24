import FluidAudio
import Foundation

/// A third "Precise" recognition engine, alongside `WhisperEngine` and
/// `WhisperCppEngine`: NVIDIA's Parakeet TDT model, run locally via FluidAudio
/// (CoreML on the Neural Engine). Independent benchmarking has shown it
/// transcribing noticeably faster than both Apple's built-in engine and the
/// Whisper-family engines here, with comparable accuracy.
///
/// Unlike the other two engines, there is no vocabulary biasing: Parakeet's
/// transducer architecture has no decoder-prompt mechanism equivalent to
/// Whisper's, so the user's dictionary/snippet terms cannot be fed in before
/// recognition. `biasTerms` is accepted for call-site uniformity and ignored.
/// FluidAudio does offer a separate CTC-based hotword-correction pass, but it
/// requires downloading a second model and rescoring each result — a
/// meaningful addition of its own, left for later if this proves worth it.
///
/// Model files are cached in FluidAudio's own default location
/// (`~/Library/Application Support/FluidAudio/Models/`) rather than under
/// Murmur's own support directory like the other two engines — there's no
/// reason to fight a sensible library default just for consistency.
@MainActor
final class ParakeetEngine {

    static let availableModels: [(id: String, label: String)] = [
        ("v2", "Parakeet v2 — English, highest recall, ~600 MB"),
        ("v3", "Parakeet v3 — multilingual (\(v3LanguageCodes.count) languages), ~600 MB"),
    ]

    /// BCP-47 language codes each model can actually transcribe: `v2` is
    /// English-only; `v3` is NVIDIA's documented 25-language European set,
    /// narrowed to the ones FluidAudio's own FLEURS benchmark measured
    /// under `v3WEROfferThreshold` word error rate — see
    /// `v3WordErrorRates`. Drives the Settings/HUD language pickers, which
    /// otherwise have no way to know these two models don't cover the same
    /// languages — or that "supported" and "actually accurate" aren't the
    /// same thing for several of the 25.
    static func supportedLanguageCodes(for model: String) -> [String] {
        model == "v2" ? ["en"] : v3LanguageCodes
    }

    /// Parakeet TDT v3's per-language word error rate, as measured by
    /// FluidAudio's own FLEURS benchmark (`fluidaudiocli fleurs-benchmark`,
    /// see FluidAudioCLI's `FleursBenchmark.swift`) against NVIDIA's
    /// documented 25-language set. Portuguese is absent from NVIDIA's set
    /// entirely here, not just filtered out below — that benchmark file
    /// only measured `pt_br` (Brazilian) as a separate, non-European
    /// addition alongside Arabic/Japanese/Mandarin/Korean/Vietnamese, with
    /// no comparable WER logged for it, so there's nothing here to vouch
    /// for either way.
    private static let v3WordErrorRates: [String: Double] = [
        "it": 3.00, "es": 3.45, "de": 5.04, "en": 4.85, "fr": 5.15,
        "ru": 5.51, "uk": 6.79, "pl": 7.31, "nl": 7.48, "sk": 8.82,
        "cs": 11.01, "ro": 12.44, "hr": 12.46, "bg": 12.64, "fi": 13.21,
        "sv": 15.08, "hu": 15.72, "et": 17.73, "da": 18.41, "mt": 20.46,
        "lt": 20.35, "el": 20.70, "lv": 22.84, "sl": 24.03,
    ]

    /// Above this measured word error rate, Murmur doesn't offer the
    /// language at all — wrong roughly one word in ten (or worse) isn't
    /// the fast, accurate dictation the app promises, and silently
    /// offering it as an equal alongside English/German/French/etc. sets
    /// an expectation the model can't meet. Chosen, not measured: there's
    /// no natural cutoff in the data (see the jump from Slovak's 8.82% to
    /// Czech's 11.01%), so this is a deliberate quality bar, not a
    /// statistical one — revisit if a Parakeet update changes the numbers.
    private static let v3WEROfferThreshold = 10.0

    private static let v3LanguageCodes: [String] =
        v3WordErrorRates
            .filter { $0.value < v3WEROfferThreshold }
            .keys
            .sorted()

    /// Status line for the UI (loading/downloading/transcribing); nil clears.
    var onStatus: ((String?) -> Void)?

    private var loadTask: Task<AsrManager, Error>?
    private var loadedModel: String?
    /// Set only after the pipeline has fully loaded.
    private var readyModel: String?

    /// Wall-clock ceilings for the load race in `pipeline(model:)`. A first-run
    /// download fetches ~450 MB from HuggingFace, so it gets a generous window;
    /// a load from an already-cached model touches only local disk and the
    /// Neural Engine compile, so it gets a short one. These bound a *stall*,
    /// not normal slowness: a healthy download or load finishes well inside.
    nonisolated static let downloadTimeout: Double = 300
    nonisolated static let loadTimeout: Double = 60

    /// True once the pipeline is loaded in memory and can transcribe now.
    func isReady(model: String) -> Bool {
        readyModel == model
    }

    /// Models confirmed present on disk. Only *positive* results are cached:
    /// a model can finish downloading later, but a complete one never
    /// becomes incomplete, so a `true` can never go stale.
    private var downloadedModels: Set<String> = []

    func isModelDownloaded(_ model: String) -> Bool {
        if downloadedModels.contains(model) { return true }
        let exists = Self.modelExistsOnDisk(model)
        if exists { downloadedModels.insert(model) }
        return exists
    }

    /// The on-disk existence probe walks the model cache directory, so it must
    /// not run on the main actor: `ParakeetEngine` is `@MainActor`, and doing
    /// filesystem work on the main thread stutters the UI. `nonisolated` moves
    /// it off. `AsrModels.modelsExist` is a pure static filesystem check with
    /// no shared mutable state, so it is safe to call from any context.
    nonisolated static func modelExistsOnDisk(_ model: String) -> Bool {
        let version = Self.version(for: model)
        let directory = AsrModels.defaultCacheDirectory(for: version)
        return AsrModels.modelsExist(at: directory, version: version)
    }

    /// Kicks off model load/download in the background.
    func preload(model: String) {
        Task { _ = try? await self.pipeline(model: model) }
    }

    private func pipeline(model: String) async throws -> AsrManager {
        if loadedModel == model, let loadTask {
            return try await loadTask.value
        }
        loadTask?.cancel()
        loadedModel = model
        readyModel = nil

        let version = Self.version(for: model)
        let needsDownload = !isModelDownloaded(model)
        onStatus?(needsDownload
            ? "Downloading Parakeet model (one-time)"
            : "Loading Parakeet model")
        let timeout = needsDownload ? Self.downloadTimeout : Self.loadTimeout
        let task = Task { () -> AsrManager in
            // Race the real load against a timeout. Without this, a stalled
            // model download (a network hang on the one-time HuggingFace
            // fetch) leaves this await pending forever: the status stays
            // "Downloading" and the app hangs, then the OS kills it as
            // unresponsive. On timeout we cancel the load and throw, so the
            // caller surfaces a real error instead of hanging.
            try await withThrowingTaskGroup(of: AsrManager.self) { group in
                group.addTask {
                    let models = try await AsrModels.downloadAndLoad(version: version)
                    let manager = AsrManager(config: .default)
                    try await manager.loadModels(models)
                    return manager
                }
                group.addTask {
                    try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                    throw ParakeetEngineError.modelLoadTimedOut(
                        model: model, seconds: timeout, wasDownloading: needsDownload)
                }
                guard let manager = try await group.next() else {
                    throw ParakeetEngineError.modelLoadTimedOut(
                        model: model, seconds: timeout, wasDownloading: needsDownload)
                }
                group.cancelAll()
                return manager
            }
        }
        loadTask = task
        defer { onStatus?(nil) }
        let manager = try await task.value
        if loadedModel == model {
            readyModel = model
        }
        return manager
    }

    func transcribe(
        fileAt url: URL, model: String, localeID: String,
        biasTerms: [String]) async throws -> String {
        let manager = try await pipeline(model: model)

        // A script-bias hint FluidAudio only actually uses for the v3
        // (multilingual) model — harmlessly ignored for v2. Safe to compute
        // and pass unconditionally rather than branching on version here.
        let language = Language(rawValue:
            String(localeID.prefix(while: { $0 != "-" })).lowercased())
        var decoderState = TdtDecoderState.make(
            decoderLayers: await manager.decoderLayerCount)

        onStatus?("Transcribing (Parakeet)")
        defer { onStatus?(nil) }
        // The URL overload does its own resampling to 16kHz mono internally
        // (FluidAudio's `AudioConverter`) — no manual PCM conversion needed,
        // unlike `WhisperCppEngine`.
        let result = try await manager.transcribe(
            url, decoderState: &decoderState, language: language)
        return result.text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    nonisolated private static func version(for model: String) -> AsrModelVersion {
        switch model {
        case "v2": return .v2
        default: return .v3
        }
    }
}

/// Errors surfaced by `ParakeetEngine` to the caller so a stall becomes a
/// visible failure rather than an indefinite hang.
enum ParakeetEngineError: LocalizedError {
    /// The model download or load exceeded its wall-clock ceiling and was
    /// cancelled. `wasDownloading` distinguishes the one-time fetch from a
    /// load of an already-cached model, so the message can guide the user.
    case modelLoadTimedOut(model: String, seconds: Double, wasDownloading: Bool)

    var errorDescription: String? {
        switch self {
        case let .modelLoadTimedOut(model, seconds, wasDownloading):
            let secs = Int(seconds)
            if wasDownloading {
                return "Downloading the Parakeet \(model) model timed out after "
                    + "\(secs)s. Check your network connection and try again; the "
                    + "download resumes from where it stopped."
            }
            return "Loading the Parakeet \(model) model timed out after \(secs)s."
        }
    }
}
