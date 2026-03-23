$ErrorActionPreference = 'Stop'

$script:MihomoConfig = @{
    ControllerApi     = 'http://127.0.0.1:9090'
    ApiSecret         = ''
    TaskName          = 'mihomo'
    ProxyPort         = 7890
    RegistryPath      = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings'
    ProcessName       = 'mihomo-windows-amd64'
    StartupTimeoutSec = 15
    RequestTimeoutSec = 3
    RetryCount        = 3
    RetryIntervalMs   = 400
}

$script:ProxyBypassDomains = @(
    '*.edu.cn', 'edu.cn',
    '*.msftconnecttest.com', 'msftconnecttest.com',
    '*.msftncsi.com', 'msftncsi.com'
)

$script:DefaultProxyBypass = @(
    'localhost', '127.*', '10.*',
    '172.16.*', '172.17.*', '172.18.*', '172.19.*', '172.20.*', '172.21.*', '172.22.*', '172.23.*',
    '172.24.*', '172.25.*', '172.26.*', '172.27.*', '172.28.*', '172.29.*', '172.30.*', '172.31.*',
    '192.168.*', '<local>'
)

function Get-MihomoHeaders {
    $headers = @{}
    if ($script:MihomoConfig.ApiSecret) {
        $headers['Authorization'] = "Bearer $($script:MihomoConfig.ApiSecret)"
    }
    return $headers
}

function Write-MihomoStatus {
    param(
        [Parameter(Mandatory)]
        [string]$Message,
        [ValidateSet('Green', 'Yellow', 'Red', 'Cyan', 'DarkGray')]
        [string]$Color = 'Green'
    )

    Write-Host $Message -ForegroundColor $Color
}

function Show-MihomoNotification {
    param(
        [Parameter(Mandatory)]
        [string]$Title,
        [Parameter(Mandatory)]
        [string]$Message,
        [switch]$ShowNotification
    )

    if (-not $ShowNotification) {
        return
    }

    Add-Type -AssemblyName System.Windows.Forms
    [System.Windows.Forms.MessageBox]::Show(
        $Message,
        $Title,
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Information
    ) | Out-Null
}

function Refresh-WinInetProxy {
    rundll32.exe wininet.dll,InternetSetOptionA 0 39 0 0 | Out-Null
    rundll32.exe wininet.dll,InternetSetOptionA 0 37 0 0 | Out-Null
}

function Set-SystemProxyEnabled {
    $proxyOverride = ($script:DefaultProxyBypass + $script:ProxyBypassDomains) -join ';'

    Set-ItemProperty -Path $script:MihomoConfig.RegistryPath -Name ProxyEnable -Value 1
    Set-ItemProperty -Path $script:MihomoConfig.RegistryPath -Name ProxyServer -Value "127.0.0.1:$($script:MihomoConfig.ProxyPort)"
    Set-ItemProperty -Path $script:MihomoConfig.RegistryPath -Name ProxyOverride -Value $proxyOverride
    Refresh-WinInetProxy
}

function Set-SystemProxyDisabled {
    Set-ItemProperty -Path $script:MihomoConfig.RegistryPath -Name ProxyEnable -Value 0
    Set-ItemProperty -Path $script:MihomoConfig.RegistryPath -Name ProxyServer -Value ''
    Refresh-WinInetProxy
}

function Set-SystemProxyServer {
    param(
        [Parameter(Mandatory)]
        [string]$Server
    )

    $proxyOverride = ($script:DefaultProxyBypass + $script:ProxyBypassDomains) -join ';'

    Set-ItemProperty -Path $script:MihomoConfig.RegistryPath -Name ProxyEnable -Value 1
    Set-ItemProperty -Path $script:MihomoConfig.RegistryPath -Name ProxyServer -Value $Server
    Set-ItemProperty -Path $script:MihomoConfig.RegistryPath -Name ProxyOverride -Value $proxyOverride
    Refresh-WinInetProxy
}

