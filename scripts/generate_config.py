from __future__ import annotations

import argparse
import copy
import sys
from collections.abc import Mapping
from pathlib import Path

from ruamel.yaml import YAML


REPO_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_TEMPLATE = REPO_ROOT / "official_config.template.yaml"
DEFAULT_LOCAL = REPO_ROOT / "config.local.yaml"
DEFAULT_OUTPUT = REPO_ROOT / "official_config.yaml"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Merge the tracked mihomo template with local overrides."
    )
    parser.add_argument("--template", type=Path, default=DEFAULT_TEMPLATE)
    parser.add_argument("--local", type=Path, default=DEFAULT_LOCAL)
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
    return parser.parse_args()


def build_yaml() -> YAML:
    yaml = YAML()
    yaml.preserve_quotes = True
    yaml.indent(mapping=2, sequence=4, offset=2)
    yaml.width = 4096
    return yaml


def load_yaml(yaml: YAML, path: Path):
    if not path.exists():
        raise FileNotFoundError(f"配置文件不存在: {path}")
    with path.open("r", encoding="utf-8") as handle:
        data = yaml.load(handle)
    if data is None:
        raise ValueError(f"配置文件为空: {path}")
    return data


def deep_merge(base, overlay):
    if isinstance(base, Mapping) and isinstance(overlay, Mapping):
        merged = copy.deepcopy(base)
        for key, value in overlay.items():
            if key in merged:
                merged[key] = deep_merge(merged[key], value)
            else:
                merged[key] = copy.deepcopy(value)
        return merged
    return copy.deepcopy(overlay)


def validate_config(config) -> None:
    providers = config.get("proxy-providers")
    if not isinstance(providers, Mapping) or not providers:
        raise ValueError("最终配置缺少 proxy-providers。")

    missing_urls = []
    for name, provider in providers.items():
        if isinstance(provider, Mapping) and provider.get("type"):
            url = str(provider.get("url", "")).strip()
            if not url:
                missing_urls.append(name)

    if missing_urls:
        joined = ", ".join(sorted(missing_urls))
        raise ValueError(f"以下 proxy-provider 缺少非空 url: {joined}")


def write_yaml(yaml: YAML, output_path: Path, config) -> None:
    output_path.parent.mkdir(parents=True, exist_ok=True)
    temp_path = output_path.with_suffix(output_path.suffix + ".tmp")
    with temp_path.open("w", encoding="utf-8", newline="\n") as handle:
        yaml.dump(config, handle)
    temp_path.replace(output_path)


def main() -> int:
    args = parse_args()
    yaml = build_yaml()

    try:
        template = load_yaml(yaml, args.template)
        local = load_yaml(yaml, args.local)
        merged = deep_merge(template, local)
        validate_config(merged)
        write_yaml(yaml, args.output, merged)
    except Exception as exc:
        print(f"生成配置失败: {exc}", file=sys.stderr)
        return 1

    print(f"已生成: {args.output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
