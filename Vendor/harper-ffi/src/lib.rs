//! Minimal C FFI around harper-core, built for Murmur.
//!
//! Exposes exactly two functions: `harper_fix_text` lints the input and
//! applies every suggested fix, returning corrected text; `harper_free_string`
//! frees what it returns. No other surface — Murmur only needs "fix this text",
//! not the full lint/suggestion API.

use harper_core::linting::{LintGroup, Linter};
use harper_core::parsers::PlainEnglish;
use harper_core::spell::FstDictionary;
use harper_core::{Dialect, Document};
use std::ffi::{CStr, CString};
use std::os::raw::c_char;

/// Lints `input` and returns a newly-allocated corrected copy. The caller
/// owns the result and must pass it to `harper_free_string` when done.
///
/// Never fails outward: a null/invalid/non-UTF8 input produces an empty
/// string rather than a null pointer, so Swift callers don't need a
/// separate null-check path on top of the usual empty-string check.
#[no_mangle]
pub extern "C" fn harper_fix_text(input: *const c_char) -> *mut c_char {
    let text = if input.is_null() {
        ""
    } else {
        unsafe { CStr::from_ptr(input) }.to_str().unwrap_or("")
    };

    let fixed = fix_text(text);
    CString::new(fixed)
        .unwrap_or_else(|_| CString::new("").unwrap())
        .into_raw()
}

/// Frees a string returned by `harper_fix_text`. Safe to call with null.
#[no_mangle]
pub extern "C" fn harper_free_string(s: *mut c_char) {
    if s.is_null() {
        return;
    }
    unsafe {
        drop(CString::from_raw(s));
    }
}

fn fix_text(text: &str) -> String {
    if text.is_empty() {
        return String::new();
    }

    let parser = PlainEnglish;
    let document = Document::new_curated(text, &parser);
    let dict = FstDictionary::curated();
    let mut linter = LintGroup::new_curated(dict, Dialect::American);
    let mut lints = linter.lint(&document);

    // Apply fixes in reverse span order: applying an earlier edit first
    // would shift the character offsets every later lint's span is
    // expressed in, corrupting all subsequent splices.
    lints.sort_by(|a, b| b.span.start.cmp(&a.span.start));

    let mut chars: Vec<char> = text.chars().collect();
    for lint in &lints {
        if let Some(suggestion) = lint.suggestions.first() {
            suggestion.apply(lint.span, &mut chars);
        }
    }

    chars.into_iter().collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn leaves_correct_text_alone() {
        let input = "This is a correct sentence.";
        assert_eq!(fix_text(input), input);
    }

    #[test]
    fn fixes_repeated_word() {
        let fixed = fix_text("I went to the the store.");
        assert!(!fixed.contains("the the"), "got: {fixed}");
    }

    #[test]
    fn empty_input_is_empty_output() {
        assert_eq!(fix_text(""), "");
    }
}
