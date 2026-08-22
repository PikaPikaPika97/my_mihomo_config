#!/usr/bin/env bash
#
# Linux 终端代理开关（兼容 Bash 和 Zsh；环境变量 http_proxy / https_proxy / all_proxy / no_proxy）。
#
# 使用方法：需要 source 加载（环境变量只对当前 shell 生效）
#   source scripts/linux/terminal_proxy.sh  # Bash 或 Zsh
# 然后：
#   proxy_on [端口]    开启终端代理，默认 127.0.0.1:7890
#   proxy_off          关闭终端代理
#   proxy_status       查看当前终端代理
# 建议写入 ~/.zshrc；端口可用 MIHOMO_PROXY_PORT 环境变量覆盖。

MIHOMO_BYPASS_PLATFORM="linux"
if [ -n "${ZSH_VERSION:-}" ]; then
    SCRIPT_DIR="$(cd "$(dirname "${(%):-%N}")" && pwd)"
else
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fi
MIHOMO_RESOLVE_PROXY_BYPASS_SCRIPT="$SCRIPT_DIR/../resolve_proxy_bypass.py"
source "$SCRIPT_DIR/../unix/terminal_proxy.sh"
