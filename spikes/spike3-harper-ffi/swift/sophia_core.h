// C surface of sophia-core-spike (see core/src/lib.rs for contracts).
#ifndef SOPHIA_CORE_H
#define SOPHIA_CORE_H

// Returns a heap JSON array of issues; release with sophia_free. Never null.
char *sophia_lint(const char *text);
// Pre-loads the dictionary and rule set so the first real lint is fast.
void sophia_warmup(void);
// Releases a string returned by sophia_lint.
void sophia_free(char *ptr);

#endif
