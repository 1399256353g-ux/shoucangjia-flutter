#!/usr/bin/env python3
"""I4：消除 iOS 启动图/转场时的白色色块。

`flutter create` 生成的 LaunchScreen.storyboard 默认是纯白背景，App 首帧
（尤其是 `ready == false` 的加载帧）在 iOS 上滑返回/切换时会把这块白色
露在图标下方。本脚本把启动图改成与 App 默认主题一致的深色，并补齐
LaunchImage 资源；脚本可重复执行，已打过补丁时不会重复插入。

用法：
    python3 tool/ios_surface.py --project ios
    python3 tool/ios_surface.py --self-test
"""

from __future__ import annotations

import argparse
import json
import plistlib
import re
import struct
import sys
import tempfile
import zlib
from pathlib import Path

DARK = (0x10, 0x14, 0x18)  # 与 kBootBackground / deepblue 背景一致
COLOR_TAG = (
    '<color key="backgroundColor" red="0.062745" green="0.078431" '
    'blue="0.094118" alpha="1" colorSpace="custom" customColorSpace="sRGB"/>'
)


def png_bytes(width: int, height: int, rgb: tuple[int, int, int]) -> bytes:
    row = b"\x00" + bytes(rgb) * width
    raw = row * height

    def chunk(kind: bytes, data: bytes) -> bytes:
        return (
            struct.pack(">I", len(data))
            + kind
            + data
            + struct.pack(">I", zlib.crc32(kind + data) & 0xFFFFFFFF)
        )

    ihdr = struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0)
    return (
        b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", ihdr)
        + chunk(b"IDAT", zlib.compress(raw, 9))
        + chunk(b"IEND", b"")
    )


def patch_storyboard(path: Path) -> None:
    text = path.read_text(encoding="utf-8")
    if COLOR_TAG in text:
        return
    text, count = re.subn(
        r'<color key="backgroundColor"[^>]*/>', COLOR_TAG, text, count=1
    )
    if count == 0:
        m = re.search(r"<view key=\"view\"[^>]*>", text)
        if m is None:
            raise RuntimeError(f"LaunchScreen 中找不到根 view：{path}")
        text = text[: m.end()] + "\n" + COLOR_TAG + text[m.end() :]
    # 启动图资源保持居中，不拉伸变形。
    text = text.replace(
        'contentMode="center" image="LaunchImage"',
        'contentMode="scaleAspectFit" image="LaunchImage"',
    )
    if COLOR_TAG not in text:
        raise RuntimeError("启动图背景色写入失败")
    path.write_text(text, encoding="utf-8")


def write_launch_image(imageset: Path) -> None:
    imageset.mkdir(parents=True, exist_ok=True)
    for scale, size in (("1x", 1), ("2x", 2), ("3x", 3)):
        name = "LaunchImage.png" if scale == "1x" else f"LaunchImage@{scale}.png"
        (imageset / name).write_bytes(png_bytes(size, size, DARK))
    contents = {
        "images": [
            {"filename": "LaunchImage.png", "idiom": "universal", "scale": "1x"},
            {"filename": "LaunchImage@2x.png", "idiom": "universal", "scale": "2x"},
            {"filename": "LaunchImage@3x.png", "idiom": "universal", "scale": "3x"},
        ],
        "info": {"author": "xcode", "version": 1},
    }
    (imageset / "Contents.json").write_text(
        json.dumps(contents, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )


def patch_info_plist(path: Path) -> None:
    data = plistlib.loads(path.read_bytes())
    # 深色启动图配浅色状态栏；启动阶段不依赖 Flutter 的 overlay 设置。
    data["UIStatusBarStyle"] = "UIStatusBarStyleLightContent"
    data["UIViewControllerBasedStatusBarAppearance"] = False
    path.write_bytes(plistlib.dumps(data, sort_keys=False))


def patch_project(project: Path) -> None:
    storyboard = project / "Runner" / "Base.lproj" / "LaunchScreen.storyboard"
    if not storyboard.exists():
        raise RuntimeError(f"找不到启动图：{storyboard}")
    patch_storyboard(storyboard)
    write_launch_image(project / "Runner" / "Assets.xcassets" / "LaunchImage.imageset")
    info = project / "Runner" / "Info.plist"
    if not info.exists():
        raise RuntimeError(f"找不到 Info.plist：{info}")
    patch_info_plist(info)
    print(f"iOS 启动图已改为深色 #{DARK[0]:02X}{DARK[1]:02X}{DARK[2]:02X}")


def self_test() -> None:
    fixture = """<?xml version="1.0" encoding="UTF-8"?>
<document launchScreen="YES">
  <scenes><scene><objects><viewController><view key="view" contentMode="scaleToFill" id="v">
    <subviews><imageView contentMode="center" image="LaunchImage" id="i"/></subviews>
    <color key="backgroundColor" red="1" green="1" blue="1" alpha="1" colorSpace="custom" customColorSpace="sRGB"/>
  </view></viewController></objects></scene></scenes>
</document>
"""
    info = {"CFBundleName": "Dizi", "UILaunchStoryboardName": "LaunchScreen"}
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        project = root / "ios"
        (project / "Runner" / "Base.lproj").mkdir(parents=True)
        storyboard = project / "Runner" / "Base.lproj" / "LaunchScreen.storyboard"
        storyboard.write_text(fixture, encoding="utf-8")
        (project / "Runner" / "Info.plist").write_bytes(plistlib.dumps(info))
        patch_project(project)
        text = storyboard.read_text(encoding="utf-8")
        assert COLOR_TAG in text, "背景色未替换"
        assert "0.062745" in text and "1.000000" not in text, "背景仍是白色"
        assert 'contentMode="scaleAspectFit"' in text
        # 重复执行必须幂等，不能插入两块颜色。
        patch_project(project)
        assert storyboard.read_text(encoding="utf-8").count("backgroundColor") == 1
        imageset = project / "Runner" / "Assets.xcassets" / "LaunchImage.imageset"
        for name, size in (
            ("LaunchImage.png", 1),
            ("LaunchImage@2x.png", 2),
            ("LaunchImage@3x.png", 3),
        ):
            raw = (imageset / name).read_bytes()
            assert raw.startswith(b"\x89PNG\r\n\x1a\n")
            assert struct.unpack(">II", raw[16:24]) == (size, size)
        patched = plistlib.loads((project / "Runner" / "Info.plist").read_bytes())
        assert patched["UIStatusBarStyle"] == "UIStatusBarStyleLightContent"
        assert patched["CFBundleName"] == "Dizi"
    print("ios_surface self-test OK")


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--project", default="ios", help="flutter create 生成的 ios 目录")
    ap.add_argument("--self-test", action="store_true")
    args = ap.parse_args()
    if args.self_test:
        self_test()
        return 0
    patch_project(Path(args.project))
    return 0


if __name__ == "__main__":
    sys.exit(main())
