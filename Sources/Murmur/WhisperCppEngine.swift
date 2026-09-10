import AVFAudio
import Foundation
import whisper

/// A second "Precise" recognition engine, alongside `WhisperEngine`: the same
/// Whisper models, run through whisper.cpp's Metal backend instead of
/// WhisperKit/CoreML. Benchmarking on this machine showed whisper.cpp
/// transcribing 2.9–4.3× faster, likely because it runs on the GPU rather
/// than the power-efficient Neural Engine — a speed/battery tradeoff worth
/// letting the user pick for themselves rather than deciding for them.
///
/// Mirrors `WhisperEngine`'s public shape closely so the two are
/// interchangeable at the call site. The one structural difference:
/// whisper.cpp's C API is synchronous and blocking, where WhisperKit's is
/// already async — so every call into it here goes through `Task.detached`
/// rather than a plain inherited `Task`, which would otherwise block this
/// actor (and the UI) for the duration of the call.
@MainActor
final class WhisperCppEngine {

    static let availableModels: [(id: String, label: String)] = [
        ("tiny", "Tiny — fastest, ~75 MB"),
        ("base", "Base — fast, ~140 MB"),
        ("small", "Small — balanced, ~465 MB"),
        ("large-v3-turbo", "Large v3 Turbo — most precise, ~1.5 GB"),
        ("large-v3-lv", "Large v3 (Latvian fine-tune) — Latvian only, ~1.7 GB"),
    ]

    /// The one language a fine-tuned model is actually good for, if it's
    /// restricted to one — `nil` for the general multilingual models above.
    /// `large-v3-lv` (University of Latvia AiLab's Interspeech 2025
    /// fine-tune of whisper-large-v3, trained on Common Voice 19 + the
    /// LATE-Media broadcast corpus) measures 3.2% WER on Latvian versus
    /// Parakeet v3's 22.84% — but it's fine-tuned purely on Latvian audio,
    /// with no published data on retained multilingual competence, so
    /// unlike the general models it shouldn't be offered as a substitute
    /// for them on any other language. Mirrors `WhisperEngine.isEnglishOnly`
    /// in spirit, just specialized toward a different single language.
    static func restrictedLanguage(for model: String) -> String? {
        model == "large-v3-lv" ? "lv" : nil
    }

    /// Status line for the UI (loading/downloading/transcribing); nil clears.
    var onStatus: ((String?) -> Void)?

    // OpaquePointer doesn't conform to Sendable, so the compiler can't see
    // that access here is safe — but it is: both are only ever touched from
    // `pipeline(model:)`, which is itself actor-isolated, so there's no
    // concurrent access to prove. `nonisolated(unsafe)` says so explicitly
    // rather than leaving it as an unexplained warning.
    nonisolated(unsafe) private var context: OpaquePointer?
    nonisolated(unsafe) private var loadTask: Task<OpaquePointer, Error>?
    private var loadedModel: String?
    /// Set only after the context has fully loaded.
    private var readyModel: String?

    private var modelsDirectory: URL {
        AppPaths.supportDirectory.appendingPathComponent(
            "whispercpp-models", isDirectory: true)
    }

    private func modelFileURL(_ model: String) -> URL {
        modelsDirectory.appendingPathComponent("ggml-\(model).bin")
    }

    /// True once the context is loaded in memory and can transcribe now.
    func isReady(model: String) -> Bool {
        readyModel == model
    }

    /// Models confirmed present on disk. Mirrors `WhisperEngine`'s cache:
    /// only positive results are remembered, since a downloaded model file
    /// never becomes un-downloaded.
    private var downloadedModels: Set<String> = []

    func isModelDownloaded(_ model: String) -> Bool {
        if downloadedModels.contains(model) { return true }
        let exists = FileManager.default.fileExists(atPath: modelFileURL(model).path)
        if exists { downloadedModels.insert(model) }
        return exists
    }

    /// Kicks off model load/download in the background.
    func preload(model: String) {
        Task { _ = try? await self.pipeline(model: model) }
    }

    deinit {
        if let context {
            whisper_free(context)
        }
    }

