# Extra Rules

Optional user-managed rule files can be placed in `/data/adb/resukisu-stealth/rules.d/`.

Supported file names:

- `sus_maps.txt`
- `sus_mount.txt`
- `sus_path.txt`
- `sus_path_loop.txt`
- `sus_open_redirect.txt`
- `sus_kstat.txt`

The module keeps generated files separate from local overrides, so rescans do not erase manual rules.
