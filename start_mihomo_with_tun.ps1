param(
    [switch]$ShowNotification
)

$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\mihomo_common.ps1"

try {
    Invoke-TunMode -ShowNotification:$ShowNotification
}
catch {
    Write-Host "❌ TUN 模式切换失败: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
