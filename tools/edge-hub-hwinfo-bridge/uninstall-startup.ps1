# Removes the logon entry, stops the bridge and deletes its HWiNFO custom sensor.
$ErrorActionPreference = 'Stop'
Remove-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run' -Name 'EdgeHubBridge' -ErrorAction SilentlyContinue
$binDir = (Resolve-Path (Join-Path $PSScriptRoot 'bin')).Path
Get-Process -Name 'EdgeHubBridge', 'EdgeHubBridgeHidden' -ErrorAction SilentlyContinue |
    Where-Object { $_.Path -and $_.Path.StartsWith($binDir, [StringComparison]::OrdinalIgnoreCase) } |
    ForEach-Object { Stop-Process -Id $_.Id }
& (Join-Path $binDir 'EdgeHubBridge.exe') --remove | Out-Null
Write-Host "Uninstalled. Restart HWiNFO to drop the custom sensor from its list."
