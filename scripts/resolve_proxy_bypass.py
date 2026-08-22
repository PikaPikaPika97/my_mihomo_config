# /// script
# requires-python = ">=3.10"
# dependencies = [
#     "ruamel-yaml>=0.19.1",
# ]
# ///

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

from ruamel.yaml import YAML

REPO_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_BYPASS_FILE = REPO_ROOT / "proxy_bypass.yaml"
LOCAL_BYPASS_FILE = REPO_ROOT / "proxy_bypass.local.yaml"

# 私有网段按平台展开；Windows 以 `<local>` 结尾（与旧脚本行为一致），macOS 不使用 `<local>`。
# Linux 的输出用于 no_proxy，因此使用 CIDR 表示私有网段。
PRIVATE_NETWORKS = {
    "windows": [
        "localhost",
        "127.*",
        "10.*",
        *(f"172.{i}.*" for i in range(16, 32)),
        "192.168.*",
        "<local>",
    ],
    "macos": [
        "localhost",
        "127.0.0.1",
        "10.*",
        "172.16.*",
        "192.168.*",
    ],
    "linux": [
        "localhost",
        "127.0.0.1",
        "::1",
        "10.0.0.0/8",
        "172.16.0.0/12",
        "192.168.0.0/16",
    ],
}

DEFAULT_FORMAT = {"windows": "windows", "macos": "lines", "linux": "lines"}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Resolve the proxy bypass list from proxy_bypass.yaml (+ local overrides)."
    )
    parser.add_argument(
        "--platform",
        required=True,
        choices=sorted(DEFAULT_FORMAT),
        help="Target platform (windows, macos, or linux).",
    )
    parser.add_argument(
        "--format",
        choices=["windows", "lines", "json"],
        default=None,
        help="Output format (defaults to the platform default).",
    )
    return parser.parse_args()


def build_yaml() -> YAML:
    yaml = YAML()
    yaml.preserve_quotes = True
    return yaml


def load_data(yaml: YAML, path: Path, *, optional: bool):
    if not path.exists():
        if optional:
            return None
        raise FileNotFoundError(f"配置文件不存在: {path}")
    with path.open("r", encoding="utf-8") as handle:
        data = yaml.load(handle)
    if data is None:
        return {}
    return data


def resolve(platform: str) -> list[str]:
    yaml = build_yaml()
    base = load_data(yaml, DEFAULT_BYPASS_FILE, optional=False) or {}
    local = load_data(yaml, LOCAL_BYPASS_FILE, optional=True) or {}

    if local:
        print(f"已合并本机扩展: {LOCAL_BYPASS_FILE}", file=sys.stderr)

    result: list[str] = []
    seen: set[str] = set()

    def append(items) -> None:
        for item in items:
            item = str(item).strip()
            # no_proxy 使用前导点匹配子域名；`*.example.com` 不是通用语法。
            if platform == "linux" and item.startswith("*."):
                item = item[1:]
            if item and item not in seen:
                seen.add(item)
                result.append(item)

    if base.get("private_networks"):
        append(PRIVATE_NETWORKS[platform])
    append(base.get("domains") or [])
    append(local.get("domains") or [])
    return result


def main() -> int:
    args = parse_args()
    out_format = args.format or DEFAULT_FORMAT[args.platform]
    items = resolve(args.platform)

    if out_format == "windows":
        print(";".join(items))
    elif out_format == "lines":
        print("\n".join(items))
    else:
        print(json.dumps(items, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