    private func pipeline(model: String) async throws -> OpaquePointer {
        if loadedModel == model, let loadTask {
            return try await loadTask.value
        }
        loadTask?.cancel()
        let previousContext = context
        loadedModel = model
        readyModel = nil
        context = nil

        let needsDownload = !isModelDownloaded(model)
        onStatus?(needsDownload
            ? "Downloading whisper.cpp model (one-time)"
            : "Loading whisper.cpp model")

        let modelURL = modelFileURL(model)
        let task = Task.detached(priority: .userInitiated) { () -> OpaquePointer in
            if needsDownload {
                try await Self.download(model: model, to: modelURL)
            }
            var params = whisper_context_default_params()
            params.use_gpu = true
            guard let ctx = whisper_init_from_file_with_params(modelURL.path, params)
            else { throw WhisperCppError.loadFailed }
            return ctx
        }
        loadTask = task
        defer { onStatus?(nil) }
        let ctx = try await task.value
        // A newer call already superseded this one (model switched again
        // mid-load) — free what we just built instead of leaking it.
        guard loadedModel == model else {
            whisper_free(ctx)
            throw CancellationError()
        }
        context = ctx
        readyModel = model
        // Freed only now that the new context is fully in place, so a
        // transcription already in flight against the old one isn't pulled
        // out from under it.
        if let previousContext { whisper_free(previousContext) }
        return ctx
    }

    func transcribe(
        fileAt url: URL, model: String, localeID: String,
        biasTerms: [String]) async throws -> String {
        let ctx = try await pipeline(model: model)
        let samples = try Self.pcm16kMono(from: url)
        let language = String(localeID.prefix(while: { $0 != "-" })).lowercased()

        // Vocabulary biasing: the direct whisper.cpp equivalent of
        // WhisperKit's decoder prompt tokens — prepended free-text context
        // rather than pre-encoded tokens, but the same intent.
        let prompt = biasTerms.isEmpty ? nil
            : "Vocabulary: " + biasTerms.prefix(60).joined(separator: ", ") + "."

        onStatus?("Transcribing (whisper.cpp)")
        defer { onStatus?(nil) }

        return try await Task.detached(priority: .userInitiated) {
            try Self.runFull(ctx: ctx, samples: samples, language: language, prompt: prompt)
        }.value
    }

    /// OpenAI's own reference default — governs `no_speech_thold` below,
    /// whisper.cpp's own internal decoding-fallback signal. Not used as a
    /// post-hoc filter here (see `runFull`'s comment on why not).
    nonisolated private static let noSpeechThreshold: Float = 0.6

