$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

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
    MutexName         = 'Local\mihomo-proxy-control'
}

$script:LocalProxyServer = "127.0.0.1:$($script:MihomoConfig.ProxyPort)"
$script:ResolveProxyBypassScript = "$PSScriptRoot\scripts\resolve_proxy_bypass.py"
$script:ProxyOverride = $null

function Get-MihomoHeaders {
    $headers = @{}
    if ($script:MihomoConfig.ApiSecret) {
        $headers['Authorization'] = "Bearer $($script:MihomoConfig.ApiSecret)"
    }
    return $headers
}

function Invoke-MihomoControllerVersionRequest {
    return Invoke-RestMethod `
        -Uri "$($script:MihomoConfig.ControllerApi)/version" `
        -Headers (Get-MihomoHeaders) `
        -TimeoutSec $script:MihomoConfig.RequestTimeoutSec `
        -Method GET
}

function Invoke-MihomoControllerConfigRequest {
    return Invoke-RestMethod `
        -Uri "$($script:MihomoConfig.ControllerApi)/configs" `
        -Headers (Get-MihomoHeaders) `
        -TimeoutSec $script:MihomoConfig.RequestTimeoutSec `
        -Method GET
}

function Test-MihomoControllerAvailable {
    try {
        $null = Invoke-MihomoControllerVersionRequest
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
    while ((Get-Date) -lt $deadline) {
        if (Test-MihomoControllerAvailable) {
            return
        }
        Start-Sleep -Milliseconds $script:MihomoConfig.RetryIntervalMs
    }

    throw "mihomo 控制器未在 ${TimeoutSec} 秒内就绪: $($script:MihomoConfig.ControllerApi)"
}

function Get-MihomoScheduledTask {
    try {
        return Get-ScheduledTask -TaskName $script:MihomoConfig.TaskName -ErrorAction Stop
    }
    catch {
        if ($_.CategoryInfo.Category -eq [System.Management.Automation.ErrorCategory]::ObjectNotFound) {
            return $null
        }
        throw
    }
}

function Ensure-MihomoRunning {
    if (Test-MihomoControllerAvailable) {
        return
    }

    $task = Get-MihomoScheduledTask
    if ($null -eq $task) {
        throw "mihomo 控制器不可达，且找不到计划任务: $($script:MihomoConfig.TaskName)"
    }
    if ($task.State -ne 'Running') {
        Start-ScheduledTask -TaskName $script:MihomoConfig.TaskName
    }

    Wait-MihomoControllerReady
}

function Get-TunModeEnabled {
    $config = Invoke-MihomoControllerConfigRequest
    $tunProperty = $config.PSObject.Properties['tun']
    if ($null -eq $tunProperty -or $null -eq $config.tun) {
        throw 'mihomo 控制器返回中缺少 tun 配置。'
    }

    $enableProperty = $config.tun.PSObject.Properties['enable']
    if ($null -eq $enableProperty) {
        throw 'mihomo 控制器返回中缺少 tun.enable 配置。'
    }

    return [bool]$config.tun.enable
}

function Set-TunMode {
    param(
        [Parameter(Mandatory)]
        [bool]$Enable
    )

    $body = @{ tun = @{ enable = $Enable } } | ConvertTo-Json -Compress
    $uri = "$($script:MihomoConfig.ControllerApi)/configs"

    for ($attempt = 1; $attempt -le $script:MihomoConfig.RetryCount; $attempt++) {
        try {
            $null = Invoke-RestMethod `
                -Uri $uri `
                -Headers (Get-MihomoHeaders) `
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

function Refresh-WinInetProxy {
    rundll32.exe wininet.dll,InternetSetOptionA 0 39 0 0 | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw "WinINet 设置变更通知失败，退出码: $LASTEXITCODE"
    }

    rundll32.exe wininet.dll,InternetSetOptionA 0 37 0 0 | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw "WinINet 设置刷新失败，退出码: $LASTEXITCODE"
    }
}

function Get-SystemProxySettings {
    $properties = Get-ItemProperty -Path $script:MihomoConfig.RegistryPath
    $proxyEnableProperty = $properties.PSObject.Properties['ProxyEnable']
    if ($null -eq $proxyEnableProperty) {
        throw "注册表中缺少 ProxyEnable: $($script:MihomoConfig.RegistryPath)"
    }

    $proxyServerProperty = $properties.PSObject.Properties['ProxyServer']
    $proxyServer = if ($null -eq $proxyServerProperty) {
        ''
    }
    else {
        [string]$proxyServerProperty.Value
    }

    return [pscustomobject]@{
        Enabled = [bool]$proxyEnableProperty.Value
        Server  = $proxyServer
    }
}

function Set-SystemProxyDisabled {
    Set-ItemProperty -Path $script:MihomoConfig.RegistryPath -Name ProxyEnable -Value 0
    Set-ItemProperty -Path $script:MihomoConfig.RegistryPath -Name ProxyServer -Value ''
    Refresh-WinInetProxy
}

function Enable-SystemProxyServer {
    param(
        [Parameter(Mandatory)]
        [string]$Server,
        [Parameter(Mandatory)]
        [string]$ProxyOverride
    )

    Set-ItemProperty -Path $script:MihomoConfig.RegistryPath -Name ProxyServer -Value $Server
    Set-ItemProperty -Path $script:MihomoConfig.RegistryPath -Name ProxyOverride -Value $ProxyOverride
    Set-ItemProperty -Path $script:MihomoConfig.RegistryPath -Name ProxyEnable -Value 1
    Refresh-WinInetProxy
}

function Get-SystemProxyOverride {
    if ($null -eq $script:ProxyOverride) {
        try {
            $output = & uv run --script $script:ResolveProxyBypassScript --platform windows
            if ($LASTEXITCODE -ne 0) {
                throw "uv 退出码: $LASTEXITCODE"
            }
            $script:ProxyOverride = ($output -join [Environment]::NewLine).Trim()
        }
        catch {
            throw "无法解析代理 bypass 列表（请确认已安装 uv）: $($_.Exception.Message)"
        }
    }
    return $script:ProxyOverride
}

function ConvertFrom-ProxyEndpoint {
    param(
        [Parameter(Mandatory)]
        [string]$Server
    )

    $value = $Server.Trim()
    $separatorIndex = $value.LastIndexOf(':')
    if ($separatorIndex -lt 1) {
        throw "代理地址格式无效，应为 host:port 或 [IPv6]:port: $Server"
    }

    $serverHost = $value.Substring(0, $separatorIndex)
    if ($serverHost.StartsWith('[') -and $serverHost.EndsWith(']')) {
        $serverHost = $serverHost.Substring(1, $serverHost.Length - 2)
    }
    elseif ($serverHost.Contains(':')) {
        throw "IPv6 代理地址必须使用方括号: $Server"
    }

    if ([string]::IsNullOrWhiteSpace($serverHost)) {
        throw "代理主机不能为空: $Server"
    }

    $portText = $value.Substring($separatorIndex + 1)
    $port = 0
    if (-not [int]::TryParse($portText, [ref]$port) -or $port -lt 1 -or $port -gt 65535) {
        throw "代理端口无效: $Server"
    }

    return [pscustomobject]@{
        Host = $serverHost
        Port = $port
    }
}

function Test-TcpEndpoint {
    param(
        [Parameter(Mandatory)]
        [string]$Server,
        [int]$TimeoutMs = 1500
    )

    $endpoint = ConvertFrom-ProxyEndpoint -Server $Server
    $client = [System.Net.Sockets.TcpClient]::new()
    $asyncResult = $null

    try {
        $asyncResult = $client.BeginConnect($endpoint.Host, $endpoint.Port, $null, $null)
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
        if ($null -ne $asyncResult) {
            $asyncResult.AsyncWaitHandle.Close()
        }
        $client.Dispose()
    }
}

function Test-LocalMihomoRunning {
    if (Test-MihomoControllerAvailable) {
        return $true
    }

    $task = Get-MihomoScheduledTask
    if ($null -ne $task -and $task.State -eq 'Running') {
        return $true
    }

    $processes = @(Get-Process -Name $script:MihomoConfig.ProcessName -ErrorAction SilentlyContinue)
    return $processes.Count -gt 0
}

function Stop-LocalMihomoCore {
    $failures = [System.Collections.Generic.List[string]]::new()

    try {
        $task = Get-MihomoScheduledTask
        if ($null -ne $task -and $task.State -eq 'Running') {
            Stop-ScheduledTask -TaskName $script:MihomoConfig.TaskName
        }
    }
    catch {
        $failures.Add("停止计划任务失败: $($_.Exception.Message)")
    }

    try {
        $processes = @(Get-Process -Name $script:MihomoConfig.ProcessName -ErrorAction SilentlyContinue)
        if ($processes.Count -gt 0) {
            $processes | Stop-Process -Force -ErrorAction Stop
        }
    }
    catch {
        $failures.Add("结束残留进程失败: $($_.Exception.Message)")
    }

    try {
        $task = Get-MihomoScheduledTask
        if ($null -ne $task -and $task.State -eq 'Running') {
            $failures.Add("计划任务仍在运行: $($script:MihomoConfig.TaskName)")
        }
    }
    catch {
        $failures.Add("无法验证计划任务状态: $($_.Exception.Message)")
    }

    try {
        $processes = @(Get-Process -Name $script:MihomoConfig.ProcessName -ErrorAction SilentlyContinue)
        if ($processes.Count -gt 0) {
            $failures.Add("mihomo 进程仍然存在: $($script:MihomoConfig.ProcessName)")
        }
    }
    catch {
        $failures.Add("无法验证 mihomo 进程状态: $($_.Exception.Message)")
    }

    if ($failures.Count -gt 0) {
        throw ($failures -join '；')
    }
}

function Assert-LocalMihomoCoreStopped {
    $task = Get-MihomoScheduledTask
    if ($null -ne $task -and $task.State -eq 'Running') {
        throw "计划任务仍在运行: $($script:MihomoConfig.TaskName)"
    }

    $processes = @(Get-Process -Name $script:MihomoConfig.ProcessName -ErrorAction SilentlyContinue)
    if ($processes.Count -gt 0) {
        throw "mihomo 进程仍然存在: $($script:MihomoConfig.ProcessName)"
    }
}

function Assert-MihomoTargetState {
    param(
        [Parameter(Mandatory)]
        [ValidateSet('LocalSystemProxy', 'LocalTun', 'Direct', 'RemoteProxy', 'Stopped')]
        [string]$State,
        [string]$RemoteServer
    )

    $systemProxy = Get-SystemProxySettings

    switch ($State) {
        'LocalSystemProxy' {
            if (-not $systemProxy.Enabled -or $systemProxy.Server -ne $script:LocalProxyServer) {
                throw "Windows 系统代理未指向本机出口: $($systemProxy.Server)"
            }
            if (Get-TunModeEnabled) {
                throw 'mihomo TUN 仍处于开启状态。'
            }
        }
        'LocalTun' {
            if ($systemProxy.Enabled -or $systemProxy.Server) {
                throw 'Windows 系统代理未完全关闭。'
            }
            if (-not (Get-TunModeEnabled)) {
                throw 'mihomo TUN 未开启。'
            }
        }
        'Direct' {
            if ($systemProxy.Enabled -or $systemProxy.Server) {
                throw 'Windows 系统代理未完全关闭。'
            }
            if (Get-TunModeEnabled) {
                throw 'mihomo TUN 仍处于开启状态。'
            }
        }
        'RemoteProxy' {
            if (-not $systemProxy.Enabled -or $systemProxy.Server -ne $RemoteServer) {
                throw "Windows 系统代理未指向远端出口: $($systemProxy.Server)"
            }
            Assert-LocalMihomoCoreStopped
        }
        'Stopped' {
            if ($systemProxy.Enabled -or $systemProxy.Server) {
                throw 'Windows 系统代理未完全关闭。'
            }
            Assert-LocalMihomoCoreStopped
        }
    }
}

function Invoke-MihomoTransitionStep {
    param(
        [Parameter(Mandatory)]
        [string]$TargetState,
        [Parameter(Mandatory)]
        [string]$Step,
        [Parameter(Mandatory)]
        [string]$IntermediateState,
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [System.Collections.Generic.List[string]]$CompletedSteps,
        [Parameter(Mandatory)]
        [scriptblock]$Action
    )

    try {
        & $Action | Out-Null
        $CompletedSteps.Add($Step)
    }
    catch {
        $completedText = if ($CompletedSteps.Count -eq 0) {
            '无'
        }
        else {
            $CompletedSteps -join '、'
        }

        throw "切换到 $TargetState 失败。已完成步骤: $completedText。失败步骤: $Step。当前可能状态: $IntermediateState。请重新执行同一显式目标状态以继续收敛。原始错误: $($_.Exception.Message)"
    }
}

function Set-MihomoTargetStateCore {
    param(
        [Parameter(Mandatory)]
        [ValidateSet('LocalSystemProxy', 'LocalTun', 'Direct', 'RemoteProxy', 'Stopped')]
        [string]$State,
        [string]$RemoteServer,
        [Parameter(Mandatory)]
        [bool]$RemoteServerSpecified
    )

    if ($State -eq 'RemoteProxy') {
        if (-not $RemoteServerSpecified -or [string]::IsNullOrWhiteSpace($RemoteServer)) {
            throw 'RemoteProxy 必须显式提供 -RemoteServer，且不会修改当前状态。'
        }
        $RemoteServer = $RemoteServer.Trim()
        $null = ConvertFrom-ProxyEndpoint -Server $RemoteServer
    }
    elseif ($RemoteServerSpecified) {
        throw "只有 RemoteProxy 可以使用 -RemoteServer，且不会修改当前状态。"
    }

    $completedSteps = [System.Collections.Generic.List[string]]::new()

    switch ($State) {
        'LocalSystemProxy' {
            $proxyOverride = Get-SystemProxyOverride
            Invoke-MihomoTransitionStep -TargetState $State -Step '启动并确认本机控制器' -IntermediateState '本机内核可能已启动，原代理状态可能仍在' -CompletedSteps $completedSteps -Action {
                Ensure-MihomoRunning
            }
            Invoke-MihomoTransitionStep -TargetState $State -Step '关闭本机 TUN' -IntermediateState '本机内核运行，原系统代理状态可能仍在' -CompletedSteps $completedSteps -Action {
                Set-TunMode -Enable $false
            }
            Invoke-MihomoTransitionStep -TargetState $State -Step '启用本机系统代理' -IntermediateState 'TUN 已关闭，Windows 代理可能处于部分写入或直连状态' -CompletedSteps $completedSteps -Action {
                Enable-SystemProxyServer -Server $script:LocalProxyServer -ProxyOverride $proxyOverride
            }
        }
        'LocalTun' {
            Invoke-MihomoTransitionStep -TargetState $State -Step '启动并确认本机控制器' -IntermediateState '本机内核可能已启动，原代理状态可能仍在' -CompletedSteps $completedSteps -Action {
                Ensure-MihomoRunning
            }
            Invoke-MihomoTransitionStep -TargetState $State -Step '关闭 Windows 系统代理' -IntermediateState 'Windows 代理可能处于部分关闭状态' -CompletedSteps $completedSteps -Action {
                Set-SystemProxyDisabled
            }
            Invoke-MihomoTransitionStep -TargetState $State -Step '开启本机 TUN' -IntermediateState '接近直连状态，本机内核运行但 TUN 可能仍关闭' -CompletedSteps $completedSteps -Action {
                Set-TunMode -Enable $true
            }
        }
        'Direct' {
            Invoke-MihomoTransitionStep -TargetState $State -Step '关闭 Windows 系统代理' -IntermediateState 'Windows 代理可能处于部分关闭状态' -CompletedSteps $completedSteps -Action {
                Set-SystemProxyDisabled
            }
            Invoke-MihomoTransitionStep -TargetState $State -Step '启动并确认本机控制器' -IntermediateState 'Windows 代理已关闭，本机内核可能尚未就绪' -CompletedSteps $completedSteps -Action {
                Ensure-MihomoRunning
            }
            Invoke-MihomoTransitionStep -TargetState $State -Step '关闭本机 TUN' -IntermediateState 'Windows 代理已关闭，本机 TUN 可能仍开启' -CompletedSteps $completedSteps -Action {
                Set-TunMode -Enable $false
            }
        }
        'RemoteProxy' {
            if (-not (Test-TcpEndpoint -Server $RemoteServer)) {
                throw "远端代理不可达: $RemoteServer。未修改当前状态。"
            }
            $proxyOverride = Get-SystemProxyOverride
            $controllerAvailable = Test-MihomoControllerAvailable
            $localCoreRunning = if ($controllerAvailable) {
                $true
            }
            else {
                Test-LocalMihomoRunning
            }

            if ($localCoreRunning -and -not $controllerAvailable) {
                throw '本机 mihomo 似乎正在运行，但控制器不可达，无法确认 TUN 已关闭。未修改当前状态。'
            }

            if ($controllerAvailable) {
                Invoke-MihomoTransitionStep -TargetState $State -Step '关闭本机 TUN' -IntermediateState '远端代理尚未启用，本机 TUN 可能仍开启' -CompletedSteps $completedSteps -Action {
                    Set-TunMode -Enable $false
                }
            }
            Invoke-MihomoTransitionStep -TargetState $State -Step '启用远端系统代理' -IntermediateState '本机 TUN 已关闭，Windows 代理可能处于部分写入状态' -CompletedSteps $completedSteps -Action {
                Enable-SystemProxyServer -Server $RemoteServer -ProxyOverride $proxyOverride
            }
            Invoke-MihomoTransitionStep -TargetState $State -Step '停止本机 mihomo 内核' -IntermediateState '远端系统代理已启用，但本机内核可能仍在运行' -CompletedSteps $completedSteps -Action {
                Stop-LocalMihomoCore
            }
        }
        'Stopped' {
            Invoke-MihomoTransitionStep -TargetState $State -Step '关闭 Windows 系统代理' -IntermediateState 'Windows 代理可能处于部分关闭状态；本机内核仍在运行' -CompletedSteps $completedSteps -Action {
                Set-SystemProxyDisabled
            }
            Invoke-MihomoTransitionStep -TargetState $State -Step '停止本机 mihomo 内核' -IntermediateState 'Windows 代理已关闭，但任务或进程可能仍在运行' -CompletedSteps $completedSteps -Action {
                Stop-LocalMihomoCore
            }
        }
    }

    Invoke-MihomoTransitionStep -TargetState $State -Step '验证目标代理状态' -IntermediateState '写入步骤已完成，但最终不变量未满足' -CompletedSteps $completedSteps -Action {
        Assert-MihomoTargetState -State $State -RemoteServer $RemoteServer
    }

    if ($State -eq 'Stopped') {
        try {
            Clear-DnsClientCache
        }
        catch {
            Write-Warning "停止状态已达到，但 DNS 缓存清理失败: $($_.Exception.Message)"
        }
    }

    return $State
}

function Invoke-WithMihomoControlLock {
    param(
        [Parameter(Mandatory)]
        [scriptblock]$Action
    )

    $mutex = [System.Threading.Mutex]::new($false, $script:MihomoConfig.MutexName)
    $acquired = $false

    try {
        try {
            $acquired = $mutex.WaitOne(0)
        }
        catch [System.Threading.AbandonedMutexException] {
            $acquired = $true
            Write-Warning '上一次代理状态切换异常退出；将从当前状态继续收敛。'
        }

        if (-not $acquired) {
            throw '另一个 mihomo 代理状态切换正在执行，请等待其完成后重试。'
        }

        return & $Action
    }
    finally {
        if ($acquired) {
            $mutex.ReleaseMutex()
        }
        $mutex.Dispose()
    }
}

function Set-MihomoTargetState {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('LocalSystemProxy', 'LocalTun', 'Direct', 'RemoteProxy', 'Stopped')]
        [string]$State,
        [string]$RemoteServer
    )

    $remoteServerSpecified = $PSBoundParameters.ContainsKey('RemoteServer')
    return Invoke-WithMihomoControlLock -Action {
        Set-MihomoTargetStateCore `
            -State $State `
            -RemoteServer $RemoteServer `
            -RemoteServerSpecified $remoteServerSpecified
    }
}

function Switch-MihomoLocalMode {
    [CmdletBinding()]
    param()

    return Invoke-WithMihomoControlLock -Action {
        $systemProxy = Get-SystemProxySettings
        if (-not (Test-MihomoControllerAvailable)) {
            throw '当前不是可切换的本机系统代理状态或本机 TUN 状态：mihomo 控制器不可达。请显式指定 -State。'
        }

        $tunEnabled = Get-TunModeEnabled
        $targetState = if (
            $systemProxy.Enabled -and
            $systemProxy.Server -eq $script:LocalProxyServer -and
            -not $tunEnabled
        ) {
            'LocalTun'
        }
        elseif (
            -not $systemProxy.Enabled -and
            [string]::IsNullOrEmpty($systemProxy.Server) -and
            $tunEnabled
        ) {
            'LocalSystemProxy'
        }
        else {
            throw '当前不是完整的本机系统代理状态或本机 TUN 状态。ToggleLocal 不会猜测目标，请显式指定 -State。'
        }

        Set-MihomoTargetStateCore -State $targetState -RemoteServerSpecified $false
    }
}

Export-ModuleMember -Function Set-MihomoTargetState, Switch-MihomoLocalMode