function Test-TcpEndpoint {
    param(
        [Parameter(Mandatory)]
        [string]$Server,
        [int]$TimeoutMs = 1500
    )

    $separatorIndex = $Server.LastIndexOf(':')
    if ($separatorIndex -lt 1) {
        throw "代理地址格式无效，应为 host:port: $Server"
    }

    $serverHost = $Server.Substring(0, $separatorIndex)
    if ($serverHost.StartsWith('[') -and $serverHost.EndsWith(']')) {
        $serverHost = $serverHost.Substring(1, $serverHost.Length - 2)
    }

    $portText = $Server.Substring($separatorIndex + 1)
    $port = 0
    if (-not [int]::TryParse($portText, [ref]$port)) {
        throw "代理端口无效: $Server"
    }

    $client = [System.Net.Sockets.TcpClient]::new()
    $asyncResult = $null

    try {
        $asyncResult = $client.BeginConnect($serverHost, $port, $null, $null)
        if (-not $asyncResult.AsyncWaitHandle.WaitOne($TimeoutMs, $false)) {
            return $false
        }

        $client.EndConnect($asyncResult) | Out-Null
        return $client.Connected
    }
    catch {
        return $false
    }
    finally {
        if ($asyncResult) {
            $asyncResult.AsyncWaitHandle.Close()
        }
        $client.Dispose()
    }
}

function Get-SystemProxyEnabled {
    return [bool](Get-ItemPropertyValue -Path $script:MihomoConfig.RegistryPath -Name ProxyEnable)
}

function Test-MihomoControllerAvailable {
    $uri = "$($script:MihomoConfig.ControllerApi)/version"
    $headers = Get-MihomoHeaders

    try {
        $null = Invoke-RestMethod -Uri $uri -Headers $headers -TimeoutSec $script:MihomoConfig.RequestTimeoutSec -Method GET
        return $true
    }
    catch {
        return $false
    }
}

function Wait-MihomoControllerReady {
    param(
        [int]$TimeoutSec = $script:MihomoConfig.StartupTimeoutSec
    )

    $deadline = (Get-Date).AddSeconds($TimeoutSec)
    $uri = "$($script:MihomoConfig.ControllerApi)/version"
    $headers = Get-MihomoHeaders

    while ((Get-Date) -lt $deadline) {
        try {
            $null = Invoke-RestMethod -Uri $uri -Headers $headers -TimeoutSec $script:MihomoConfig.RequestTimeoutSec -Method GET
            return
        }
        catch {
            Start-Sleep -Milliseconds 400
        }
    }

    throw "mihomo 控制器未在 ${TimeoutSec} 秒内就绪: $uri"
}

function Ensure-MihomoRunning {
    $task = Get-ScheduledTask -TaskName $script:MihomoConfig.TaskName
    if ($task.State -ne 'Running') {
        Start-ScheduledTask -TaskName $script:MihomoConfig.TaskName
    }

    Wait-MihomoControllerReady
}

