# /// script
# requires-python = ">=3.10"
# dependencies = [
#     "ruamel-yaml>=0.19.1",
# ]
# ///

from __future__ import annotations

import argparse
import copy
import sys
from collections.abc import Mapping, Sequence
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


def assert_no_merge_keys(value, path="config") -> None:
    """Reject merge keys anywhere in the local overlay."""
    if isinstance(value, Mapping):
        # ruamel resolves ``<<`` into _yaml_merge, so a plain key scan misses it.
        if getattr(value, "_yaml_merge", None):
            raise ValueError(f"{path} 不支持 YAML merge key <<；请写显式键。")
        for key, child in value.items():
            if key == "<<":
                raise ValueError(f"{path} 不支持 YAML merge key <<；请写显式键。")
            assert_no_merge_keys(child, f"{path}.{key}")
    elif isinstance(value, Sequence) and not isinstance(value, (str, bytes)):
        for index, child in enumerate(value):
            assert_no_merge_keys(child, f"{path}[{index}]")


def deep_merge(base, overlay):
    """Merge overlay into base in place.

    The template uses YAML anchors/merge keys.  Deep-copying the base breaks
    ruamel's alias relationships and makes the dumper expand ``<<: *domain``
    into a merge key plus duplicated fields.  The template is freshly loaded
    for each run, so mutating it preserves anchors, aliases and comments.
    """
    if not isinstance(base, Mapping) or not isinstance(overlay, Mapping):
        raise ValueError("配置的顶层结构必须是映射。")

    assert_no_merge_keys(overlay)

    explicit = dict(base.non_merged_items()) if hasattr(base, "non_merged_items") else base
    for key, value in overlay.items():
        if key in explicit and isinstance(explicit[key], Mapping) and isinstance(value, Mapping):
            deep_merge(explicit[key], value)
        elif key in base and isinstance(base[key], Mapping) and isinstance(value, Mapping):
            # The key is inherited through <<; merge a detached copy so fields
            # not mentioned by the overlay are not discarded.
            inherited = copy.deepcopy(base[key])
            deep_merge(inherited, value)
            base[key] = inherited
        else:
            # Assigning an explicit key overrides a value inherited via <<.
            base[key] = copy.deepcopy(value)
    return base


def validate_config(config) -> None:
    # 生成出来的配置必须至少带有一个可用的代理提供器，否则 mihomo 无法正常拉取节点。
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
    # 先写临时文件，再一次性替换目标文件，避免中途失败留下半截配置。
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
