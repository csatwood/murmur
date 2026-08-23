import harper

/// A fast, local, deterministic grammar pass — [Harper](https://github.com/Automattic/harper),
/// vendored as a small Rust static library (`Vendor/harper-ffi`, built into
/// `Vendor/harper.xcframework`). Runs *in addition to* the Apple Intelligence
/// edit pass in `RewriteEngine`, not instead of it: the LLM handles filler
/// removal and restructuring rambling speech into sentences, which Harper's
/// rule-based linting doesn't do; Harper catches grammar (agreement,
/// punctuation, repeated words) at millisecond speed, as a final polish the
/// LLM's own occasional misses don't get a chance to slip through.
///
/// Pure, synchronous, local Rust — no model to download, no warm-up, no
/// network. Unlike every other engine in this app, there's nothing to be
/// "ready" for.
enum HarperChecker {
    /// Lints `text` and applies every fix Harper is confident enough to
    /// suggest. Empty input returns empty output; never throws — a
    /// malformed C string round-trip degrades to returning `text`
    /// unchanged rather than losing the dictation.
    static func fix(_ text: String) -> String {
        guard !text.isEmpty else { return text }
        guard let resultPtr = text.withCString({ harper_fix_text($0) }) else {
            return text
        }
        defer { harper_free_string(resultPtr) }
        let fixed = String(cString: resultPtr)
        return fixed.isEmpty ? text : fixed
    }
}
