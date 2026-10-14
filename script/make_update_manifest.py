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
    "notes": "修复设备切换或读取超时后再次连入时未重新发现机型的问题；实体显示器关闭时仍可使用远程主屏，并保留原桌面恢复记录；菜单打开时继续检查连接，恢复提示中显示已识别设备。",
}
(directory / "PadDisplay-update.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
