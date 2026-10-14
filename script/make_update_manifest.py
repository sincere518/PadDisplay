#!/usr/bin/env python3
"""Generate the update metadata for this release's ZIP; publishing remains explicit."""
import hashlib
import json
import sys
from pathlib import Path
from urllib.parse import urlsplit

version, build, destination, base_url = sys.argv[1:]
url = urlsplit(base_url)
if url.scheme != "https" or not url.hostname or url.username or url.password or url.query or url.fragment:
    raise SystemExit("RELEASE_BASE_URL 必须是 HTTPS 发布附件目录。")
directory = Path(destination)
filename = f"PadDisplay-{version}-arm64.zip"
manifest = {
    "version": version,
    "build": int(build),
    "minimumSystemVersion": "14.0",
    "downloadURL": f"{base_url.rstrip('/')}/{filename}",
    "sha256": hashlib.sha256((directory / filename).read_bytes()).hexdigest(),
    "notes": "固定设备屏幕身份；还原显示模式与普通窗口；显示预设和可视区域；主屏／扩展策略；菜单栏收藏、快捷键；连接助手、配置备份；DMG 与应用内更新。",
}
(directory / "PadDisplay-update.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
