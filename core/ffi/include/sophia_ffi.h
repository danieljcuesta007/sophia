// C surface of sophia-ffi. Canonical copy; the SwiftPM target's header is a
// symlink to this file (the Cadence pattern). Contracts in core/ffi/src/lib.rs.
#ifndef SOPHIA_FFI_H
#define SOPHIA_FFI_H

// Lint text (UTF-8) with options JSON (nullable): {"dictionary":["Addisuna"]}.
// Returns a heap JSON array of issues; release with sophia_free. Never null.
// Offsets are UTF-16 code units. A panic inside the core returns "[]".
char *sophia_lint(const char *text, const char *opts_json);

// Pre-loads the dictionary and rule set (~300 ms once). Call at agent launch,
// off the main thread.
void sophia_warmup(void);

// Releases a string returned by sophia_lint.
void sophia_free(char *ptr);

#endif
