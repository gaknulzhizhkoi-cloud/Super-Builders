#!/bin/bash
# fix-susfs-compat.sh — Runtime SUSFS kernel compatibility fixes
# Called by build workflows after patches are applied.
# Fixes sublevel-dependent issues that can't be in static patches.
# Idempotent: safe to run multiple times on the same tree.
#
# Usage: fix-susfs-compat.sh <kernel_common_dir> <sublevel> <android_ver> <kernel_ver> <kernel_patches_dir>

KERNEL_DIR="$1"   # e.g., /path/to/common
SUBLEVEL="$2"     # e.g., 107, 209, 246
ANDROID_VER="$3"  # e.g., android12
KERNEL_VER="$4"   # e.g., 5.10
PATCHES_DIR="$5"  # reserved — not currently used

if [ -z "$KERNEL_DIR" ] || [ ! -d "$KERNEL_DIR" ]; then
    echo "fix-susfs-compat: ERROR: kernel dir '$KERNEL_DIR' not found" >&2
    exit 1
fi

echo "fix-susfs-compat: kernel=$KERNEL_DIR sublevel=$SUBLEVEL android=$ANDROID_VER kver=$KERNEL_VER"

# ---------------------------------------------------------------------------
# Fix 1: show_pad: label missing from fs/proc/task_mmu.c
# Needed when the 50_ patch adds a 'goto show_pad;' but the label itself
# isn't present in the source (android12-5.10 sublevels < 218).
# ---------------------------------------------------------------------------
TMU="$KERNEL_DIR/fs/proc/task_mmu.c"
if [ -f "$TMU" ]; then
    if grep -q 'goto show_pad;' "$TMU" && ! grep -q '^show_pad:' "$TMU"; then
        echo "fix-susfs-compat: injecting show_pad: label in task_mmu.c (sublevel $SUBLEVEL)"
        sed -i '/show_smap_vma_flags(m, vma);/,/return 0;/{/return 0;/i\show_pad:
        }' "$TMU"
    fi
    # Suppress -Wunused-label on show_pad regardless of goto presence
    if grep -q '^show_pad:' "$TMU" && ! grep -q 'show_pad:.*__attribute__' "$TMU"; then
        echo "fix-susfs-compat: marking show_pad: as maybe-unused in task_mmu.c"
        sed -i 's/^show_pad:$/show_pad: __attribute__((__unused__));/' "$TMU"
    fi
else
    echo "fix-susfs-compat: task_mmu.c not found — skipping show_pad fix"
fi

# ---------------------------------------------------------------------------
# Fix 2: fdinfo.c — inotify_mark_user_mask() fallback
# The helper was backported mid-stable (~5.10.68+). On older sublevels
# the function is absent, causing a link error. Replace the call with
# the direct field access it wraps.
# Guard: only act when the call-site is present but the definition is absent.
# ---------------------------------------------------------------------------
FDINFO="$KERNEL_DIR/fs/notify/fdinfo.c"
if [ -f "$FDINFO" ]; then
    if grep -q 'inotify_mark_user_mask(mark)' "$FDINFO"; then
        if ! grep -rq 'static.*inotify_mark_user_mask\|^u32 inotify_mark_user_mask' "$KERNEL_DIR/fs/notify/"; then
            echo "fix-susfs-compat: replacing inotify_mark_user_mask(mark) with mark->mask in fdinfo.c"
            sed -i 's/inotify_mark_user_mask(mark)/mark->mask/g' "$FDINFO"
        else
            echo "fix-susfs-compat: inotify_mark_user_mask defined — no fallback needed"
        fi
    fi
else
    echo "fix-susfs-compat: fdinfo.c not found — skipping inotify_mark_user_mask fix"
fi

# ---------------------------------------------------------------------------
# Fix 3: fdinfo.c — old-style 'u32 mask' declaration (sublevel ≤ 117)
# Early 5.10 sublevels declare 'u32 mask = mark->mask & IN_ALL_EVENTS;'
# before the SUSFS injected code, producing a C89 "declaration after
# statement" error. Delete the declaration and replace bare 'mask' refs.
# ---------------------------------------------------------------------------
if [ -f "$FDINFO" ]; then
    if grep -q 'u32 mask = mark->mask & IN_ALL_EVENTS;' "$FDINFO"; then
        echo "fix-susfs-compat: fixing u32 mask declaration in fdinfo.c (sublevel $SUBLEVEL)"
        # Remove the declaration
        sed -i '/u32 mask = mark->mask & IN_ALL_EVENTS;/d' "$FDINFO"
        # Single-line seq_printf variant: s_dev, mask)
        sed -i 's/s_dev, mask)/s_dev, mark->mask)/g' "$FDINFO"
        # Multi-line seq_printf variant: leading whitespace + mask, mark->ignored_mask
        sed -i 's/^\([[:space:]]*\)mask, mark->ignored_mask/\1mark->mask, mark->ignored_mask/' "$FDINFO"
    else
        echo "fix-susfs-compat: fdinfo.c u32 mask declaration not present — OK"
    fi
