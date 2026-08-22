#!/usr/bin/env bash
#
# Unix 终端代理开关（兼容 Bash 和 Zsh）。调用方必须在 source 前设置
# MIHOMO_BYPASS_PLATFORM 和 MIHOMO_RESOLVE_PROXY_BYPASS_SCRIPT。

if [ -z "${MIHOMO_BYPASS_PLATFORM:-}" ] || [ -z "${MIHOMO_RESOLVE_PROXY_BYPASS_SCRIPT:-}" ]; then
    printf '错误: 必须设置 MIHOMO_BYPASS_PLATFORM 和 MIHOMO_RESOLVE_PROXY_BYPASS_SCRIPT\n' >&2
    return 1
fi

proxy_on() {
    local host="127.0.0.1"
    local port="${1:-${MIHOMO_PROXY_PORT:-7890}}"

    export http_proxy="http://$host:$port"
    export https_proxy="http://$host:$port"
    export all_proxy="socks5://$host:$port"
    export HTTP_PROXY="$http_proxy"
    export HTTPS_PROXY="$https_proxy"
    export ALL_PROXY="$all_proxy"

    # no_proxy 复用统一的 bypass 数据源（每行一项，转成逗号分隔）。
    if command -v uv >/dev/null 2>&1; then
        local no_proxy_value
        no_proxy_value="$(uv run --script "$MIHOMO_RESOLVE_PROXY_BYPASS_SCRIPT" --platform "$MIHOMO_BYPASS_PLATFORM" | paste -sd, -)"
        export no_proxy="$no_proxy_value"
        export NO_PROXY="$no_proxy_value"
    else
        printf '警告: 未找到 uv，跳过 no_proxy 设置\n' >&2
    fi

    printf '终端代理已开启: %s:%s\n' "$host" "$port"
}

proxy_off() {
    unset http_proxy https_proxy all_proxy no_proxy HTTP_PROXY HTTPS_PROXY ALL_PROXY NO_PROXY 2>/dev/null || true
    printf '终端代理已关闭\n'
}

proxy_status() {
    printf 'http_proxy=%s\n' "${http_proxy:-}"
    printf 'https_proxy=%s\n' "${https_proxy:-}"
    printf 'all_proxy=%s\n' "${all_proxy:-}"
    printf 'HTTP_PROXY=%s\n' "${HTTP_PROXY:-}"
    printf 'HTTPS_PROXY=%s\n' "${HTTPS_PROXY:-}"
    printf 'ALL_PROXY=%s\n' "${ALL_PROXY:-}"
    printf 'no_proxy=%s\n' "${no_proxy:-}"
}
