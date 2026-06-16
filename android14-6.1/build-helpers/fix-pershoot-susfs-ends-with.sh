#!/bin/bash
# pershoot dev-susfs adb_root.c calls susfs_starts_with() and susfs_ends_with()
# but they're only declared locally in kernel/kallsyms.c, not in any header
# adb_root.c includes susfs_def.h — add declarations there

SUSFS_DEF="include/linux/susfs_def.h"
if [ -f "$SUSFS_DEF" ]; then
  if ! grep -q "susfs_starts_with" "$SUSFS_DEF" 2>/dev/null; then
    cat >> "$SUSFS_DEF" << 'STUBEOF'

/* Stubs for pershoot dev-susfs compatibility */
#ifndef susfs_starts_with
extern bool susfs_starts_with(const char *str, const char *prefix);
#endif
#ifndef susfs_ends_with
static inline bool susfs_ends_with(const char *str, const char *suffix) {
	int slen = strlen(str), xlen = strlen(suffix);
	return slen >= xlen && !strcmp(str + slen - xlen, suffix);
}
#endif
STUBEOF
    echo "Added susfs_starts_with/susfs_ends_with to susfs_def.h"
  fi
else
  echo "WARNING: susfs_def.h not found — patch 50 may have failed"
fi
