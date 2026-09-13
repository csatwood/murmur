import AppKit
import Foundation

@main
struct MurmurMain {
    @MainActor
    static func main() async {
        Settings.migrateLegacyDefaults()
        var arguments = Array(CommandLine.arguments.dropFirst()).makeIterator()
        var mode: Mode = .app
        var localeIdentifier = "en-US"
        var engineName = "apple"
        var whisperModel = Settings.whisperModel
        var templateName: String?
        var transformID: String?
        var bundleID: String?

        while let argument = arguments.next() {
            switch argument {
            case "--transcribe":
                guard let path = arguments.next() else { usageAndExit() }
                mode = .transcribe(path)
            case "--engine":
                engineName = arguments.next() ?? engineName
            case "--whisper-model":
                whisperModel = arguments.next() ?? whisperModel
            case "--format":
                guard let text = arguments.next() else { usageAndExit() }
                mode = .format(text)
            case "--transform":
                guard let text = arguments.next() else { usageAndExit() }
                mode = .transform(text)
            case "--edit":
                guard let text = arguments.next() else { usageAndExit() }
                mode = .edit(text)
            case "--harper-fix":
                guard let text = arguments.next() else { usageAndExit() }
                mode = .harperFix(text)
            case "--ask":
                guard let question = arguments.next() else { usageAndExit() }
                mode = .ask(question)
            case "--history":
                mode = .history
            case "--history-search":
                guard let query = arguments.next() else { usageAndExit() }
                mode = .historySearch(query)
            case "--history-export":
                guard let path = arguments.next() else { usageAndExit() }
                mode = .historyExport(path)
            case "--template":
                templateName = arguments.next() ?? templateName
            case "--transform-id":
                transformID = arguments.next() ?? transformID
            case "--selftest":
                mode = .selftest
            case "--locale":
                localeIdentifier = arguments.next() ?? localeIdentifier
            case "--bundle-id":
                bundleID = arguments.next() ?? bundleID
            case "--help", "-h":
                usageAndExit()
            default:
                usageAndExit()
            }
        }

        switch mode {
        case .selftest:
            let formatterPassed = TextFormatter.runSelfTest()
            let learnedPassed = LearnedStore.runSelfTest()
            let templatesPassed = NoteTemplateStore.runSelfTest()
            let askPassed = AskMurmur.runSelfTest()
            let profilesPassed = AppProfileStore.runSelfTest()
            let audioPassed = AudioRecorder.runSelfTest()
            let hallucinationPassed = HallucinationFilter.runSelfTest()
            let developerVocabPassed = DeveloperVocabulary.runSelfTest()
            exit(formatterPassed && learnedPassed && templatesPassed && askPassed
                 && profilesPassed && audioPassed && hallucinationPassed
                 && developerVocabPassed ? 0 : 1)

        case .format(let text):
            // Same pipeline as live dictation: format, apply learned
            // corrections, then expand snippets. --bundle-id resolves
            // developer-vocabulary the same way a real dictation into that
            // app would (default: off, matching a `nil` bundle ID/no
            // resolvable frontmost app).
            let developerVocabulary = AppProfileStore.developerVocabularyEnabled(
                forBundleID: bundleID)
            print(SnippetStore.expand(
                in: LearnedStore.apply(
                    in: TextFormatter().format(text),
                    includeDeveloperVocabulary: developerVocabulary)))
            exit(0)

        case .harperFix(let text):
            let developerVocabulary = AppProfileStore.developerVocabularyEnabled(
                forBundleID: bundleID)
            print(HarperChecker.fix(
                text,
                vocabulary: LearnedStore.biasTerms(
                    includeDeveloperVocabulary: developerVocabulary)))
            exit(0)

        case .transform(let text):
            let engine = RewriteEngine()
            if let note = engine.availabilityNote {
                FileHandle.standardError.write(Data("Unavailable: \(note)\n".utf8))
                exit(1)
            }
            let transform = transformID.flatMap { id in
                Transform.all.first { $0.id.caseInsensitiveCompare(id) == .orderedSame }
            } ?? Transform.all[0]
            do {
                let polished = try await engine.edit(
                    text, instructions: transform.instructions)
                print(polished)
                exit(0)
            } catch {
                FileHandle.standardError.write(Data("Failed: \(error)\n".utf8))
                exit(1)
            }

        case .edit(let text):
            // Runs the exact same pipeline stopAndTranscribe() does for a
            // dictation into --bundle-id (default: no app, so the global
            // default style/no per-app override) — real persisted Voice
            // Profile included — rather than a synthetic instruction
            // string, so this reproduces field reports faithfully instead
            // of a simplified stand-in. --template opts into a specific
            // built-in/custom template instead of the no-template default,
            // to verify a template's own instructions (and worked example,
            // once one exists) rather than just the baseline cleanup pass.
            //
            // Style resolves through AppProfileStore exactly like the real
            // pipeline (a bundle ID's own override, else Raw for a
            // recognized terminal, else the global default) rather than
            // hardcoding StyleSettings.defaultStyle — the gap between
            // those two used to mean this command couldn't reproduce a
            // Raw-style app at all, only ever exercising the non-Raw path.
            let style = AppProfileStore.style(forBundleID: bundleID)
            guard !style.skipsAllProcessing else {
                print(text)
                exit(0)
            }
            let engine = RewriteEngine()
            if let note = engine.availabilityNote {
                FileHandle.standardError.write(Data("Unavailable: \(note)\n".utf8))
                exit(1)
            }
            let voice = Settings.useVoiceProfile ? VoiceProfileStore.load() : nil
            let template = templateName.flatMap { name in
                NoteTemplateStore.all().first { $0.name.caseInsensitiveCompare(name) == .orderedSame }
            }
            guard let instructions = RewritePlan.instructions(
                template: template, style: style, voice: voice)
            else {
                print(text)
                exit(0)
            }
            FileHandle.standardError.write(
                Data("--- instructions ---\n\(instructions)\n--- end instructions ---\n".utf8))
            do {
                let result = try await engine.edit(text, instructions: instructions)
                print(result)
                exit(0)
            } catch {
                FileHandle.standardError.write(Data("Failed: \(error)\n".utf8))
                exit(1)
            }

        case .ask(let question):
            let engine = RewriteEngine()
            if let note = engine.availabilityNote {
                FileHandle.standardError.write(Data("Unavailable: \(note)\n".utf8))
                exit(1)
            }
            let history = HistoryStore()
            do {
                let answer = try await AskMurmur.ask(
                    question, history: history.entries, engine: engine)
                print(answer)
                exit(0)
            } catch {
                FileHandle.standardError.write(Data("Failed: \(error)\n".utf8))
                exit(1)
            }

        case .history:
            printHistory(HistoryStore().entries)
            exit(0)

        case .historySearch(let query):
            printHistory(HistoryStore.matching(query, in: HistoryStore().entries))
            exit(0)

        case .historyExport(let path):
            do {
                let data = try JSONEncoder().encode(HistoryStore().entries)
                try data.write(to: URL(fileURLWithPath: path))
                print("Exported \(HistoryStore().entries.count) entries to \(path)")
                exit(0)
            } catch {
                FileHandle.standardError.write(Data("Export failed: \(error)\n".utf8))
                exit(1)
            }

        case .transcribe(let path):
            do {
                // --bundle-id resolves developer-vocabulary the same way a
                // real dictation into that app would (default: off,
                // matching a `nil` bundle ID/no resolvable frontmost app) —
                // pass e.g. `--bundle-id com.apple.dt.Xcode` to reproduce
                // what actually happens dictating into a recognized
                // developer-context app instead of the CLI's own default.
                let developerVocabulary = AppProfileStore.developerVocabularyEnabled(
                    forBundleID: bundleID)
                let raw: String
                if engineName == "whisper" {
                    let whisper = WhisperEngine()
                    whisper.onStatus = { status in
                        if let status {
                            FileHandle.standardError.write(Data("\(status)\n".utf8))
                        }
                    }
                    raw = try await whisper.transcribe(
                        fileAt: URL(fileURLWithPath: path),
                        model: whisperModel,
                        localeID: localeIdentifier,
                        biasTerms: LearnedStore.biasTerms(
                            includeDeveloperVocabulary: developerVocabulary))
                } else if engineName == "whispercpp" {
                    let whisperCpp = WhisperCppEngine()
                    whisperCpp.onStatus = { status in
                        if let status {
                            FileHandle.standardError.write(Data("\(status)\n".utf8))
                        }
                    }
                    raw = try await whisperCpp.transcribe(
                        fileAt: URL(fileURLWithPath: path),
                        model: whisperModel,
                        localeID: localeIdentifier,
                        biasTerms: LearnedStore.biasTerms(
                            includeDeveloperVocabulary: developerVocabulary))
                } else if engineName == "parakeet" {
                    let parakeet = ParakeetEngine()
                    parakeet.onStatus = { status in
                        if let status {
                            FileHandle.standardError.write(Data("\(status)\n".utf8))
                        }
                    }
                    raw = try await parakeet.transcribe(
                        fileAt: URL(fileURLWithPath: path),
                        model: whisperModel,
                        localeID: localeIdentifier,
                        biasTerms: LearnedStore.biasTerms(
                            includeDeveloperVocabulary: developerVocabulary),
                        boostVocabulary: developerVocabulary)
                } else {
                    let transcriber = Transcriber(
                        locale: Locale(identifier: localeIdentifier))
                    raw = try await transcriber.transcribe(
                        fileAt: URL(fileURLWithPath: path),
                        biasTerms: LearnedStore.biasTerms(
                            includeDeveloperVocabulary: developerVocabulary))
                }
                // Full live-dictation pipeline: format → learned corrections
                // → snippet expansion → Harper — everything the real style
                // resolved for --bundle-id runs except the Apple
                // Intelligence rewrite pass, left out here since it's
                // non-deterministic and needs on-device model availability
                // this debug path shouldn't depend on. Personal corrections
                // and Harper are gated to English, matching AppDelegate's
                // `isEnglishDictation` — both assume English input and
                // corrupt other languages' real words otherwise.
                //
                // Branches on `AppProfileStore.style(forBundleID:)` the
                // same way AppDelegate does — this used to run one fixed
                // sequence regardless of --bundle-id, so it could not
                // exercise Raw mode's "skip formatting/Harper entirely"
                // path at all. Found by testing the terminal-defaults-to-
                // Raw change immediately after building it: every
                // --bundle-id gave the same output, silently, because
                // this pipeline never branched on the value it resolved.
                let isEnglishDictation =
                    String(localeIdentifier.prefix(while: { $0 != "-" }))
                    .lowercased() == "en"
                let style = AppProfileStore.style(forBundleID: bundleID)
                var formatted: String
                if style.skipsAllProcessing {
                    formatted = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                    if isEnglishDictation {
                        formatted = LearnedStore.apply(
                            in: formatted, includeDeveloperVocabulary: developerVocabulary)
                    }
                    formatted = SnippetStore.expand(in: formatted)
                } else {
                    formatted = TextFormatter(
                        dictionary: isEnglishDictation ? TextFormatter.loadDictionary() : [:]
                    ).format(raw)
                    if isEnglishDictation {
                        formatted = LearnedStore.apply(
                            in: formatted, includeDeveloperVocabulary: developerVocabulary)
                    }
                    formatted = SnippetStore.expand(in: formatted)
                    if isEnglishDictation {
                        formatted = HarperChecker.fix(
                            formatted,
                            vocabulary: LearnedStore.biasTerms(
                                includeDeveloperVocabulary: developerVocabulary))
                    }
                }
                print("RAW: \(raw)")
                print("style: \(style.rawValue)")
                print("FORMATTED: \(formatted)")
                exit(0)
            } catch {
                FileHandle.standardError.write(
                    Data("Transcription failed: \(error)\n".utf8))
                exit(1)
            }

        case .app:
            let app = NSApplication.shared
            app.setActivationPolicy(.accessory)
            let delegate = AppDelegate()
            app.delegate = delegate
            app.run()
        }
    }

