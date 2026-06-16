#!/system/bin/sh

ui_print " "
ui_print "ReSukiSU Stealth Policy"
ui_print "- Uses BRENE /data/adb/ksu/bin/ksu_susfs when available"
ui_print "- Generates rule overlays under /data/adb/resukisu-stealth"
ui_print "- Run: resukisu-stealth rescan && resukisu-stealth apply"

chmod 0755 "$MODPATH/resukisu-stealth" 2>/dev/null || true
mkdir -p /data/adb/ksu/bin /data/adb/resukisu-stealth/rules.d 2>/dev/null || true
cp -af "$MODPATH/resukisu-stealth" /data/adb/ksu/bin/resukisu-stealth 2>/dev/null || true
chmod 0755 /data/adb/ksu/bin/resukisu-stealth 2>/dev/null || true

if [ ! -f /data/adb/resukisu-stealth/local.conf ]; then
  cp -af "$MODPATH/local.conf.example" /data/adb/resukisu-stealth/local.conf 2>/dev/null || true
fi

ui_print "- Installed CLI: /data/adb/ksu/bin/resukisu-stealth"
