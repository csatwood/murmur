# Upstream review — September 17, 2026

Compared the fork's Murmur 2.1.0 base (`0627909`) with upstream `main` at [`b5c5667`](https://github.com/janisbelozerovs-dev/murmur/commit/b5c5667). There are nine upstream commits after that base. The fork's microphone commit is `932708e`; the fast-dictation changes follow it.

The fork remains based on its tested Murmur 2.1.0 lineage. Selected correctness fixes are ported below; this is not a merge of the complete upstream history.

## Changes worth considering

| Commit | Change | Assessment |
| --- | --- | --- |
| `75cc953` | v2.1.0 changelog | Documentation only. |
| `f49c36a` | TheWhisper benchmark candidate | Developer tooling; no direct dictation fix. |
| `dd05b3b` | Developer vocabulary; protect brand names from Harper | Useful correctness work. Swift wrapper, C headers and vendored Harper binary must be updated together. Also changes vocabulary and terminal behavior. |
| `676ee24` | Self-correction handling; Parakeet speed/seam fixes | Useful but depends on vocabulary work; the next commit supersedes its Parakeet workaround. |
| `f319a8a` | UnifiedAsrManager; preserve abbreviation commas | Prioritize reviewing the punctuation fix. The recognition change matters when adopting vocabulary boosting and needs timing/accuracy checks. |
| `713835d` | Notetaker, custom Transforms, Settings redesign, HUD | Broad feature upgrade affecting more than 40 files; integrate separately. Includes cleanup levels that still run AI. |
| `fe77f94` | Feature changelog | Bring forward with the matching features. |
| `a69d4b8` | sherpa-onnx benchmark candidate | Optional developer tooling. |
| `b5c5667` | Experimental engines, per-profile recognition, website profiles, in-app updates | Broad upgrade with additional integration and updater risks below. |

## Conflicts and integration requirements

Read-only merge analysis of committed microphone patch `932708e` against upstream `b5c5667` confirmed textual conflicts in `Main.swift` (self-test aggregation) and `SettingsView.swift` (state and lifecycle). Keep all tests, microphone selection and device refresh when resolving them.

The fast-dictation patch adds further semantic overlap, not an independently verified merge-conflict list:

- Upstream `RewritePlan.instructions` introduces `cleanupLevel`. Its Light level still uses AI. Preserve this fork's fast default, optional automatic cleanup, explicit CLI editing, and Raw behavior.
- Preserve both microphone selection and the Automatic AI cleanup setting through the Settings redesign.
- Upstream audio changes add a live-buffer callback but retain built-in-microphone forcing. Preserve the fork's device routing.
- Preserve explicit `EditedText` conformance, SDK argument forwarding and font packaging when incorporating upstream's additional dynamic framework and permission declarations.

## Updater risk

The new upstream `UpdateChecker` targets `janisbelozerovs-dev/murmur`. Its installer replaces the installed app with an upstream release. Adopting it unchanged could overwrite this fork's changes.

Do not enable that installer for this fork until it targets verified fork releases or upstream update notices are separated from installation. Its bundle-ID check does not establish signing-identity continuity, so permission grants cannot be assumed to survive replacement with a differently signed app.

## Recommended order

1. Review and port the punctuation and vocabulary-protection fixes with their tests and required binary changes.
2. Benchmark recognition changes before adopting vocabulary boosting or another runtime.
3. Integrate the Settings/Notetaker/profile upgrade as a separate change, explicitly resolving the controls above.
4. Add fork-specific update delivery only when fork releases and signing verification are in place.

## Selected correctness ports

The follow-up correctness branch selectively adapts:

- [`dd05b3b`](https://github.com/janisbelozerovs-dev/murmur/commit/dd05b3b): Harper vocabulary support, matching Rust source/C headers/archive, rebuild script, and a guard against automatically learning ordinary-word substitutions. Live English grammar checking and the CLI grammar check both supply the existing user vocabulary. The guard is limited to automatic extraction so explicit Voice Training and existing mappings remain valid. This does not import developer-app detection, fuzzy developer vocabulary or CTC recognition boosting.
- [`f319a8a`](https://github.com/janisbelozerovs-dev/murmur/commit/f319a8a): narrow duplicate-punctuation handling so abbreviation commas survive. A local companion fix preserves lowercase letters after periods within abbreviations. Tests cover real `p.m.,` and `a.m.,` inputs, not only unpunctuated `5pm,`.

The Harper archive's Git blob matches upstream `dd05b3b` exactly. App-linked Swift tests check vocabulary and grammar together; isolated store tests verify deliberate training and existing saved mappings. The Rust toolchain was unavailable locally, so the Rust source suite was not run.

### Deferred after closer review

The restart-command regex in `676ee24` must not be copied unchanged. It checks the phrase's trailing boundary but can discard ordinary text such as “Do not forget that, it matters” or a quoted “scratch that” phrase. This port leaves restart handling unchanged and adds preservation tests. The associated AI prompt changes and Parakeet migration also remain deferred.

An upstream automatic-learning regression case used a substitution at the end of a sentence, where the existing diff algorithm already returned no mapping. This port puts the substituted word in the middle, observes the incorrect mapping before the fix, and verifies it is rejected afterward. The separate end-of-sentence extraction limitation is not changed here.

The initial two-file merge-conflict report above applied to the microphone commit. Later local changes can introduce additional conflicts during a full upstream merge; rerun the analysis when that upgrade is undertaken. Selective ports do not mark whole upstream commits as merged, so GitHub's behind count is not a list of missing fixes.
