#!/usr/bin/env python3
"""Small idempotent kernel-source fixes synced from WildKernels upstream."""

import re
import sys
from pathlib import Path


def log(message):
    print(f"[kernel-compat] {message}", flush=True)


def read_version(root):
    makefile = root / "Makefile"
    if not makefile.is_file():
        return None
    text = makefile.read_text(encoding="utf-8", errors="surrogateescape")
    values = {}
    for key in ("VERSION", "PATCHLEVEL", "SUBLEVEL"):
        match = re.search(rf"^{key}\s*=\s*(\d+)", text, re.MULTILINE)
        if not match:
            return None
        values[key] = int(match.group(1))
    return values["VERSION"], values["PATCHLEVEL"], values["SUBLEVEL"]


def fix_task_struct_kabi(root, version):
    """Reorder the 6.1.157+ task_struct KABI slots to the CE 5 layout."""
    if version[:2] != (6, 1) or version[2] < 157:
        return

    path = root / "include/linux/sched.h"
    if not path.is_file():
        return
    text = path.read_text(encoding="utf-8", errors="surrogateescape")

    old = (
        "\tANDROID_KABI_USE(1, unsigned int saved_state);\n"
        "#ifdef CONFIG_SLIM_SCHED\n"
        "\tANDROID_KABI_USE(2, unsigned long sched_prop);\n"
        "\tANDROID_KABI_USE(3, struct sched_ext_entity *scx);\n"
        "\tANDROID_KABI_USE(4, struct task_dma_buf_info *dmabuf_info);\n"
        "#else\n"
        "\tANDROID_KABI_USE(2, struct task_dma_buf_info *dmabuf_info);\n"
        "\tANDROID_KABI_RESERVE(3);\n"
        "\tANDROID_KABI_RESERVE(4);\n"
        "#endif\n"
    )
    new = (
        "\tANDROID_KABI_USE(1, unsigned int saved_state);\n"
        "\tANDROID_KABI_USE(2, struct task_dma_buf_info *dmabuf_info);\n"
        "#ifdef CONFIG_SLIM_SCHED\n"
        "\tANDROID_KABI_USE(3, unsigned long sched_prop);\n"
        "\tANDROID_KABI_USE(4, struct sched_ext_entity *scx);\n"
        "#else\n"
        "\tANDROID_KABI_RESERVE(3);\n"
        "\tANDROID_KABI_RESERVE(4);\n"
        "#endif\n"
    )

    if new in text:
        log("task_struct KABI alignment already applied")
        return
    if old not in text:
        log("task_struct KABI layout not found; skip")
        return

    path.write_text(text.replace(old, new, 1), encoding="utf-8", errors="surrogateescape")
    log("aligned task_struct KABI slots for 6.1.157+")


def drop_test_task_ux_export(root, version):
    """Vendor modules already export test_task_ux; avoid a duplicate export."""
    if version[:2] != (6, 1) or version[2] < 141:
        return

    path = root / "block/blk-mq.c"
    if not path.is_file():
        return
    text = path.read_text(encoding="utf-8", errors="surrogateescape")
    if "EXPORT_SYMBOL_GPL(test_task_ux);" not in text:
        log("test_task_ux export not present; skip")
        return

    pattern = re.compile(
        r"^[ \t]*EXPORT_SYMBOL_GPL\(test_task_ux\);[ \t]*(?:\n|$)",
        re.MULTILINE,
    )
    new, count = pattern.subn("", text, count=1)
    if count == 0:
        log("test_task_ux export not matched; skip")
        return

    path.write_text(new, encoding="utf-8", errors="surrogateescape")
    log("removed duplicate test_task_ux export")


def fix_mtk_firmware_dotdot(root, version, soc):
    """Allow MTK tfa98xx firmware under odm paths without disabling the guard."""
    if version[:2] != (5, 10) or version[2] < 226:
        return
    if not (soc.startswith("dimensity") or soc.startswith("helio")):
        return

    path = root / "drivers/base/firmware_loader/main.c"
    if not path.is_file():
        return
    text = path.read_text(encoding="utf-8", errors="surrogateescape")
    if "name_contains_dotdot" not in text:
        return
    if "name_is_confined_vendor_firmware" in text:
        log("MTK firmware dotdot exception already applied")
        return

    anchor = "static bool name_contains_dotdot("
    condition = "\tif (name_contains_dotdot(name)) {"
    if text.count(anchor) != 1 or text.count(condition) != 1:
        log("MTK firmware dotdot layout not matched; skip")
        return

    helper = (
        "static bool name_is_confined_vendor_firmware(const char *name)\n"
        "{\n"
        "\tstatic const char * const allowed_roots[] = {\n"
        "\t\t\"../../odm/firmware/\",\n"
        "\t\t\"../odm/firmware/\",\n"
        "\t};\n"
        "\tsize_t i;\n"
        "\n"
        "\tfor (i = 0; i < ARRAY_SIZE(allowed_roots); i++) {\n"
        "\t\tsize_t len = strlen(allowed_roots[i]);\n"
        "\n"
        "\t\tif (strncmp(name, allowed_roots[i], len) != 0)\n"
        "\t\t\tcontinue;\n"
        "\t\tif (strstr(name + len, \"..\") != NULL)\n"
        "\t\t\treturn false;\n"
        "\t\treturn true;\n"
        "\t}\n"
        "\n"
        "\treturn false;\n"
        "}\n\n"
    )
    replacement = (
        "\tif (name_contains_dotdot(name) &&\n"
        "\t    !name_is_confined_vendor_firmware(name)) {"
    )

    text = text.replace(anchor, helper + anchor, 1)
    text = text.replace(condition, replacement, 1)
    path.write_text(text, encoding="utf-8", errors="surrogateescape")
    log("allowed MTK tfa98xx firmware under odm paths")


def main():
    if len(sys.argv) < 2:
        print("usage: apply_kernel_fixes.py <kernel-root> [soc]", file=sys.stderr)
        return 2

    root = Path(sys.argv[1]).resolve()
    soc = sys.argv[2].lower() if len(sys.argv) > 2 else ""
    version = read_version(root)
    if version is None:
        log("kernel version not found; skip all fixes")
        return 0

    log(f"kernel version: {version[0]}.{version[1]}.{version[2]}, soc: {soc or 'unknown'}")
    fix_task_struct_kabi(root, version)
    drop_test_task_ux_export(root, version)
    fix_mtk_firmware_dotdot(root, version, soc)
    return 0


if __name__ == "__main__":
    sys.exit(main())