[CmdletBinding()]
param(
    [string]$DeviceName,
    [string]$ConfigPath = (Join-Path (Split-Path $PSScriptRoot -Parent) 'config\test-cases.json')
)

$ErrorActionPreference = 'Stop'

if ($env:OS -ne 'Windows_NT') {
    throw 'This test harness requires an interactive Windows desktop session.'
}

Import-Module (Join-Path $PSScriptRoot 'MctDisplayTools.psm1') -Force

$warnings = New-Object System.Collections.Generic.List[string]
$failures = New-Object System.Collections.Generic.List[string]

if (-not [Environment]::UserInteractive) {
    $failures.Add('PowerShell is not running in an interactive user session.')
}

if ($PSVersionTable.PSVersion.Major -lt 5) {
    $failures.Add("PowerShell $($PSVersionTable.PSVersion) is too old. Windows PowerShell 5.1 or newer is recommended.")
}

if ($env:SESSIONNAME -like 'RDP*') {
    $warnings.Add("Current session is '$env:SESSIONNAME'. RDP can replace or virtualize the physical display topology; run locally when possible.")
}

if (-not (Test-Path $ConfigPath)) {
    $failures.Add("Test configuration not found: $ConfigPath")
} else {
    try { Get-Content $ConfigPath -Raw | ConvertFrom-Json | Out-Null }
    catch { $failures.Add("Test configuration is not valid JSON: $($_.Exception.Message)") }
}

$displays = @(Get-MctDisplayDevices)
if ($displays.Count -eq 0) {
    $failures.Add('Windows reports no attached desktop display devices.')
}
if ($displays.Count -lt 2) {
    $warnings.Add('Only one attached display is visible. The MCT-secondary role requires at least two displays in Extend mode.')
}

$target = $null
if ($DeviceName) {
    $target = $displays | Where-Object { $_.DeviceName -ieq $DeviceName } | Select-Object -First 1
    if (-not $target) { $failures.Add("Requested target '$DeviceName' is not currently attached.") }
}

Write-Host ''
Write-Host 'Display inventory' -ForegroundColor Cyan
$displays | Format-Table DeviceName, Description, Primary, X, Y, Width, Height, FrequencyHz -AutoSize

Write-Host ''
Write-Host 'Environment' -ForegroundColor Cyan
Write-Host "Windows: $([Environment]::OSVersion.VersionString)"
Write-Host "PowerShell: $($PSVersionTable.PSVersion)"
Write-Host "Interactive: $([Environment]::UserInteractive)"
Write-Host "Session: $env:SESSIONNAME"
Write-Host "Config: $ConfigPath"

foreach ($warning in $warnings) { Write-Warning $warning }
foreach ($failure in $failures) { Write-Host "FAIL: $failure" -ForegroundColor Red }

$result = [pscustomobject]@{
    Passed = ($failures.Count -eq 0)
    WarningCount = $warnings.Count
    FailureCount = $failures.Count
    Warnings = @($warnings)
    Failures = @($failures)
    DisplayCount = $displays.Count
    Displays = $displays
}

if (-not $result.Passed) {
    throw "Lab preflight failed with $($failures.Count) error(s)."
}

Write-Host ''
Write-Host 'Preflight passed.' -ForegroundColor Green
return $result
