#!/system/bin/sh

MODDIR=${0%/*}
chmod 0755 "$MODDIR/resukisu-stealth" 2>/dev/null || true
mkdir -p /data/adb/ksu/bin /data/adb/resukisu-stealth/rules.d 2>/dev/null || true
cp -af "$MODDIR/resukisu-stealth" /data/adb/ksu/bin/resukisu-stealth 2>/dev/null || true
chmod 0755 /data/adb/ksu/bin/resukisu-stealth 2>/dev/null || true

if [ ! -f /data/adb/resukisu-stealth/local.conf ]; then
  cp -af "$MODDIR/local.conf.example" /data/adb/resukisu-stealth/local.conf 2>/dev/null || true
fi