    private enum Mode {
        case app
        case transcribe(String)
        case format(String)
        case transform(String)
        case edit(String)
        case harperFix(String)
        case ask(String)
        case history
        case historySearch(String)
        case historyExport(String)
        case selftest
    }

    /// One line per entry, tab-separated: timestamp, word count, text. Text
    /// can contain embedded newlines (templated output has its own line
    /// breaks) — collapsed to spaces so the one-line-per-entry shape a
    /// terminal pipeline expects actually holds.
    private static func printHistory(_ entries: [HistoryEntry]) {
        let formatter = ISO8601DateFormatter()
        for entry in entries {
            let line = entry.text.replacingOccurrences(of: "\n", with: " ")
            print("\(formatter.string(from: entry.date))\t\(entry.wordCount)w\t\(line)")
        }
    }

    private static func usageAndExit() -> Never {
        print("""
        Murmur — local dictation (hold fn to talk, release to paste)

        Usage:
          Murmur                      run as menu bar app
          Murmur --transcribe <file>  transcribe an audio file
                                      [--locale en-US] [--engine apple|whisper|whispercpp|parakeet]
                                      [--whisper-model base|small|large-v3-v20240930_turbo]
                                      [--bundle-id com.apple.dt.Xcode] to test as
                                      if dictating into that app (developer
                                      vocabulary on/off resolves the same way);
                                      omitted, resolves like no app is focused
          Murmur --format "<text>"    run the text formatter on a string
                                      [--bundle-id ...] same as --transcribe
          Murmur --transform "<text>" run a ⌥1/⌥2 Transform (Polish by default)
                                      [--transform-id promptEngineer] to pick
                                      a different one from Transform.all
          Murmur --edit "<text>"      run the real rewrite pass on a string —
                                      actual persisted Voice Profile included,
                                      same as a live dictation would use
                                      [--bundle-id ...] resolves style the
                                      same way a real dictation into that
                                      app would (default: global default
                                      style); a Raw-style app prints the
                                      text unchanged, same as live
                                      [--template "Meeting Notes"] to route
                                      through a specific template instead of
                                      the no-template default
          Murmur --ask "<question>"   ask a question about your dictation history
          Murmur --history            print dictation history (last 30 days,
                                      500 entries max — that's all Murmur
                                      keeps on disk)
          Murmur --history-search "<term>"   search history, same window
          Murmur --history-export <path>     write history as JSON to a file
          Murmur --selftest           run formatter self-tests
        """)
        exit(0)
    }
}
