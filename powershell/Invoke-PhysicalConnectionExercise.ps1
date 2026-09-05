[CmdletBinding()]
param(
    [ValidateSet('Full','VgaCycle','UsbCycle','VgaDisconnect','VgaConnect','UsbDisconnect','UsbConnect')]
    [string]$Sequence = 'Full',
    [string]$OutputDirectory = (Join-Path (Get-Location) ("artifacts\physical-{0}" -f (Get-Date -Format 'yyyyMMdd-HHmmss'))),
    [int]$PostActionSeconds = 5,
    [switch]$ExternalCapturePrompts
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'MctDisplayTools.psm1') -Force

New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
$logPath = Join-Path $OutputDirectory 'events.jsonl'

function Invoke-CaptureBoundaryPrompt([string]$TestId, [string]$Phase) {
    if (-not $ExternalCapturePrompts) { return }
    if ($Phase -eq 'Start') {
        Read-Host "[$TestId] Start the independent USBPcap/Wireshark capture now, then press ENTER"
    } else {
        Read-Host "[$TestId] Stop/save the independent USB capture now, then press ENTER"
    }
}

function Save-Snapshot([string]$TestId, [string]$Phase) {
    $safePhase = $Phase.ToLowerInvariant()
    $path = Join-Path $OutputDirectory ("{0}-{1}.json" -f $TestId.ToLowerInvariant(), $safePhase)
    Save-MctDisplaySnapshot -Path $path | Out-Null
}

function Run-HumanAction([string]$TestId, [string]$Instruction, [switch]$AskVisualResult) {
    Write-MctEvent -LogPath $logPath -TestId $TestId -Event 'test_start'
    Save-Snapshot $TestId 'before'
    Invoke-CaptureBoundaryPrompt $TestId 'Start'
    Start-Sleep -Seconds 3

    Invoke-MctOperatorPrompt -Message $Instruction -LogPath $logPath -TestId $TestId | Out-Null
    Write-MctEvent -LogPath $logPath -TestId $TestId -Event 'physical_action_confirmed'
    Wait-MctInterval -Seconds $PostActionSeconds -Message "[$TestId] Observing post-action state"

    if ($AskVisualResult) {
        Write-Host ''
        Write-Host 'Visual confirmation:' -ForegroundColor Yellow
        Write-Host '  PASS      = image visible and stable'
        Write-Host '  ARTIFACT  = image visible but incorrect/artifacts'
        Write-Host '  NO_IMAGE  = monitor detected but no usable image'
        Write-Host '  NO_SYNC   = monitor reports no signal/cannot synchronize'
        Write-Host '  UNSURE    = cannot confidently determine'
        $result = Read-Host 'Enter result'
        Write-MctEvent -LogPath $logPath -TestId $TestId -Event 'visual_confirmation' -Data @{result=$result}
    }

    Save-Snapshot $TestId 'after'
    Invoke-CaptureBoundaryPrompt $TestId 'Stop'
    Write-MctEvent -LogPath $logPath -TestId $TestId -Event 'test_end'
}

$steps = switch ($Sequence) {
    'Full'          { @('VgaDisconnect','VgaConnect','UsbDisconnect','UsbConnect') }
    'VgaCycle'      { @('VgaDisconnect','VgaConnect') }
    'UsbCycle'      { @('UsbDisconnect','UsbConnect') }
    default         { @($Sequence) }
}

Write-Host "Artifacts: $OutputDirectory" -ForegroundColor Green
Write-Host 'This script does not start or stop USBPcap. It only supplies synchronized human actions and display snapshots.' -ForegroundColor Cyan

foreach ($step in $steps) {
    switch ($step) {
        'VgaDisconnect' {
            Run-HumanAction -TestId 'VGA_DISCONNECT' -Instruction @'
Disconnect ONLY the VGA cable from the NComputing U170/display path.
Leave the U170 USB connection in place. Do not change resolution or move other cables.
'@
        }
        'VgaConnect' {
            Run-HumanAction -TestId 'VGA_CONNECT' -Instruction @'
Connect the VGA cable to the same monitor and the NComputing U170.
Wait until the monitor attempts to synchronize, then confirm the action.
'@ -AskVisualResult
        }
        'UsbDisconnect' {
            Run-HumanAction -TestId 'USB_DISCONNECT' -Instruction @'
Unplug ONLY the U170 USB connection from the host computer.
Leave the VGA cable and monitor power unchanged.
'@
        }
        'UsbConnect' {
            Run-HumanAction -TestId 'USB_CONNECT' -Instruction @'
Reconnect the U170 to the SAME host USB port used before.
Wait for Windows device enumeration and the display driver to settle before confirming.
'@ -AskVisualResult
        }
    }
}

Write-Host ''
Write-Host "Physical connection exercise complete. Event log: $logPath" -ForegroundColor Green
