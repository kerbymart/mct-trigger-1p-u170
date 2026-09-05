[CmdletBinding()]
param(
    [string]$OutputPath,
    [switch]$IncludeModes,
    [string]$DeviceName
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'MctDisplayTools.psm1') -Force

$snapshot = Get-MctDisplaySnapshot

Write-Host ''
Write-Host 'Attached displays' -ForegroundColor Cyan
$snapshot.Displays | Format-Table DeviceName, Description, Primary, X, Y, Width, Height, FrequencyHz, BitsPerPixel -AutoSize

Write-Host ''
Write-Host 'Monitor IDs' -ForegroundColor Cyan
$snapshot.MonitorIds | Format-Table -AutoSize

if ($IncludeModes) {
    if (-not $DeviceName) {
        $selected = Select-MctDisplayDevice
        $DeviceName = $selected.DeviceName
    }
    Write-Host ''
    Write-Host "Supported modes for $DeviceName" -ForegroundColor Cyan
    Get-MctSupportedDisplayModes -DeviceName $DeviceName | Format-Table Width, Height, FrequencyHz, BitsPerPixel -AutoSize
}

if ($OutputPath) {
    $directory = Split-Path -Parent $OutputPath
    if ($directory -and -not (Test-Path $directory)) { New-Item -ItemType Directory -Path $directory -Force | Out-Null }
    $snapshot | ConvertTo-Json -Depth 8 | Set-Content -Path $OutputPath -Encoding UTF8
    Write-Host "Snapshot saved to: $OutputPath" -ForegroundColor Green
}
