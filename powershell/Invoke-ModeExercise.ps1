[CmdletBinding()]
param(
    [string]$DeviceName,
    [ValidateSet('Representative','Refresh')]
    [string]$Kind = 'Representative',
    [int]$StepSeconds = 5,
    [int]$BaselineSeconds = 3,
    [int]$MaximumModes = 5,
    [string]$TestId,
    [string]$LogPath
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'MctDisplayTools.psm1') -Force

if (-not $DeviceName) { $DeviceName = (Select-MctDisplayDevice).DeviceName }
if (-not $TestId) { $TestId = "MODE_$($Kind.ToUpperInvariant())" }

$current = Resolve-MctDisplayDevice -DeviceName $DeviceName
$allModes = @(Get-MctSupportedDisplayModes -DeviceName $DeviceName)
if ($allModes.Count -eq 0) { throw "No supported modes were enumerated for $DeviceName." }

function Select-ClosestFrequencyMode($modes, [int]$frequency) {
    return $modes | Sort-Object @{Expression={ [Math]::Abs([int]$_.FrequencyHz - $frequency) }} | Select-Object -First 1
}

$selectedModes = @()
if ($Kind -eq 'Refresh') {
    $selectedModes = @($allModes |
        Where-Object { $_.Width -eq $current.Width -and $_.Height -eq $current.Height -and $_.FrequencyHz -gt 0 } |
        Sort-Object FrequencyHz -Unique |
        Select-Object -First $MaximumModes)
} else {
    $standard = @(
        @{W=800;H=600}, @{W=1024;H=768}, @{W=1280;H=720}, @{W=1280;H=1024},
        @{W=1366;H=768}, @{W=1600;H=900}, @{W=1680;H=1050}, @{W=1920;H=1080}
    )
    foreach ($wanted in $standard) {
        $matches = @($allModes | Where-Object { $_.Width -eq $wanted.W -and $_.Height -eq $wanted.H })
        if ($matches.Count -gt 0) {
            $selectedModes += Select-ClosestFrequencyMode $matches $current.FrequencyHz
        }
    }

    if ($selectedModes.Count -lt 3) {
        $uniqueResolutions = @($allModes |
            Group-Object Width,Height |
            ForEach-Object { Select-ClosestFrequencyMode $_.Group $current.FrequencyHz } |
            Sort-Object @{Expression={ $_.Width * $_.Height }})
        if ($uniqueResolutions.Count -gt 0) {
            $indices = @(0, [int](($uniqueResolutions.Count-1)/2), ($uniqueResolutions.Count-1)) | Select-Object -Unique
            foreach ($index in $indices) { $selectedModes += $uniqueResolutions[$index] }
        }
    }

    $selectedModes = @($selectedModes |
        Sort-Object Width,Height,FrequencyHz -Unique |
        Select-Object -First $MaximumModes)
}

if ($selectedModes.Count -eq 0) {
    Write-Warning "No alternate modes were found for exercise kind '$Kind'."
    return
}

if ($LogPath) {
    Write-MctEvent -LogPath $LogPath -TestId $TestId -Event 'mode_exercise_start' -Data @{
        deviceName=$DeviceName; kind=$Kind; originalWidth=$current.Width; originalHeight=$current.Height;
        originalFrequencyHz=$current.FrequencyHz; selectedModeCount=$selectedModes.Count
    }
}

Wait-MctInterval -Seconds $BaselineSeconds -Message "[$TestId] Baseline mode"

$step = 0
try {
    foreach ($mode in $selectedModes) {
        $stepId = "${TestId}_$('{0:D2}' -f $step)"
        if ($LogPath) {
            Write-MctEvent -LogPath $LogPath -TestId $stepId -Event 'mode_change_request' -Data @{
                width=$mode.Width;height=$mode.Height;frequencyHz=$mode.FrequencyHz;bitsPerPixel=$mode.BitsPerPixel
            }
        }
        try {
            Set-MctDisplayMode -DeviceName $DeviceName -Width $mode.Width -Height $mode.Height -FrequencyHz $mode.FrequencyHz -BitsPerPixel $mode.BitsPerPixel | Out-Null
            if ($LogPath) { Write-MctEvent -LogPath $LogPath -TestId $stepId -Event 'mode_change_applied' }
            Write-Host "[$stepId] $($mode.Width)x$($mode.Height)@$($mode.FrequencyHz)Hz" -ForegroundColor Cyan
            Wait-MctInterval -Seconds $StepSeconds -Message "[$stepId] Holding display mode"
        } catch {
            Write-Warning "[$stepId] $($_.Exception.Message)"
            if ($LogPath) { Write-MctEvent -LogPath $LogPath -TestId $stepId -Event 'mode_change_failed' -Data @{message=$_.Exception.Message} }
        }
        $step++
    }
} finally {
    Write-Host "Restoring original mode $($current.Width)x$($current.Height)@$($current.FrequencyHz)Hz" -ForegroundColor Green
    try {
        Set-MctDisplayMode -DeviceName $DeviceName -Width $current.Width -Height $current.Height -FrequencyHz $current.FrequencyHz -BitsPerPixel $current.BitsPerPixel | Out-Null
        if ($LogPath) { Write-MctEvent -LogPath $LogPath -TestId $TestId -Event 'original_mode_restored' }
    } catch {
        Write-Warning "Could not automatically restore the original mode: $($_.Exception.Message)"
        if ($LogPath) { Write-MctEvent -LogPath $LogPath -TestId $TestId -Event 'original_mode_restore_failed' -Data @{message=$_.Exception.Message} }
    }
}

if ($LogPath) { Write-MctEvent -LogPath $LogPath -TestId $TestId -Event 'mode_exercise_end' }
