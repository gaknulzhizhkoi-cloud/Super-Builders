# ReSukiSU Stealth Policy

`resukisu-stealth-policy` is a small KernelSU/ReSukiSU module that acts as a rules overlay for a SUSFS userspace provider. It is designed for the module stack:

- BRENE
- BreWheel
- BreZygisk or ReZygisk
- ReLSPosed or LSPosed
- rsTEESimulator-RS
- TA_enhanced
- metamount-rs

BRENE remains the preferred owner of `/data/adb/ksu/bin/ksu_susfs`. This module reuses that helper when it works and only generates/apply rules around the real modules installed on the device.

## Commands

```sh
resukisu-stealth rescan
resukisu-stealth apply
resukisu-stealth status
resukisu-stealth export-brene
resukisu-stealth reset
```

## Rule Outputs

Generated files live under `/data/adb/resukisu-stealth/generated/`:

- `sus_maps.txt`
- `sus_mount.txt`
- `sus_path.txt`
- `sus_path_loop.txt`
- `sus_open_redirect.txt`
- `sus_kstat_statically.json`

Local overrides live under `/data/adb/resukisu-stealth/rules.d/` and `/data/adb/resukisu-stealth/local.conf`.

## Notes

- Install BRENE first, then the Zygisk/LSPosed/TEE/TA/mount-layer modules, then this policy module.
- Keep app-specific policy out of the kernel. Add new module leaks through `rules.d` or `local.conf`.
- The `apply` command is intentionally tolerant: unsupported SUSFS commands are logged and skipped instead of causing a boot loop.
