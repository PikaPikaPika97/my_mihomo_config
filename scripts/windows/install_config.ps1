#Requires -Version 7.0
#Requires -RunAsAdministrator
[CmdletBinding()]
param(
    [string]$MihomoExecutable = "$PSScriptRoot\..\..\mihomo-windows-amd64.exe"
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$repoRoot = (Resolve-Path "$PSScriptRoot\..\..").Path
$sourceExecutable = (Resolve-Path -LiteralPath $MihomoExecutable).Path
$installDirectory = Join-Path $env:ProgramFiles 'mihomo'
$dataDirectory = Join-Path $env:ProgramData 'mihomo'
$installedExecutable = Join-Path $installDirectory 'mihomo-windows-amd64.exe'
$installedConfig = Join-Path $dataDirectory 'config.yaml'
$bypassFile = Join-Path $dataDirectory 'proxy_bypass.txt'
$pwsh = Join-Path $PSHOME 'pwsh.exe'
$uv = (Get-Command uv -CommandType Application).Source

Write-Host '生成并校验配置'
& $uv run --script "$repoRoot\scripts\generate_config.py"
if ($LASTEXITCODE -ne 0) { throw "生成配置失败，退出码: $LASTEXITCODE" }
& $sourceExecutable -t -d $repoRoot -f "$repoRoot\official_config.yaml"
if ($LASTEXITCODE -ne 0) { throw "校验配置失败，退出码: $LASTEXITCODE" }
$bypass = & $uv run --script "$repoRoot\scripts\resolve_proxy_bypass.py" --platform windows
if ($LASTEXITCODE -ne 0) { throw "解析 bypass 失败，退出码: $LASTEXITCODE" }

# 先完成生成和校验，再停止已有内核。内核更新时也使用同一个安装入口。
$existingTask = Get-ScheduledTask -TaskName mihomo -ErrorAction SilentlyContinue
if ($null -ne $existingTask) {
    Stop-ScheduledTask -TaskName mihomo
}
Get-Process -Name mihomo-windows-amd64 -ErrorAction SilentlyContinue |
    Stop-Process -Force -PassThru | Wait-Process -Timeout 15

Write-Host "部署程序到 $installDirectory，配置到 $dataDirectory"
$null = New-Item -ItemType Directory -Path "$installDirectory\scripts\windows", $dataDirectory -Force
# 写入内容而非复制工作区 ACL，避免继承源文件的 Low/Medium 完整性标签。
$executableBytes = [System.IO.File]::ReadAllBytes($sourceExecutable)
[System.IO.File]::WriteAllBytes($installedExecutable, $executableBytes)
& icacls $installedExecutable /setintegritylevel High /Q
if ($LASTEXITCODE -ne 0) { throw "设置内核完整性标签失败，退出码: $LASTEXITCODE" }
foreach ($relativePath in @('mihomo.ps1', 'scripts\windows\MihomoControl.psm1')) {
    $content = Get-Content -LiteralPath (Join-Path $repoRoot $relativePath) -Raw
    Set-Content -LiteralPath (Join-Path $installDirectory $relativePath) -Value $content -Encoding utf8
}
Get-Content -LiteralPath "$repoRoot\official_config.yaml" -Raw |
    Set-Content -LiteralPath $installedConfig -Encoding utf8
Set-Content -LiteralPath $bypassFile -Value ($bypass -join [Environment]::NewLine) -Encoding utf8

Write-Host '注册 SYSTEM 开机任务'
$action = New-ScheduledTaskAction -Execute $installedExecutable `
    -Argument "-d `"$dataDirectory`" -f `"$installedConfig`"" -WorkingDirectory $dataDirectory
$principal = New-ScheduledTaskPrincipal -UserId 'S-1-5-18' -LogonType ServiceAccount -RunLevel Highest
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
    -ExecutionTimeLimit ([TimeSpan]::Zero) -MultipleInstances IgnoreNew
$task = New-ScheduledTask -Action $action -Principal $principal -Settings $settings `
    -Trigger (New-ScheduledTaskTrigger -AtStartup)
$null = Register-ScheduledTask -TaskName mihomo -InputObject $task -Force
# XML 是本机安装产物，不包含仓库路径。
Export-ScheduledTask -TaskName mihomo | Set-Content "$dataDirectory\mihomo.xml" -Encoding unicode

Write-Host '生成当前用户的开始菜单快捷方式'
$shortcutDirectory = Join-Path ([Environment]::GetFolderPath('Programs')) 'mihomo'
$null = New-Item -ItemType Directory -Path $shortcutDirectory -Force
$shell = New-Object -ComObject WScript.Shell
$commands = [ordered]@{
    '本机系统代理' = '-State LocalSystemProxy'
    '本机 TUN' = '-State LocalTun'
    '切换本机代理模式' = '-ToggleLocal'
    '直连' = '-State Direct'
    '停止 mihomo' = '-State Stopped'
}
foreach ($entry in $commands.GetEnumerator()) {
    $shortcutPath = Join-Path $shortcutDirectory "$($entry.Key).lnk"
    $shortcut = $shell.CreateShortcut($shortcutPath)
    $shortcut.TargetPath = $pwsh
    $shortcut.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$installDirectory\mihomo.ps1`" -ProxyBypassFile `"$bypassFile`" $($entry.Value) -ShowNotification"
    $shortcut.WorkingDirectory = $installDirectory
    $shortcut.Save()
    # SLDF_RUNAS_USER：提升当前用户，HKCU 系统代理仍属于该用户。
    $shortcutBytes = [System.IO.File]::ReadAllBytes($shortcutPath)
    $shortcutBytes[0x15] = $shortcutBytes[0x15] -bor 0x20
    [System.IO.File]::WriteAllBytes($shortcutPath, $shortcutBytes)
}

Start-ScheduledTask -TaskName mihomo
$controlModule = Import-Module "$installDirectory\scripts\windows\MihomoControl.psm1" `
    -ArgumentList $bypassFile -Force -PassThru
$deadline = (Get-Date).AddSeconds(15)
do {
    $taskState = (Get-ScheduledTask -TaskName mihomo).State
    if ($taskState -eq 'Running') {
        $process = Get-Process -Name mihomo-windows-amd64 -ErrorAction SilentlyContinue |
            Where-Object Path -EQ $installedExecutable
        if ($null -ne $process -and (& $controlModule { Test-MihomoControllerAvailable })) {
            Write-Host "安装完成。配置: $installedConfig；快捷方式: $shortcutDirectory"
            return
        }
    }
    Start-Sleep -Milliseconds 400
} while ((Get-Date) -lt $deadline)
throw '安装后的 mihomo 控制器未在 15 秒内就绪，请检查计划任务 mihomo 和控制模块中的控制器设置。'