fi

# ---------------------------------------------------------------------------
# Fix 4: fdinfo.c — 'out_seq_printf:' label missing trailing semicolon
# C requires a statement after a label. The SUSFS patch may inject the
# label without a semicolon on older sublevels.
# ---------------------------------------------------------------------------
if [ -f "$FDINFO" ]; then
    # Match lines that have ONLY the label (no trailing semicolon)
    if grep -qE '^[[:space:]]*out_seq_printf:[[:space:]]*$' "$FDINFO"; then
        echo "fix-susfs-compat: adding semicolon after out_seq_printf: label in fdinfo.c"
        sed -i 's/^\([[:space:]]*\)out_seq_printf:[[:space:]]*$/\1out_seq_printf: ;/' "$FDINFO"
    else
        echo "fix-susfs-compat: out_seq_printf: label OK (already has semicolon or absent)"
    fi
fi

# ---------------------------------------------------------------------------
# Fix 5: susfs.c — i_uid_into_mnt / i_user_ns() fallback
# These helpers were backported mid-5.15 and are absent from 5.10 kernels
# that don't carry the backport. Fall back to direct i_uid field access.
# Guard: check for i_user_ns in include/linux/fs.h.
# ---------------------------------------------------------------------------
SUSFS_C="$KERNEL_DIR/fs/susfs.c"
if [ -f "$SUSFS_C" ]; then
    if ! grep -q 'i_user_ns' "$KERNEL_DIR/include/linux/fs.h" 2>/dev/null; then
        if grep -q 'i_uid_into_mnt' "$SUSFS_C"; then
            echo "fix-susfs-compat: replacing i_uid_into_mnt() calls in susfs.c (i_user_ns absent)"
            sed -i 's/i_uid_into_mnt(i_user_ns(&fi->inode), &fi->inode)\.val/fi->inode.i_uid.val/g' "$SUSFS_C"
            sed -i 's/i_uid_into_mnt(i_user_ns(inode), inode)\.val/inode->i_uid.val/g' "$SUSFS_C"
        fi
    else
        echo "fix-susfs-compat: i_user_ns present — i_uid_into_mnt fix not needed"
    fi
else
    echo "fix-susfs-compat: susfs.c not found — skipping i_uid_into_mnt fix"
fi

# ---------------------------------------------------------------------------
# Fix 6: setuid_hook.c — duplicate ksu_handle_setresuid on >= 6.8 kernels
# SukiSU builtin branch defines ksu_handle_setresuid in both the SUSFS
# #else block AND a separate 6.8+ MANUAL_HOOK block. When both
# CONFIG_KSU_SUSFS and CONFIG_KSU_MANUAL_HOOK are defined, both compile,
# causing a redefinition error. Remove the 6.8+ block.
# ---------------------------------------------------------------------------
SETUID="$KERNEL_DIR/drivers/kernelsu/setuid_hook.c"
if [ -f "$SETUID" ]; then
    DUPS=$(grep -c 'int ksu_handle_setresuid' "$SETUID")
    if [ "$DUPS" -gt 1 ]; then
        echo "fix-susfs-compat: removing duplicate ksu_handle_setresuid (6.8+ MANUAL_HOOK block)"
        python3 - "$SETUID" << 'PYEOF'
import sys
path = sys.argv[1]
with open(path) as f:
    lines = f.readlines()
start = next((i for i, l in enumerate(lines) if 'KERNEL_VERSION(6, 8, 0)' in l), None)
if start is not None:
    depth, end = 0, None
    for i in range(start, len(lines)):
        stripped = lines[i].strip()
        if stripped.startswith('#if'):
            depth += 1
        elif stripped.startswith('#endif'):
            depth -= 1
            if depth == 0:
                end = i
                break
    if end is not None:
        del lines[start:end+1]
        while lines and lines[-1].strip() == '':
            lines.pop()
        lines.append('\n')
        with open(path, 'w') as f:
            f.writelines(lines)
        print(f"  removed lines {start+1}-{end+1}")
