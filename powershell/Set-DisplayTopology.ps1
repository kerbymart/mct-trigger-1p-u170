[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)]
    [ValidateSet('Extend','Duplicate','InternalOnly','ExternalOnly')]
    [string]$Mode,

    [int]$SettleSeconds = 3
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'MctDisplayTools.psm1') -Force

Set-MctDisplayTopology -Mode $Mode -SettleSeconds $SettleSeconds -WhatIf:$WhatIfPreference
Get-MctDisplayDevices | Format-Table DeviceName, Description, Primary, X, Y, Width, Height, FrequencyHz -AutoSize
