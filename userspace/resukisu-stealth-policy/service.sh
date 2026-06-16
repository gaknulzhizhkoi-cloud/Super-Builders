#!/system/bin/sh

MODDIR=${0%/*}
BOOT_DONE=0
while [ "$BOOT_DONE" != "1" ]; do
  BOOT_DONE=$(getprop sys.boot_completed 2>/dev/null)
  sleep 2
done

sh "$MODDIR/resukisu-stealth" rescan >/dev/null 2>&1 || true
sh "$MODDIR/resukisu-stealth" apply >/dev/null 2>&1 || true
