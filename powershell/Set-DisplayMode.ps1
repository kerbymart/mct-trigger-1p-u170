[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$DeviceName,
    [Parameter(Mandatory)][int]$Width,
    [Parameter(Mandatory)][int]$Height,
    [int]$FrequencyHz,
    [int]$BitsPerPixel
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'MctDisplayTools.psm1') -Force

if (-not $DeviceName) {
    $DeviceName = (Select-MctDisplayDevice).DeviceName
}

$result = Set-MctDisplayMode -DeviceName $DeviceName -Width $Width -Height $Height -FrequencyHz $FrequencyHz -BitsPerPixel $BitsPerPixel -WhatIf:$WhatIfPreference
$result | Format-List
