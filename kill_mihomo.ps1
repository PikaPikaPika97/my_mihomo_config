$process = "mihomo-windows-amd64"

Set-ItemProperty -Path 'Registry::HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Internet Settings' -Name ProxyEnable -Value 0
Write-Host "System proxy disabled."
Stop-Process -Name $process -Force > $null 2>&1
Write-Host "${process} stopped."
Clear-DnsClientCache
Start-Sleep -Seconds 1