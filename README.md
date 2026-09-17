# Murmur 🎙️

**Private, unlimited voice dictation for macOS — 100% on-device.**

Hold `fn`, speak, release — clean text appears at your cursor in any app.
Choose your microphone in **Settings → Dictation → Microphone**. The default
is **System default**, which follows macOS Sound settings at the start of each
recording. A selected device is remembered across restarts; reconnect it or
choose another if it becomes unavailable. For Bluetooth playback without
headset microphone mode switching, select a built-in or USB microphone.
No cloud, no subscription, no word limits. Your audio and transcripts never
leave your Mac.

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="Resources/screenshot-dark.png">
  <img src="Resources/screenshot.png" alt="Murmur dashboard">
</picture>

Murmur is an open-source, fully local take on the modern AI dictation app
(in the spirit of Wispr Flow), built natively in Swift on Apple's on-device
speech and language models, with an optional local Whisper engine.

## Features

- **Push-to-talk dictation** — hold `fn` (or right ⌥) anywhere; release to
  paste at your cursor. Double-tap for hands-free mode.
- **Four recognition engines**, all offline:
  - **Apple** — instant, built into macOS (SpeechAnalyzer, macOS 26).
  - **WhisperKit** — precision engine via
    [WhisperKit](https://github.com/argmaxinc/WhisperKit) (CoreML on the
    Neural Engine). Your vocabulary is fed into the decoder prompt.
  - **whisper.cpp** — the same Whisper models, running via Metal on the
    GPU instead, with phrase-based filtering for the sign-off
    hallucinations ("Thank you.", etc.) Whisper-family models are known to
    produce on near-silent audio.
  - **Parakeet** — NVIDIA's model via
    [FluidAudio](https://github.com/FluidInference/FluidAudio) (CoreML on
    the Neural Engine). Murmur's fastest engine; no vocabulary biasing yet.
- **Harper grammar pass** — [Harper](https://github.com/Automattic/harper)
  runs alongside the Apple Intelligence edit pass below: deterministic,
  millisecond-speed local linting (agreement, punctuation, repeated words)
  that catches what an LLM edit occasionally misses. No model, no warm-up,
  no network.
- **Per-app profiles** — one place to set what Murmur does when you dictate
  into a specific app: tone and note template together, instead of two
  separate override systems answering "what happens in Slack?" differently.
- **Ask Murmur** — ask questions about your own dictation history, answered
  entirely on-device via lightweight keyword retrieval into the local model
  (no embeddings, no network).
- **Note templates** — restructure a transcript into a specific document
  shape via the on-device LLM; trigger one by voice at the start of a
  dictation, or apply manually.
- **Pronunciation learning** — a Voice Training page learns how *you* say
  tricky words; corrections you make to transcripts are diffed and learned
  automatically; everything biases future recognition.
- **Cleanup pipeline** — filler-word removal, spoken "new line"/"new
  paragraph", auto-capitalization, personal dictionary, snippets
  (say a trigger phrase → paste a saved block).
- **Styles** — per-app tone rewriting (formal / casual / very casual) using
  Apple Intelligence's on-device model.
- **Transforms** — select text in any app, press ⌥1 to polish grammar or ⌥2
  to turn rough notes into a structured AI prompt, rewritten in place.
- **Dashboard** — history with search and correction-learning, usage stats
  (words, WPM, day streak), insights chart, a Voice Profile persona derived
  locally from what you dictate, scratchpad.
- **Guided first run** — welcome → permissions → recognition engine →
  hotkey → mic test, shown once.

## Requirements

- macOS 26 (Tahoe) or newer
- Apple Silicon Mac
- Xcode 26 command-line tools (`xcode-select --install`)
- For Styles / Transforms / Voice Profile: Apple Intelligence enabled
- For the Whisper engine: a one-time model download (150 MB – 1.6 GB)

## Build & run

```bash
git clone <this-repo>
cd murmur
./scripts/make_app.sh     # builds build/Murmur.app
open build/Murmur.app
```

Optional: run `./scripts/make_signing_cert.sh` once to create a local
self-signed signing certificate — this keeps macOS permission grants valid
across rebuilds. Without it the app is ad-hoc signed and you'll need to
re-grant Accessibility after each rebuild.

### One-time permissions

1. **Microphone** — allow when prompted on first dictation.
2. **Accessibility** — allow when prompted (needed for the global hotkey and
   for pasting). If the app still shows it as missing, use *Settings →
   Reset Grant & Relaunch* inside Murmur.

## CLI test modes

```bash
.build/debug/Murmur --selftest                          # formatter + learning tests
.build/debug/Murmur --transcribe audio.wav              # Apple engine
.build/debug/Murmur --transcribe audio.wav --engine whisper
.build/debug/Murmur --format "um hello new line hi"     # cleanup pipeline only
.build/debug/Murmur --transform "fix this grammer pls"  # on-device LLM polish
```

## Privacy

Everything runs on this Mac: recognition (Apple SpeechAnalyzer or a local
Whisper/Parakeet model), cleanup, tone rewriting (Apple Intelligence), and
the Voice Profile analysis. Murmur makes no network requests except the
one-time model downloads by macOS itself (Apple speech assets) and, if you
opt into a non-Apple engine, that model's own one-time fetch (Hugging Face
for Whisper, FluidAudio's own CDN for Parakeet). Dictation data is stored
only in `~/Library/Application Support/Murmur/`.

## Architecture

Swift Package. WhisperKit and FluidAudio are remote SwiftPM dependencies,
each used only if you pick that engine; whisper.cpp/ggml and Harper are
vendored as prebuilt xcframeworks under `Vendor/` (Harper's Rust source is
included, whisper.cpp's isn't — see [NOTICE.md](NOTICE.md) for both).

```
HotkeyMonitor  →  AudioRecorder  →  Transcriber (Apple / WhisperKit / whisper.cpp / Parakeet)
                                        ↓
     TextFormatter → LearnedStore → SnippetStore → RewriteEngine (Styles) → HarperChecker
                                        ↓
                        TextInserter (clipboard + ⌘V)
```

See [PLAN.md](PLAN.md) for the original design document and
[CHANGELOG.md](CHANGELOG.md) for what's new in each release.

## License

[MIT](LICENSE). Not affiliated with Wispr Flow, OpenAI, NVIDIA, or Apple.
