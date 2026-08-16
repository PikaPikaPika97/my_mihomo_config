[CmdletBinding(DefaultParameterSetName = 'State')]
param(
    [Parameter(Position = 0, ParameterSetName = 'State')]
    [ValidateSet('LocalSystemProxy', 'LocalTun', 'Direct', 'RemoteProxy', 'Stopped')]
    [string]$State,

    [Parameter(Mandatory, ParameterSetName = 'Toggle')]
    [switch]$ToggleLocal,

    [Parameter(ParameterSetName = 'State')]
    [string]$RemoteServer,

    [switch]$ShowNotification
)

$ErrorActionPreference = 'Stop'

function Show-MihomoCommandNotification {
    param(
        [Parameter(Mandatory)]
        [string]$Title,
        [Parameter(Mandatory)]
        [string]$Message,
        [Parameter(Mandatory)]
        [ValidateSet('Information', 'Error')]
        [string]$Icon
    )

    try {
        $null = Add-Type -AssemblyName System.Windows.Forms
        $messageBoxIcon = [System.Windows.Forms.MessageBoxIcon]::$Icon
        [System.Windows.Forms.MessageBox]::Show(
            $Message,
            $Title,
            [System.Windows.Forms.MessageBoxButtons]::OK,
            $messageBoxIcon
        ) | Out-Null
    }
    catch {
        Write-Warning "无法显示通知: $($_.Exception.Message)"
    }
}

function Get-MihomoStateMessage {
    param(
        [Parameter(Mandatory)]
        [string]$ReachedState,
        [string]$RemoteEndpoint
    )

    switch ($ReachedState) {
        'LocalSystemProxy' { return '已进入本机系统代理状态。' }
        'LocalTun' { return '已进入本机 TUN 状态。' }
        'Direct' { return '已进入直连状态；本机 mihomo 内核保持运行。' }
        'RemoteProxy' { return "已进入远端代理状态: $RemoteEndpoint" }
        'Stopped' { return '已进入停止状态；本机 mihomo 内核已停止。' }
        default { return "已进入目标代理状态: $ReachedState" }
    }
}

try {
    Import-Module "$PSScriptRoot\scripts\windows\MihomoControl.psm1" -Force

    if ($ToggleLocal) {
        $reachedState = Switch-MihomoLocalMode
    }
    elseif ($PSBoundParameters.ContainsKey('State')) {
        $stateParameters = @{ State = $State }
        if ($PSBoundParameters.ContainsKey('RemoteServer')) {
            $stateParameters.RemoteServer = $RemoteServer
        }
        $reachedState = Set-MihomoTargetState @stateParameters
    }
    else {
        throw '必须显式提供 -State 或 -ToggleLocal；未修改当前状态。'
    }

    $message = Get-MihomoStateMessage -ReachedState $reachedState -RemoteEndpoint $RemoteServer
    Write-Host "✅ $message" -ForegroundColor Green
    if ($ShowNotification) {
        Show-MihomoCommandNotification -Title 'mihomo 代理状态' -Message $message -Icon Information
    }
    exit 0
}
catch {
    $message = $_.Exception.Message
    Write-Host "❌ $message" -ForegroundColor Red
    if ($ShowNotification) {
        Show-MihomoCommandNotification -Title 'mihomo 代理状态切换失败' -Message $message -Icon Error
    }
    exit 1
}
