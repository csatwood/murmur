# Changelog

## v2.0.1 — 2026-08-25

Fixes for the floating nav-bar HUD (the small pill that appears near the
bottom of the screen while Murmur is idle).

### Fixed

- Its popovers (Templates/Transforms, More, Listen) could render with their
  rounded corners and shadow sheared off flat, or clipped on one side —
  the panel they draw into was a fixed size too small for their actual
  content.
- Moving the cursor from a popover's trigger icon into the popover itself
  could close it before you reached it, since there was a real screen gap
  between the two with no hover coverage.
- At idle, the HUD's hit-region was the full nav-bar footprint (invisible,
  but still solid) — enough to swallow clicks meant for another
  bottom-docked utility sitting in the same part of the screen. Idle state
  now shows a small reveal-pill with a much smaller footprint, which grows
  into the full bar only when you hover it.
- The reveal/collapse between the small pill and the full bar is now a
  smooth, staged grow/shrink instead of an instant swap.

## v2.0.0 — 2026-08-23

The first public update since the original release — a full redesign, built and
open-sourced under MIT.

### New

- **Third recognition engine**: whisper.cpp running via Metal on the GPU,
  alongside Apple's built-in SpeechAnalyzer and WhisperKit. Murmur's fastest
  engine.
- **Harper grammar pass**: a deterministic, local, millisecond-speed grammar
  and style check that runs alongside the Apple Intelligence edit pass —
  catches agreement, punctuation, and repeated words the LLM edit occasionally
  misses. No model, no warm-up, no network.
- **Per-app profiles**: one place to set what Murmur does when you dictate
  into a specific app — tone and note template together, replacing two
  separate override systems that used to answer that question differently.
- **Ask Murmur**: ask questions about your own dictation history, answered
  entirely on-device via keyword retrieval into the local model.
- **Note templates**: restructure a transcript into a specific document shape
  via the on-device LLM; trigger one by voice at the start of a dictation.
- **Guided first run**: welcome → permissions → recognition engine → hotkey
  → mic test, shown once.
- **Hallucination filtering** for Whisper-family engines — phrase-matches the
  small, well-documented set of sign-off hallucinations ("Thank you.", etc.)
  those models produce on near-silent audio.
- **Legal page**: in-app licensing info for Murmur itself and its four
  open-source dependencies (also now in [NOTICE.md](NOTICE.md)).

### Changed

- Full UI redesign — a multi-view dashboard (Home, Insights, Ask Murmur,
  Scratchpad, Dictionary, Voice Profile, Style, Snippets, Templates,
  Transforms, Settings) replacing the original single menu-bar view.
- Murmur is now open-source under MIT. Between this release and the last, it
  was developed as a closed-source commercial product; that plan was dropped
  in favor of open-sourcing the whole thing.

## v1.0.0 — 2026-07-20

Initial public release: push-to-talk dictation via Apple's on-device speech
recognition or WhisperKit, cleanup pipeline, pronunciation learning, Styles,
Transforms, and a dashboard with history and usage stats.
