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
        let version = Self.version(for: model)
        let directory = AsrModels.defaultCacheDirectory(for: version)
        let exists = AsrModels.modelsExist(at: directory, version: version)
        if exists { downloadedModels.insert(model) }
        return exists
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
        let task = Task { () -> AsrManager in
            let models = try await AsrModels.downloadAndLoad(version: version)
            let manager = AsrManager(config: .default)
            try await manager.loadModels(models)
            return manager
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

    private static func version(for model: String) -> AsrModelVersion {
        switch model {
        case "v2": return .v2
        default: return .v3
        }
    }
}