function Set-TunMode {
    param(
        [Parameter(Mandatory)]
        [bool]$Enable
    )

    $body = @{ tun = @{ enable = $Enable } } | ConvertTo-Json -Compress
    $headers = Get-MihomoHeaders
    $uri = "$($script:MihomoConfig.ControllerApi)/configs"

    for ($attempt = 1; $attempt -le $script:MihomoConfig.RetryCount; $attempt++) {
        try {
            $null = Invoke-RestMethod -Uri $uri `
                -Headers $headers `
                -ContentType 'application/json' `
                -Method PATCH `
                -Body $body `
                -TimeoutSec $script:MihomoConfig.RequestTimeoutSec
            return
        }
        catch {
            if ($attempt -eq $script:MihomoConfig.RetryCount) {
                throw
            }
            Start-Sleep -Milliseconds $script:MihomoConfig.RetryIntervalMs
        }
    }
}

function Invoke-SystemProxyMode {
    param([switch]$ShowNotification)

    Ensure-MihomoRunning
    Set-SystemProxyEnabled
    Set-TunMode -Enable $false

    Write-MihomoStatus '✅ mihomo 控制器已就绪' -Color DarkGray
    Write-MihomoStatus "✅ 系统代理已启用 (端口 $($script:MihomoConfig.ProxyPort))"
    Write-MihomoStatus '✅ TUN 模式已禁用'
    Show-MihomoNotification `
        -Title '系统代理模式已启用' `
        -Message "系统代理已启用`n端口: $($script:MihomoConfig.ProxyPort)`nTUN 模式已关闭" `
        -ShowNotification:$ShowNotification
}

function Invoke-TunMode {
    param([switch]$ShowNotification)

    Ensure-MihomoRunning
    Set-SystemProxyDisabled
    Set-TunMode -Enable $true

    Write-MihomoStatus '✅ mihomo 控制器已就绪' -Color DarkGray
    Write-MihomoStatus '✅ 系统代理已关闭'
    Write-MihomoStatus '✅ TUN 模式已启用'
    Show-MihomoNotification `
        -Title 'TUN 模式已启用' `
        -Message "系统代理已关闭`nTUN 模式已启用" `
        -ShowNotification:$ShowNotification
}

function Invoke-SwitchMode {
    param([switch]$ShowNotification)

    if (Get-SystemProxyEnabled) {
        Invoke-TunMode -ShowNotification:$ShowNotification
        return
    }

    Invoke-SystemProxyMode -ShowNotification:$ShowNotification
}

function Invoke-TurnOffSystemProxy {
    param([switch]$ShowNotification)

    Set-SystemProxyDisabled
    Write-MihomoStatus '✅ 系统代理已关闭'
    Show-MihomoNotification `
        -Title '系统代理设置' `
        -Message '系统代理已成功关闭' `
        -ShowNotification:$ShowNotification
}

function Invoke-RemoteSystemProxyMode {
    param(
        [string]$Server = '192.168.137.1:7890',
        [switch]$ShowNotification
    )

    if (-not (Test-TcpEndpoint -Server $Server)) {
        throw "目标代理不可达: $Server"
    }

    Write-MihomoStatus "✅ 已确认远端 mihomo 可达 ($Server)" -Color DarkGray

    if (Test-MihomoControllerAvailable) {
        Set-TunMode -Enable $false
        Write-MihomoStatus '✅ 已确保本机 TUN 模式关闭' -Color DarkGray
    }
    else {
        Write-MihomoStatus 'ℹ️ 本机 mihomo 控制器不可达，跳过 TUN 处理' -Color Yellow
    }

    Set-SystemProxyServer -Server $Server

    Write-MihomoStatus "✅ 系统代理已切换到台式机 mihomo ($Server)"
    Write-MihomoStatus '✅ 当前处于工位模式，本机 mihomo 不作为系统代理出口'
    Show-MihomoNotification `
        -Title '远端代理模式已启用' `
        -Message "系统代理已指向 $Server`n当前处于工位模式" `
        -ShowNotification:$ShowNotification
}

function Invoke-StopMihomo {
    param([switch]$ShowNotification)

    Set-SystemProxyDisabled
    Write-MihomoStatus '✅ 系统代理已关闭'

    $taskStopped = $false
    try {
        $task = Get-ScheduledTask -TaskName $script:MihomoConfig.TaskName
        if ($task.State -eq 'Running') {
            Stop-ScheduledTask -TaskName $script:MihomoConfig.TaskName
            $taskStopped = $true
            Write-MihomoStatus "✅ 已停止计划任务: $($script:MihomoConfig.TaskName)"
        }
    }
    catch {
        Write-MihomoStatus "⚠️ 无法停止计划任务，继续尝试结束进程: $($_.Exception.Message)" -Color Yellow
    }

    $processes = @(Get-Process -Name $script:MihomoConfig.ProcessName -ErrorAction SilentlyContinue)
    if ($processes.Count -gt 0) {
        $processes | Stop-Process -Force
        Write-MihomoStatus "✅ 已结束进程: $($script:MihomoConfig.ProcessName)"
    }
    elseif (-not $taskStopped) {
        Write-MihomoStatus 'ℹ️ mihomo 当前未运行' -Color Yellow
    }

    try {
        Clear-DnsClientCache
        Write-MihomoStatus '✅ DNS 缓存已清理'
    }
    catch {
        Write-MihomoStatus "⚠️ DNS 缓存清理失败: $($_.Exception.Message)" -Color Yellow
    }

    Show-MihomoNotification `
        -Title 'mihomo 已关闭' `
        -Message "系统代理已关闭`nmihomo 已停止`nDNS 缓存已处理" `
        -ShowNotification:$ShowNotification
}
