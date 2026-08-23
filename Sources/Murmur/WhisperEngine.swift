import AVFAudio
import Foundation
import WhisperKit

/// Murmur's optional "Precise" recognition engine: OpenAI's Whisper model
/// running locally via WhisperKit (CoreML on the Neural Engine). Slower to
/// warm up than Apple's engine but stronger on accents and jargon, and it
/// supports vocabulary biasing through the decoder prompt — the user's
/// dictionary, snippets and learned terms are fed in before recognition.
/// The model downloads once into Application Support; recognition is offline.
@MainActor
final class WhisperEngine {

    static let availableModels: [(id: String, label: String)] = [
        ("base", "Base — fastest, ~150 MB"),
        ("small", "Small — balanced, recommended, ~500 MB"),
        ("distil-whisper_distil-large-v3_turbo",
         "Distil Large v3 — fast + precise, English only, ~600 MB"),
        ("large-v3-v20240930_turbo", "Large v3 Turbo — most precise, slow, ~1.6 GB"),
    ]

    /// Status line for the UI (loading/downloading/transcribing); nil clears.
    var onStatus: ((String?) -> Void)?

    private var loadTask: Task<WhisperKit, Error>?
    private var loadedModel: String?
    /// Set only after the pipeline has fully loaded and prewarmed.
    private var readyModel: String?

    private var modelsDirectory: URL {
        AppPaths.supportDirectory.appendingPathComponent(
            "whisper-models", isDirectory: true)
    }

    /// True once the pipeline is loaded in memory and can transcribe now.
    func isReady(model: String) -> Bool {
        readyModel == model
    }

    /// Where WhisperKit unpacks its CoreML repos.
    private var repoDirectory: URL {
        modelsDirectory.appendingPathComponent(
            "models/argmaxinc/whisperkit-coreml", isDirectory: true)
    }

    /// Models confirmed present on disk. Only *positive* results are cached:
    /// a model can finish downloading later, but a complete one never
    /// becomes incomplete, so a `true` can never go stale.
    private var downloadedModels: Set<String> = []

    /// True once all three CoreML components exist locally (no download
    /// needed).
    ///
    /// This is called from `whisperModelDetail` in the Settings view body,
    /// which SwiftUI re-evaluates on every state change. The previous
    /// implementation answered it with `subpathsOfDirectory` — a *deep*
    /// enumeration of the whole model tree (~300 files, ~6ms of main-thread
    /// I/O) — so simply having Settings open re-walked several gigabytes'
    /// worth of directory entries continuously. This checks the three exact
    /// paths instead, and remembers the answer.
    func isModelDownloaded(_ model: String) -> Bool {
        if downloadedModels.contains(model) { return true }

        let fileManager = FileManager.default
        // WhisperKit prefixes most repo folders ("base" → "openai_whisper-base")
        // but not all ("distil-whisper_distil-large-v3_turbo" is verbatim), so
        // match on suffix rather than trying to reproduce the naming scheme.
        guard let folders = try? fileManager.contentsOfDirectory(
            atPath: repoDirectory.path),
            let folder = folders.first(where: { $0 == model || $0.hasSuffix(model) })
        else { return false }

        let base = repoDirectory.appendingPathComponent(folder, isDirectory: true)
        let complete = ["AudioEncoder", "TextDecoder", "MelSpectrogram"]
            .allSatisfy { component in
                fileManager.fileExists(atPath: base
                    .appendingPathComponent("\(component).mlmodelc", isDirectory: true)
                    .appendingPathComponent("coremldata.bin").path)
            }
        if complete { downloadedModels.insert(model) }
        return complete
    }

    /// Kicks off model load/download in the background.
    func preload(model: String) {
        Task { _ = try? await self.pipeline(model: model) }
    }

    private func pipeline(model: String) async throws -> WhisperKit {
        if loadedModel == model, let loadTask {
            return try await loadTask.value
        }
        loadTask?.cancel()
        loadedModel = model
        readyModel = nil

        let needsDownload = !isModelDownloaded(model)
        onStatus?(needsDownload
            ? "Downloading Whisper model (one-time)"
            : "Loading Whisper model")
        let directory = modelsDirectory
        let task = Task { () -> WhisperKit in
            let config = WhisperKitConfig(
                model: model,
                downloadBase: directory,
                verbose: false,
                logLevel: .error,
                prewarm: true,
                load: true,
                download: true)
            return try await WhisperKit(config)
        }
        loadTask = task
        defer { onStatus?(nil) }
        let pipe = try await task.value
        if loadedModel == model {
            readyModel = model
        }
        return pipe
    }

    func transcribe(
        fileAt url: URL, model: String, localeID: String,
        biasTerms: [String]) async throws -> String {
        let pipe = try await pipeline(model: model)

        var options = DecodingOptions()
        options.language = String(localeID.prefix(while: { $0 != "-" })).lowercased()
        // Timestamps aren't needed for dictation — skipping them trims
        // decoding work. VAD chunking only pays off on long recordings.
        options.withoutTimestamps = true
        // Already WhisperKit's own default (0.6, matching OpenAI's
        // reference), but set explicitly rather than left implicit — this
        // is what a segment's `noSpeechProb` gets compared against below,
        // so the two numbers need to stay visibly in sync even if
        // WhisperKit's own default ever changes.
        options.noSpeechThreshold = Self.noSpeechThreshold
        if let audioFile = try? AVAudioFile(forReading: url),
           audioFile.fileFormat.sampleRate > 0 {
            let seconds = Double(audioFile.length) / audioFile.fileFormat.sampleRate
            options.chunkingStrategy = seconds > 25 ? .vad : nil
        } else {
            options.chunkingStrategy = .vad
        }

        // Vocabulary biasing: Whisper conditions on a decoder prompt, so
        // listing the user's terms makes it far likelier to spell them right.
        if !biasTerms.isEmpty, let tokenizer = pipe.tokenizer {
            let prompt = "Vocabulary: "
                + biasTerms.prefix(60).joined(separator: ", ") + "."
            let tokens = tokenizer.encode(text: " " + prompt)
                .filter { $0 < tokenizer.specialTokens.specialTokenBegin }
            options.promptTokens = Array(tokens.prefix(200))
            options.usePrefillPrompt = true
        }

        onStatus?("Transcribing (Whisper)")
        defer { onStatus?(nil) }
        let results = try await pipe.transcribe(
            audioPath: url.path, decodeOptions: options)
        // `noSpeechThreshold` above only controls WhisperKit's internal
        // decoding fallback (whether to retry at a different temperature)
        // — nothing in WhisperKit itself drops a segment's text from
        // `results.map(\.text)` just because it decided the segment was
        // silence. A per-segment `noSpeechProb` filter used to be applied
        // here too, on the same reasoning as the whisper.cpp engine — and
        // removed for the same reason: measured unreliable against actual
        // hallucinations (a confident "Thank you." scores near-zero, not
        // uncertain), so a signal that weak had no safe margin left to
        // also spare real trailing speech, and it was silently truncating
        // genuine dictations. `HallucinationFilter` (whole-output phrase
        // matching) and `AudioRecorder`'s sustained-signal gate already
        // cover the silence case this was for.
        return results
            .flatMap(\.segments)
            .map(\.text)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// OpenAI's own reference default — the value most is known about not
    /// causing regressions on ordinary quiet-but-real speech.
    private static let noSpeechThreshold: Float = 0.6
}
