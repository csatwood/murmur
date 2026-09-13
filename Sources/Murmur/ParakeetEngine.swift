import AVFAudio
import FluidAudio
import Foundation

/// A third "Precise" recognition engine, alongside `WhisperEngine` and
/// `WhisperCppEngine`: NVIDIA's Parakeet TDT model, run locally via FluidAudio
/// (CoreML on the Neural Engine). Independent benchmarking has shown it
/// transcribing noticeably faster than both Apple's built-in engine and the
/// Whisper-family engines here, with comparable accuracy.
///
/// Vocabulary biasing works differently here than in the Whisper-family
/// engines. Parakeet's transducer architecture has no decoder-prompt
/// mechanism equivalent to Whisper's, so `biasTerms` can't nudge the main
/// decode itself — instead this runs FluidAudio's separate CTC-based
/// vocabulary-boosting pass (`SlidingWindowAsrManager` +
/// `CustomVocabularyContext`; see `Documentation/ASR/CustomVocabulary.md` in
/// the FluidAudio checkout) after the TDT decode: a second, small CTC
/// encoder listens to the same audio for acoustic evidence of a bias term,
/// and rescoring swaps in that term only where the evidence clears
/// FluidAudio's own confidence thresholds. This is the mechanism
/// prompt-based biasing could not be — testing this against
/// `DeveloperVocabulary`'s "Supabase" case showed a Whisper prompt
/// containing the term verbatim was still not enough on its own, because
/// prompt biasing only ever nudges token probabilities; it never checks a
/// candidate replacement against the actual audio the way CTC rescoring
/// does.
///
/// Falls back to the plain one-shot decode (no boosting) whenever the
/// caller doesn't request boosting (see `transcribe`'s `boostVocabulary`),
/// the CTC model isn't downloaded/loaded yet, there are no bias terms, or
/// the boosted path fails for any reason — boosting must never be the
/// reason a dictation comes back empty.
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

    private var loadTask: Task<AsrModels, Error>?
    private var loadedModel: String?
    /// Set only after the pipeline has fully loaded.
    private var readyModel: String?

    /// The CTC model used for vocabulary-boosting rescoring — independent of
    /// which TDT model (v2/v3) is actually transcribing, so it's loaded once
    /// and shared regardless of the model picker. `.ctc06b` is the variant
    /// FluidAudio's docs pair with Parakeet TDT 0.6B ("Approach 2: Separate
    /// CTC Encoder"), which both v2 and v3 are.
    private static let ctcVariant: CtcModelVariant = .ctc06b
    private var ctcLoadTask: Task<(models: CtcModels, tokenizer: CtcTokenizer), Error>?

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

    /// Kicks off model load/download in the background — the main TDT
    /// model, and separately the CTC vocabulary-boosting model. Dictation
    /// never waits on the latter: `transcribe` silently falls back to the
    /// plain decode if it isn't ready yet, so this has no status message of
    /// its own the way the main model's download does.
    func preload(model: String) {
        Task { _ = try? await self.asrModels(for: model) }
        Task { _ = try? await self.ctcResources() }
    }

    private func asrModels(for model: String) async throws -> AsrModels {
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
        let task = Task { () -> AsrModels in
            try await AsrModels.downloadAndLoad(version: version)
        }
        loadTask = task
        defer { onStatus?(nil) }
        let models = try await task.value
        if loadedModel == model {
            readyModel = model
        }
        return models
    }

    /// Loads (downloading if needed) the CTC model and its matching
    /// tokenizer used for vocabulary-boosting rescoring. Cached after the
    /// first success. Must load the tokenizer from `.ctc06b`'s own cache
    /// directory explicitly — `CtcTokenizer.load()`'s parameterless overload
    /// defaults to the *110m* model's directory, which would hand back
    /// token IDs from the wrong vocabulary.
    private func ctcResources() async throws -> (models: CtcModels, tokenizer: CtcTokenizer) {
        if let ctcLoadTask {
            return try await ctcLoadTask.value
        }
        let variant = Self.ctcVariant
        let task = Task { () -> (models: CtcModels, tokenizer: CtcTokenizer) in
            let models = try await CtcModels.downloadAndLoad(variant: variant)
            let tokenizer = try await CtcTokenizer.load(
                from: CtcModels.defaultCacheDirectory(for: variant))
            return (models, tokenizer)
        }
        ctcLoadTask = task
        return try await task.value
    }

    /// `boostVocabulary` gates the CTC rescoring pass below, separately
    /// from whether `biasTerms` happens to be non-empty. Measured cost:
    /// ~0.65s for a plain decode vs. ~1.7s once boosting kicks in — nearly
    /// 3x, and it used to trigger on *any* non-empty bias list, which in
    /// practice was almost every dictation (even a handful of personal
    /// dictionary entries is enough; developer vocabulary alone is ~110
    /// terms). That's a bad trade for most dictations: the terms most
    /// likely to actually collide acoustically with an ordinary word —
    /// "Supabase," "Codex," "Claude" — are specifically the short,
    /// English-word-shaped brand names in `DeveloperVocabulary`, not
    /// generic personal vocabulary. So this now only boosts when the
    /// caller says developer vocabulary is actually active for this app,
    /// restoring the fast path for everyone else — including a user with
    /// a large personal dictionary in a non-developer-context app, who
    /// previously paid the same 3x tax for terms far less prone to this
    /// specific failure mode.
    /// The exact point past which FluidAudio's sliding window starts
    /// splitting audio into multiple chunks (see `appendSamplesAndProcess`
    /// in FluidAudio's `SlidingWindowAsrManager`: it only fires once
    /// buffered audio reaches `chunk + right`). Under this, the whole
    /// recording is always one window via `flushRemaining()` alone —
    /// `transcribe`'s duration gate below relies on that to rule out the
    /// multi-window seam bug entirely, not just make it less likely.
    private static let slidingWindowChunkSeconds: Double = 11.0
    private static let slidingWindowRightContextSeconds: Double = 2.0

    func transcribe(
        fileAt url: URL, model: String, localeID: String,
        biasTerms: [String], boostVocabulary: Bool) async throws -> String {
        let models = try await asrModels(for: model)

        // A script-bias hint FluidAudio only actually uses for the v3
        // (multilingual) model — harmlessly ignored for v2. Safe to compute
        // and pass unconditionally rather than branching on version here.
        let language = Language(rawValue:
            String(localeID.prefix(while: { $0 != "-" })).lowercased())

        onStatus?("Transcribing (Parakeet)")
        defer { onStatus?(nil) }

        // Boosting's own sliding-window decoder has a real, reproduced bug:
        // FluidAudio's confirm/promote state machine that stitches multiple
        // chunks together can inject spurious text at a chunk seam — found
        // by testing a 15s, multi-sentence recording, where the boosted
        // path inserted words never spoken, right at the chunk boundary,
        // that the plain decode of the identical audio didn't have. Murmur
        // zeroes FluidAudio's `minContextForConfirmation`/
        // `confirmationThreshold` (see the doc comment below) so rescoring
        // applies to short dictations at all, which likely reopens the
        // instability those knobs exist to prevent. Rather than lose
        // boosting's real, measured win for the common case — it correctly
        // recovers "Supabase" where the plain decode mis-hears it as
        // "Superbase" — this only attempts boosting when the recording is
        // short enough that FluidAudio is structurally guaranteed to use a
        // single window (see `slidingWindowChunkSeconds` above): no second
        // chunk is ever built, so the seam this bug lives at can't occur.
        // Longer dictations fall back to the plain decode instead of
        // risking corrupted output — no boosting beats wrong boosting.
        let isShortEnoughForSingleWindow: Bool
        if let audioFile = try? AVAudioFile(forReading: url),
           audioFile.fileFormat.sampleRate > 0 {
            let seconds = Double(audioFile.length) / audioFile.fileFormat.sampleRate
            isShortEnoughForSingleWindow =
                seconds < Self.slidingWindowChunkSeconds + Self.slidingWindowRightContextSeconds
        } else {
            // Duration unreadable — can't prove single-window safety, so
            // don't risk it.
            isShortEnoughForSingleWindow = false
        }

        if boostVocabulary, isShortEnoughForSingleWindow, !biasTerms.isEmpty,
           let ctc = try? await ctcResources() {
            do {
                return try await transcribeWithVocabularyBoosting(
                    fileAt: url, asrModels: models, language: language,
                    biasTerms: biasTerms, ctc: ctc)
            } catch {
                dictationLog.error(
                    "Parakeet vocabulary boosting failed, falling back to plain decode: \(error, privacy: .public)"
                )
            }
        }

        let manager = AsrManager(config: .default)
        try await manager.loadModels(models)
        var decoderState = TdtDecoderState.make(decoderLayers: await manager.decoderLayerCount)
        // The URL overload does its own resampling to 16kHz mono internally
        // (FluidAudio's `AudioConverter`) — no manual PCM conversion needed,
        // unlike `WhisperCppEngine`.
        let result = try await manager.transcribe(
            url, decoderState: &decoderState, language: language)
        return result.text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Runs the sliding-window decoder with CTC-based vocabulary rescoring
    /// applied. `loadModels`/`configureVocabularyBoosting` here are cheap:
    /// they wire up already-loaded CoreML model handles and re-read a small
    /// cached tokenizer file, not a fresh download or model compile — the
    /// real one-time costs (`asrModels(for:)`, `ctcResources()`) are cached
    /// on `self` and shared across calls, so building a fresh
    /// `SlidingWindowAsrManager` per dictation is the safe choice: no
    /// actor-state (decoder state, sample buffers) can leak between one
    /// dictation and the next.
    ///
    /// `minContextForConfirmation`/`confirmationThreshold` are zeroed out
    /// below: both exist to stabilize a *live* transcript view (don't flip
    /// displayed text until there's enough context/confidence to commit to
    /// it), which doesn't apply here — Murmur only reads the final
    /// `finish()` result, never an intermediate volatile/confirmed state.
    /// Left at their real (10s / 0.85) defaults, most of Murmur's
    /// dictations — a sentence or two, a few seconds — would never reach
    /// "confirmed" at all, and vocabulary rescoring only ever runs on
    /// confirmed text (see `SlidingWindowAsrManager.processWindow`):
    /// silently disabling the whole feature for the common case. The
    /// rescorer has its own independent confidence gates
    /// (`CustomVocabularyContext.minCtcScore`/`minSimilarity`/
    /// `minCombinedConfidence`) for whether to actually apply a
    /// replacement, so nothing is lost by always attempting it.
    ///
    /// `minSimilarity: 0.85` is far stricter than FluidAudio's own default
    /// (0.52-0.60, size-tiered) — deliberately safe-by-default rather than
    /// tuned to fix any one term, because direct testing against
    /// synthesized audio (`say`) turned up a false-positive class the
    /// library default misses entirely: this vocabulary is full of short
    /// brand names built from ordinary English words ("Supabase" is
    /// "Supa" + "base", "Codex"/"Xcode" are both "code" plus an affix),
    /// and a floor loose enough to let the rescorer *fix* a mis-hearing of
    /// one of these is usually also loose enough to let it *corrupt* an
    /// unrelated, correctly-heard word into the same term. Confirmed, not
    /// theoretical: at a loose-enough-to-help floor, a clean "I need to
    /// back up the database..." came back "...back up the Supabase...",
    /// and a clean "I deployed the code to the cloud..." came back "...
    /// deployed the Xcode to the Claude...", with none of those brand
    /// names anywhere in the audio. 0.85 sits above every such collision
    /// found so far (database 0.63, cloud→Claude 0.67, code→Codex/Xcode
    /// 0.80). `DeveloperVocabulary.parakeetMinSimilarityOverrides` loosens
    /// this back down per-term, but only for a term with its own direct,
    /// positive test result — see its doc comment. Known remaining gap:
    /// even for "Supabase", the one term loosened so far, this can't fix
    /// every mis-hearing pattern this session found — "Separate" (0.63)
    /// and "Supervise" (0.56) measure at or below "database"'s own
    /// similarity to "Supabase", so admitting them would reopen that exact
    /// false positive.
    private func transcribeWithVocabularyBoosting(
        fileAt url: URL, asrModels: AsrModels, language: Language?,
        biasTerms: [String], ctc: (models: CtcModels, tokenizer: CtcTokenizer)
    ) async throws -> String {
        let terms = biasTerms.compactMap { term -> CustomVocabularyTerm? in
            let ctcTokenIds = ctc.tokenizer.encode(term)
            guard !ctcTokenIds.isEmpty else { return nil }
            return CustomVocabularyTerm(
                text: term, ctcTokenIds: ctcTokenIds,
                minSimilarity: DeveloperVocabulary.parakeetMinSimilarityOverrides[term])
        }
        guard !terms.isEmpty else {
            throw ASRError.processingFailed("No bias terms survived CTC tokenization")
        }
        let vocabulary = CustomVocabularyContext(terms: terms, minSimilarity: 0.85)

        // The same "proven" 11+2+2s window FluidAudio's own `.default`
        // config uses (see `SlidingWindowAsrConfig.default`) — just with
        // the two live-transcript-only knobs above zeroed out.
        let config = SlidingWindowAsrConfig(
            chunkSeconds: Self.slidingWindowChunkSeconds,
            hypothesisChunkSeconds: 2.0,
            leftContextSeconds: 2.0,
            rightContextSeconds: Self.slidingWindowRightContextSeconds,
            minContextForConfirmation: 0,
            confirmationThreshold: 0,
            language: language)
        let streamingAsr = SlidingWindowAsrManager(config: config)
        try await streamingAsr.configureVocabularyBoosting(
            vocabulary: vocabulary, ctcModels: ctc.models)
        try await streamingAsr.loadModels(asrModels)
        try await streamingAsr.startStreaming()

        let audioFile = try AVAudioFile(forReading: url)
        let format = audioFile.processingFormat
        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: format, frameCapacity: AVAudioFrameCount(audioFile.length))
        else {
            throw ASRError.processingFailed(
                "Could not allocate an audio buffer for \(url.lastPathComponent)")
        }
        try audioFile.read(into: buffer)

        // One call with the whole recording, not chunked: `streamAudio`
        // only appends to an internal sample buffer that gets sliced into
        // windows as they become available, so call granularity doesn't
        // affect the result — confirmed by reading
        // `SlidingWindowAsrManager.appendSamplesAndProcess`/
        // `flushRemaining`. Dictation is already a complete recording by
        // the time this runs, not a live stream, so there's no reason to
        // split it up ourselves.
        await streamingAsr.streamAudio(buffer)
        let text = try await streamingAsr.finish()
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func version(for model: String) -> AsrModelVersion {
        switch model {
        case "v2": return .v2
        default: return .v3
        }
    }
}