    /// The actual `whisper_full` call. Split out from `transcribe` so the
    /// `const char *` lifetimes (`language`, `initial_prompt`) stay scoped to
    /// `withCString`, rather than managed by hand with `strdup`/`free`.
    nonisolated private static func runFull(
        ctx: OpaquePointer, samples: [Float], language: String, prompt: String?
    ) throws -> String {
        try language.withCString { languagePtr in
            try withOptionalCString(prompt) { promptPtr in
                var params = whisper_full_default_params(WHISPER_SAMPLING_GREEDY)
                params.language = languagePtr
                params.detect_language = false
                params.initial_prompt = promptPtr
                // OpenAI's own reference default — the value most is known
                // about not causing regressions on ordinary quiet-but-real
                // speech. Governs whisper.cpp's internal decoding fallback
                // (whether to retry at a different temperature) but does
                // NOT by itself drop a segment's text from the output —
                // `no_speech_prob` is checked directly below for that.
                params.no_speech_thold = noSpeechThreshold
                // Each dictation is a fresh, unrelated recording — the
                // context is reused across calls purely to avoid reloading
                // the model, so it must not carry decoder state from a
                // previous, unrelated dictation into this one.
                params.no_context = true
                params.single_segment = false
                params.print_progress = false
                params.print_special = false
                params.print_realtime = false
                params.print_timestamps = false

                let status = samples.withUnsafeBufferPointer { buffer in
                    whisper_full(ctx, params, buffer.baseAddress, Int32(buffer.count))
                }
                guard status == 0 else { throw WhisperCppError.transcribeFailed }

                // No per-segment no_speech_prob filter here — it used to
                // drop any segment scoring above noSpeechThreshold, meant
                // to catch hallucinated sign-offs on silence. In practice
                // it occasionally fired on genuine trailing speech
                // instead, silently truncating real dictations. A
                // confidently-hallucinated "Thank you." measured at
                // ~0.00002 (i.e. the model is sure about its own invented
                // completion, not uncertain) — a signal that weak against
                // its actual target has no safe margin left to also spare
                // real speech. `HallucinationFilter` (whole-output phrase
                // matching) and `AudioRecorder`'s sustained-signal gate
                // already cover the silence case this was for.
                var text = ""
                for i in 0..<whisper_full_n_segments(ctx) {
                    if let segment = whisper_full_get_segment_text(ctx, i) {
                        text += String(cString: segment)
                    }
                }
                return text.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
    }

    nonisolated private static func withOptionalCString<T>(
        _ string: String?, _ body: (UnsafePointer<CChar>?) throws -> T
    ) rethrows -> T {
        if let string {
            return try string.withCString(body)
        }
        return try body(nil)
    }

    // MARK: - Audio

    /// Converts the recorder's `.caf` (whatever rate/channel layout the
    /// input device was actually running at — see `AudioRecorder`) into the
    /// 16kHz mono Float32 PCM `whisper_full` requires.
    nonisolated private static func pcm16kMono(from url: URL) throws -> [Float] {
        let file = try AVAudioFile(forReading: url)
        let inputFormat = file.processingFormat
        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32, sampleRate: 16000,
            channels: 1, interleaved: false),
            let converter = AVAudioConverter(from: inputFormat, to: targetFormat)
        else { throw WhisperCppError.audioConversionFailed }

        let inputFrameCount = AVAudioFrameCount(file.length)
        guard inputFrameCount > 0,
              let inputBuffer = AVAudioPCMBuffer(
                pcmFormat: inputFormat, frameCapacity: inputFrameCount)
        else { throw WhisperCppError.audioConversionFailed }
        try file.read(into: inputBuffer)

        let ratio = targetFormat.sampleRate / inputFormat.sampleRate
        let outputCapacity = AVAudioFrameCount(Double(inputBuffer.frameLength) * ratio) + 1024
        guard let outputBuffer = AVAudioPCMBuffer(
            pcmFormat: targetFormat, frameCapacity: outputCapacity)
        else { throw WhisperCppError.audioConversionFailed }

        var suppliedInput = false
        var conversionError: NSError?
        let status = converter.convert(to: outputBuffer, error: &conversionError) { _, outStatus in
            guard !suppliedInput else {
                outStatus.pointee = .noDataNow
                return nil
            }
            suppliedInput = true
            outStatus.pointee = .haveData
            return inputBuffer
        }
        guard status != .error else {
            throw conversionError ?? WhisperCppError.audioConversionFailed
        }
        guard let channelData = outputBuffer.floatChannelData else {
            throw WhisperCppError.audioConversionFailed
        }
        return Array(UnsafeBufferPointer(
            start: channelData[0], count: Int(outputBuffer.frameLength)))
    }

    // MARK: - Model download

    /// Where each model's GGML file actually lives. Everything downloads
    /// from ggerganov's own conversions except the Latvian fine-tune,
    /// which is a different upstream project (see `restrictedLanguage`)
    /// hosted under its own repo with its own filename — AiLab publishes
    /// several quantization levels; q8_0 is the one used here since
    /// accuracy is the entire point of offering this model at all, and
    /// q8_0 is close to full F16 quality without the full 3.1 GB download.
    nonisolated private static func downloadSource(for model: String) -> URL? {
        switch model {
        case "large-v3-lv":
            return URL(string:
                "https://huggingface.co/AiLab-IMCS-UL/whisper-large-v3-lv-late-cv19/resolve/main/ggml-model-q8_0.bin")
        default:
            return URL(string:
                "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-\(model).bin")
        }
    }

    nonisolated private static func download(model: String, to destination: URL) async throws {
        guard let source = downloadSource(for: model)
        else { throw WhisperCppError.downloadFailed }

        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true)
        let (tempURL, response) = try await URLSession.shared.download(from: source)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode)
        else { throw WhisperCppError.downloadFailed }

        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.moveItem(at: tempURL, to: destination)
    }
}

enum WhisperCppError: LocalizedError {
    case loadFailed, transcribeFailed, audioConversionFailed, downloadFailed

    var errorDescription: String? {
        switch self {
        case .loadFailed: return "whisper.cpp could not load the model."
        case .transcribeFailed: return "whisper.cpp transcription failed."
        case .audioConversionFailed: return "Could not convert the recording for whisper.cpp."
        case .downloadFailed: return "Could not download the whisper.cpp model."
        }
    }
}