PYEOF
    else
        echo "fix-susfs-compat: setuid_hook.c — no duplicate ksu_handle_setresuid"
    fi
else
    echo "fix-susfs-compat: setuid_hook.c not found — skipping"
fi

# ---------------------------------------------------------------------------
# Fix 7: Android 14 6.1 Pixel/common SUSFS 2.1 strict-context fallout
# The upstream 50_ patch is close to this tree but misses a few no-fuzz
# contexts in exec.c, proc/base.c, and proc/task_mmu.c. Apply the missing
# hunks explicitly, remove only matching reject files, and repair the upstream
# open_redirect maps helper so the spoofed pathname pointer reaches caller.
# ---------------------------------------------------------------------------
if [ "$ANDROID_VER" = "android14" ] && [ "$KERNEL_VER" = "6.1" ]; then
    python3 - "$KERNEL_DIR" << 'PYEOF'
import sys
from pathlib import Path

root = Path(sys.argv[1])

def read(path):
    return path.read_text()

def write(path, text):
    path.write_text(text)

def unlink_reject(path, required):
    rej = Path(str(path) + ".rej")
    if not rej.exists():
        return
    text = read(path)
    for needle in required:
        if needle not in text:
            raise SystemExit(f"fix-susfs-compat: refusing to remove {rej}, missing {needle!r}")
    rej.unlink()
    print(f"fix-susfs-compat: removed repaired reject {rej}")

exec_c = root / "fs/exec.c"
if exec_c.exists():
    unlink_reject(exec_c, ["#include <linux/susfs_def.h>", "ksu_handle_execveat_sucompat"])

base_c = root / "fs/proc/base.c"
if base_c.exists():
    text = read(base_c)
    old = "#ifdef CONFIG_KSU_SUSFS_SUS_MAP\n#include <linux/susfs_def.h>\n#endif\n\n#include <trace/events/oom.h>"
    new = "#if defined(CONFIG_KSU_SUSFS_SUS_MAP) || defined(CONFIG_KSU_SUSFS_OPEN_REDIRECT)\n#include <linux/susfs_def.h>\n#endif\n\n#include <trace/events/oom.h>"
    if old in text and new not in text:
        write(base_c, text.replace(old, new, 1))
        print("fix-susfs-compat: widened proc/base.c susfs_def include guard")
    unlink_reject(base_c, ["CONFIG_KSU_SUSFS_OPEN_REDIRECT", "susfs_open_redirect_spoof_do_proc_readlink"])

