#!/bin/bash
# pershoot dev-susfs calls susfs_ends_with() which is not in upstream SUSFS patches
if ! grep -q "susfs_ends_with" include/linux/susfs.h 2>/dev/null; then
  cat >> include/linux/susfs.h << 'STUBEOF'
static inline bool susfs_ends_with(const char *str, const char *suffix) {
	int slen = strlen(str), xlen = strlen(suffix);
	return slen >= xlen && !strcmp(str + slen - xlen, suffix);
}
STUBEOF
  echo "Added susfs_ends_with stub"
fi
