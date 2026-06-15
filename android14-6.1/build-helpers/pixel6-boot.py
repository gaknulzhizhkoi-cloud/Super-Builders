#!/usr/bin/env python3
"""Build and verify a Pixel 6 boot image v4 containing a legacy-LZ4 kernel."""

import argparse
import pathlib
import struct
import subprocess
import tempfile

BOOT_MAGIC = b"ANDROID!"
LZ4_LEGACY_MAGIC = b"\x02\x21\x4c\x18"
HEADER_SIZE = 1584
HEADER_VERSION = 4
PAGE_SIZE = 4096
BOOT_SIZE = 64 * 1024 * 1024


def align(value: int, alignment: int) -> int:
    return (value + alignment - 1) // alignment * alignment


def build(image: pathlib.Path, output: pathlib.Path) -> None:
    with tempfile.TemporaryDirectory() as temp_dir:
        compressed = pathlib.Path(temp_dir) / "Image.lz4"
        subprocess.run(["lz4", "-l", "-9", "-f", str(image), str(compressed)], check=True)
        kernel = compressed.read_bytes()
    if not kernel.startswith(LZ4_LEGACY_MAGIC):
        raise SystemExit("legacy LZ4 magic is missing")

    header = bytearray(HEADER_SIZE)
    header[0:8] = BOOT_MAGIC
    struct.pack_into("<I", header, 8, len(kernel))
    struct.pack_into("<I", header, 12, 0)
    struct.pack_into("<I", header, 16, 0)
    struct.pack_into("<I", header, 20, HEADER_SIZE)
    struct.pack_into("<I", header, 40, HEADER_VERSION)
    struct.pack_into("<I", header, HEADER_SIZE - 4, 0)

    boot = header + bytes(PAGE_SIZE - len(header)) + kernel
    boot += bytes(align(len(boot), PAGE_SIZE) - len(boot))
    if len(boot) > BOOT_SIZE:
        raise SystemExit(f"boot image exceeds {BOOT_SIZE} bytes")
    output.write_bytes(boot + bytes(BOOT_SIZE - len(boot)))


def verify(boot_path: pathlib.Path, expected_release: str) -> None:
    boot = boot_path.read_bytes()
    if len(boot) != BOOT_SIZE or boot[0:8] != BOOT_MAGIC:
        raise SystemExit("invalid boot image size or ANDROID! magic")
    kernel_size = struct.unpack_from("<I", boot, 8)[0]
    ramdisk_size = struct.unpack_from("<I", boot, 12)[0]
    header_size = struct.unpack_from("<I", boot, 20)[0]
    header_version = struct.unpack_from("<I", boot, 40)[0]
    signature_size = struct.unpack_from("<I", boot, HEADER_SIZE - 4)[0]
    kernel = boot[PAGE_SIZE : PAGE_SIZE + kernel_size]
    if ramdisk_size != 0 or signature_size != 0:
        raise SystemExit(f"unexpected payload sizes: ramdisk={ramdisk_size} signature={signature_size}")
    if header_size != HEADER_SIZE or header_version != HEADER_VERSION:
        raise SystemExit(f"unexpected boot header: size={header_size} version={header_version}")
    if not kernel.startswith(LZ4_LEGACY_MAGIC):
        raise SystemExit("legacy LZ4 magic is missing")

    with tempfile.TemporaryDirectory() as temp_dir:
        compressed = pathlib.Path(temp_dir) / "Image.lz4"
        decompressed = pathlib.Path(temp_dir) / "Image"
        compressed.write_bytes(kernel)
        subprocess.run(["lz4", "-d", "-f", str(compressed), str(decompressed)], check=True)
        image = decompressed.read_bytes()
    if expected_release.encode() not in image:
        raise SystemExit(f"expected release not found: {expected_release}")
    print(f"verified {boot_path}: size={len(boot)} kernel_size={kernel_size} header=v{header_version} release={expected_release}")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("command", choices=("build", "verify"))
    parser.add_argument("--image", type=pathlib.Path)
    parser.add_argument("--boot", required=True, type=pathlib.Path)
    parser.add_argument("--expected-release", default="")
    args = parser.parse_args()
    if args.command == "build":
        if not args.image:
            parser.error("--image is required for build")
        build(args.image, args.boot)
    else:
        if not args.expected_release:
            parser.error("--expected-release is required for verify")
        verify(args.boot, args.expected_release)


if __name__ == "__main__":
    main()