task_mmu = root / "fs/proc/task_mmu.c"
if task_mmu.exists():
    text = read(task_mmu)
    text = text.replace(
        "extern int susfs_open_redirect_spoof_show_map_vma(struct inode *inode, unsigned long *out_ino, dev_t *out_dev, char *spoofed_name);",
        "extern int susfs_open_redirect_spoof_show_map_vma(struct inode *inode, unsigned long *out_ino, dev_t *out_dev, char **spoofed_name);",
        1,
    )
    if "char *spoofed_redirected_name = NULL;" not in text:
        text = text.replace(
            "\tconst char *name = NULL;\n\n\tif (file) {",
            "\tconst char *name = NULL;\n#ifdef CONFIG_KSU_SUSFS_OPEN_REDIRECT\n\tchar *spoofed_redirected_name = NULL;\n#endif // #ifdef CONFIG_KSU_SUSFS_OPEN_REDIRECT\n\n\tif (file) {",
            1,
        )
    if "SUSFS_IS_INODE_OPEN_REDIRECT(inode)" not in text:
        text = text.replace(
            "\tif (file) {\n\t\tstruct inode *inode = file_inode(vma->vm_file);\n\t\tdev = inode->i_sb->s_dev;",
            "\tif (file) {\n\t\tstruct inode *inode = file_inode(vma->vm_file);\n#ifdef CONFIG_KSU_SUSFS_OPEN_REDIRECT\n\t\tif (SUSFS_IS_INODE_OPEN_REDIRECT(inode)) {\n\t\t\tif (!susfs_open_redirect_spoof_show_map_vma(inode, &ino, &dev, &spoofed_redirected_name)) {\n\t\t\t\tpgoff = ((loff_t)vma->vm_pgoff) << PAGE_SHIFT;\n\t\t\t\tgoto orig_flow;\n\t\t\t}\n\t\t}\n#endif // #ifdef CONFIG_KSU_SUSFS_OPEN_REDIRECT\n#ifdef CONFIG_KSU_SUSFS_SUS_MAP\n\t\tif (SUSFS_IS_INODE_SUS_MAP(inode))\n\t\t\treturn;\n#endif // #ifdef CONFIG_KSU_SUSFS_SUS_MAP\n\t\tdev = inode->i_sb->s_dev;",
            1,
        )
    if "susfs_sus_kstat_spoof_show_map_vma(inode, &dev, &ino);" not in text:
        text = text.replace(
            "\t\tino = inode->i_ino;\n\t\tpgoff = ((loff_t)vma->vm_pgoff) << PAGE_SHIFT;\n\t}\n\n\tstart = vma->vm_start;",
            "\t\tino = inode->i_ino;\n\t\tpgoff = ((loff_t)vma->vm_pgoff) << PAGE_SHIFT;\n#ifdef CONFIG_KSU_SUSFS_SUS_KSTAT\n\t\tsusfs_sus_kstat_spoof_show_map_vma(inode, &dev, &ino);\n#endif // #ifdef CONFIG_KSU_SUSFS_SUS_KSTAT\n\t}\n\n#ifdef CONFIG_KSU_SUSFS_OPEN_REDIRECT\norig_flow:\n#endif // #ifdef CONFIG_KSU_SUSFS_OPEN_REDIRECT\n\n\tstart = vma->vm_start;",
            1,
        )
    if "if (vma->vm_file) {\n\t\tif (SUSFS_IS_INODE_SUS_MAP(file_inode(vma->vm_file)))\n\t\t\treturn 0;" not in text:
        text = text.replace(
            "\tstruct vm_area_struct *vma = get_data_vma(v);\n\tstruct mem_size_stats mss;\n\n\tmemset(&mss, 0, sizeof(mss));",
            "\tstruct vm_area_struct *vma = get_data_vma(v);\n\tstruct mem_size_stats mss;\n\n#ifdef CONFIG_KSU_SUSFS_SUS_MAP\n\tif (vma->vm_file) {\n\t\tif (SUSFS_IS_INODE_SUS_MAP(file_inode(vma->vm_file)))\n\t\t\treturn 0;\n\t}\n#endif // #ifdef CONFIG_KSU_SUSFS_SUS_MAP\n\n\tmemset(&mss, 0, sizeof(mss));",
            1,
        )
    write(task_mmu, text)
    unlink_reject(task_mmu, [
        "char *spoofed_redirected_name = NULL;",
        "SUSFS_IS_INODE_OPEN_REDIRECT(inode)",
        "SUSFS_IS_INODE_SUS_MAP(inode)",
        "susfs_sus_kstat_spoof_show_map_vma(inode, &dev, &ino);",
        "orig_flow:",
    ])

susfs_c = root / "fs/susfs.c"
if susfs_c.exists():
    text = read(susfs_c)
    if "susfs_open_redirect_spoof_show_map_vma(struct inode *inode, unsigned long *out_ino, dev_t *out_dev, char **spoofed_name)" not in text:
        text = text.replace(
            "susfs_open_redirect_spoof_show_map_vma(struct inode *inode, unsigned long *out_ino, dev_t *out_dev, char *spoofed_name)",
            "susfs_open_redirect_spoof_show_map_vma(struct inode *inode, unsigned long *out_ino, dev_t *out_dev, char **spoofed_name)",
            1,
        )
        text = text.replace("if (spoofed_name) {", "if (*spoofed_name) {", 1)
        text = text.replace("spoofed_name = kzalloc(SUSFS_MAX_LEN_PATHNAME, GFP_KERNEL);", "*spoofed_name = kzalloc(SUSFS_MAX_LEN_PATHNAME, GFP_KERNEL);", 1)
        text = text.replace("if (!spoofed_name) {", "if (!*spoofed_name) {", 1)
        text = text.replace("strncpy(spoofed_name, entry->info.redirected_pathname, SUSFS_MAX_LEN_PATHNAME - 1);", "strncpy(*spoofed_name, entry->info.redirected_pathname, SUSFS_MAX_LEN_PATHNAME - 1);", 1)
        write(susfs_c, text)
        print("fix-susfs-compat: repaired susfs open_redirect show_map_vma pointer return")
PYEOF
fi

echo "fix-susfs-compat: done"
exit 0
