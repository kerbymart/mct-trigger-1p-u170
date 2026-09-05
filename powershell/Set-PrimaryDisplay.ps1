[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$DeviceName
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'MctDisplayTools.psm1') -Force

if (-not $DeviceName) {
    $DeviceName = (Select-MctDisplayDevice).DeviceName
}

$result = Set-MctPrimaryDisplay -DeviceName $DeviceName -WhatIf:$WhatIfPreference
$result | Format-List DeviceName, Description, Primary, X, Y, Width, Height, FrequencyHz
