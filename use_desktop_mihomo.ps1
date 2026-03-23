param(
    [string]$Server = '192.168.137.1:7890',
    [switch]$ShowNotification
)

$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\mihomo_common.ps1"

try {
    Invoke-RemoteSystemProxyMode -Server $Server -ShowNotification:$ShowNotification
}
catch {
    Write-Host "❌ 远端代理模式切换失败: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
