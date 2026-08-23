#ifndef HARPER_FFI_H
#define HARPER_FFI_H

/// Lints the given UTF-8 text and returns a newly-allocated corrected copy.
/// Never returns NULL: null, non-UTF8, or unparseable input yields an
/// empty string. The caller owns the result and must free it with
/// harper_free_string.
char *harper_fix_text(const char *input);

/// Frees a string returned by harper_fix_text. Safe to call with NULL.
void harper_free_string(char *s);

#endif /* HARPER_FFI_H */
