# Starts the windowless bridge at logon (per-user, no admin) and launches it now.
$ErrorActionPreference = 'Stop'
$exe = Join-Path $PSScriptRoot 'bin\EdgeHubBridgeHidden.exe'
if (-not (Test-Path $exe)) {
    & $env:ComSpec /c "`"$(Join-Path $PSScriptRoot 'build.cmd')`""
    if ($LASTEXITCODE -ne 0) { throw 'Build failed.' }
}
$logDir = Join-Path $env:LOCALAPPDATA 'EdgeHubBridge'
New-Item -ItemType Directory -Force $logDir | Out-Null
$command = "`"$exe`" --log `"$(Join-Path $logDir 'bridge.log')`""
Set-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run' -Name 'EdgeHubBridge' -Value $command
Start-Process -FilePath $exe -ArgumentList @('--log', (Join-Path $logDir 'bridge.log'))
Write-Host "Installed. Bridge is running and will start at logon."
Write-Host "Restart HWiNFO once so it discovers the 'Lian Li Edge Hub' custom sensor."
