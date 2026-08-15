#!/usr/bin/env bash
#
# macOS 终端代理开关（环境变量 http_proxy / https_proxy / all_proxy / no_proxy）。
#
# 使用方法：需要 source 加载（环境变量只对当前 shell 生效）
#   source scripts/macos/terminal_proxy.sh
# 然后：
#   proxy_on [端口]    开启终端代理，默认 127.0.0.1:7890
#   proxy_off          关闭终端代理
#   proxy_status       查看当前终端代理
# 建议写入 ~/.zshrc 或 ~/.bashrc；端口可用 MIHOMO_PROXY_PORT 环境变量覆盖。

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RESOLVE="$SCRIPT_DIR/../resolve_proxy_bypass.py"

# 直接执行（而非 source）时提示；source 时不触发。
if [[ -z "$ZSH_VERSION" && "${BASH_SOURCE[0]}" == "$0" ]]; then
    echo "此脚本需被 source 使用: source ${BASH_SOURCE[0]}" >&2
    exit 0
fi

proxy_on() {
    local host="127.0.0.1"
    local port="${1:-${MIHOMO_PROXY_PORT:-7890}}"

    export http_proxy="http://$host:$port"
    export https_proxy="http://$host:$port"
    export all_proxy="socks5://$host:$port"

    # no_proxy 复用统一的 bypass 数据源（macOS 输出为每行一项，转成逗号分隔）。
    if command -v uv >/dev/null 2>&1; then
        local no_proxy_value
        no_proxy_value="$(uv run --script "$RESOLVE" --platform macos | paste -sd, -)"
        export no_proxy="$no_proxy_value"
        export NO_PROXY="$no_proxy_value"
    else
        echo "警告: 未找到 uv，跳过 no_proxy 设置" >&2
    fi

    echo "终端代理已开启: $host:$port"
}

proxy_off() {
    unset http_proxy https_proxy all_proxy no_proxy NO_PROXY 2>/dev/null || true
    echo "终端代理已关闭"
}

proxy_status() {
    echo "http_proxy=${http_proxy:-}"
    echo "https_proxy=${https_proxy:-}"
    echo "all_proxy=${all_proxy:-}"
    echo "no_proxy=${no_proxy:-}"
}
