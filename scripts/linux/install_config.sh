#!/usr/bin/env bash
# macOS 和 Linuxbrew 共享同一套部署逻辑。
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "$SCRIPT_DIR/../unix/install_config.sh" "$@"
