[CmdletBinding()]
param(
    [string]$DeviceName,
    [string]$ReferencePrimaryDeviceName,

    [ValidateSet('Both','Primary','Secondary')]
    [string]$Role = 'Both',

    [string]$ConfigPath = (Join-Path (Split-Path $PSScriptRoot -Parent) 'config\test-cases.json'),
    [string]$OutputDirectory = (Join-Path (Get-Location) ("artifacts\display-{0}" -f (Get-Date -Format 'yyyyMMdd-HHmmss'))),

    [int]$PreActionSeconds = 3,
    [int]$PostActionSeconds = 2,
    [int]$RegionStepSeconds = 3,
    [int]$CursorStepSeconds = 2,
    [int]$ModeStepSeconds = 5,

    [switch]$IncludePhysical,
    [switch]$IncludeRefreshModes,
    [switch]$SkipModes,
    [switch]$SkipPatterns,
    [switch]$SkipRegions,
    [switch]$SkipCursor,
    [switch]$SkipIdle,
    [switch]$SkipMotion,
    [switch]$ExternalCapturePrompts,
    [switch]$StopOnError
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'MctDisplayTools.psm1') -Force

if (-not (Test-Path $ConfigPath)) { throw "Test configuration was not found: $ConfigPath" }
$config = Get-Content -Path $ConfigPath -Raw | ConvertFrom-Json

New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
$logPath = Join-Path $OutputDirectory 'events.jsonl'
$initialSnapshotPath = Join-Path $OutputDirectory 'snapshot-initial.json'
$finalSnapshotPath = Join-Path $OutputDirectory 'snapshot-final.json'
Save-MctDisplaySnapshot -Path $initialSnapshotPath | Out-Null

function Capture-Gate([string]$TestId, [string]$Phase) {
    if (-not $ExternalCapturePrompts) { return }
    if ($Phase -eq 'Start') {
        Write-Host ''
        Write-Host "[$TestId] External capture boundary" -ForegroundColor Yellow
        Read-Host 'Start USBPcap/Wireshark independently, then press ENTER'
    } else {
        Read-Host 'Stop/save the independent USB capture, then press ENTER'
    }
}

function Invoke-TestCase([string]$TestId, [scriptblock]$Action) {
    Capture-Gate $TestId 'Start'
    Write-MctEvent -LogPath $logPath -TestId $TestId -Event 'test_start'
    if ($PreActionSeconds -gt 0) {
        Wait-MctInterval -Seconds $PreActionSeconds -Message "[$TestId] Pre-action baseline"
    }

    $failed = $false
    try {
        & $Action
        Write-MctEvent -LogPath $logPath -TestId $TestId -Event 'test_action_complete'
    } catch {
        $failed = $true
        Write-MctEvent -LogPath $logPath -TestId $TestId -Event 'test_failed' -Data @{message=$_.Exception.Message;type=$_.Exception.GetType().FullName}
        Write-Warning "[$TestId] $($_.Exception.Message)"
        if ($StopOnError) { throw }
    } finally {
        if ($PostActionSeconds -gt 0) {
            Wait-MctInterval -Seconds $PostActionSeconds -Message "[$TestId] Post-action observation"
        }
        Write-MctEvent -LogPath $logPath -TestId $TestId -Event 'test_end' -Data @{failed=$failed}
        Capture-Gate $TestId 'Stop'
    }
}

function Get-TargetDisplay([string]$Preferred) {
    return Select-MctDisplayDevice -PreferredDeviceName $Preferred
}

Write-Host ''
Write-Host 'MCT Trigger 1+ / NComputing U170 display exercise' -ForegroundColor Green
Write-Host 'This harness DOES NOT start USBPcap or Wireshark.' -ForegroundColor Cyan
Write-Host "Artifacts: $OutputDirectory" -ForegroundColor Cyan

$target = Get-TargetDisplay $DeviceName
$DeviceName = $target.DeviceName
$initialTargetMode = [pscustomobject]@{
    Width=$target.Width; Height=$target.Height; FrequencyHz=$target.FrequencyHz; BitsPerPixel=$target.BitsPerPixel
}
$initialPrimary = Get-MctDisplayDevices | Where-Object Primary | Select-Object -First 1

Write-Host "Target MCT display: $DeviceName - $($target.Description)" -ForegroundColor Green
Write-MctEvent -LogPath $logPath -TestId 'SESSION' -Event 'session_start' -Data @{
    targetDevice=$DeviceName;targetDescription=$target.Description;requestedRole=$Role;configPath=$ConfigPath
}

if ($IncludePhysical) {
    $physicalDir = Join-Path $OutputDirectory 'physical'
    $physicalArgs = @{
        Sequence='Full'; OutputDirectory=$physicalDir; PostActionSeconds=5
    }
    if ($ExternalCapturePrompts) { $physicalArgs.ExternalCapturePrompts = $true }
    & (Join-Path $PSScriptRoot 'Invoke-PhysicalConnectionExercise.ps1') @physicalArgs

    # USB reconnects can cause Windows to rebuild parts of the display stack.
    $target = Get-TargetDisplay $DeviceName
    $DeviceName = $target.DeviceName
}

$roles = switch ($Role) {
    'Both'      { @('Secondary','Primary') }
    'Primary'   { @('Primary') }
    'Secondary' { @('Secondary') }
}

function Run-Role([string]$RoleName) {
    $prefix = if ($RoleName -eq 'Primary') { 'PRI' } else { 'SEC' }

    Invoke-TestCase "${prefix}_ROLE_SETUP" {
        Set-MctDisplayTopology -Mode Extend -SettleSeconds 3
        $attached = @(Get-MctDisplayDevices)
        $currentTarget = $attached | Where-Object { $_.DeviceName -ieq $DeviceName } | Select-Object -First 1
        if (-not $currentTarget) { throw "Target display $DeviceName is not attached after switching to Extend." }

        if ($RoleName -eq 'Primary') {
            Set-MctPrimaryDisplay -DeviceName $DeviceName | Out-Null
        } else {
            $reference = $null
            if ($ReferencePrimaryDeviceName) {
                $reference = $attached | Where-Object { $_.DeviceName -ieq $ReferencePrimaryDeviceName -and $_.DeviceName -ine $DeviceName } | Select-Object -First 1
            }
            if (-not $reference) {
                $reference = $attached | Where-Object { $_.DeviceName -ine $DeviceName } | Select-Object -First 1
            }
            if (-not $reference) { throw 'Secondary-role test requires another attached display to act as Windows primary.' }
            Set-MctPrimaryDisplay -DeviceName $reference.DeviceName | Out-Null
            $script:ReferencePrimaryDeviceName = $reference.DeviceName
        }

        Start-Sleep -Seconds 2
        $roleState = Resolve-MctDisplayDevice -DeviceName $DeviceName
        Write-MctEvent -LogPath $logPath -TestId "${prefix}_ROLE_SETUP" -Event 'role_verified' -Data @{
            role=$RoleName;targetPrimary=$roleState.Primary;referencePrimary=$script:ReferencePrimaryDeviceName
        }
        Save-MctDisplaySnapshot -Path (Join-Path $OutputDirectory ("snapshot-{0}-role.json" -f $prefix.ToLowerInvariant())) | Out-Null
    }

    # A clean black state gives every role the same framebuffer baseline.
    Invoke-TestCase "${prefix}_BASELINE_BLACK" {
        & (Join-Path $PSScriptRoot 'Show-TestPattern.ps1') -DeviceName $DeviceName -Pattern Black -DurationSeconds 5 -TestId "${prefix}_BASELINE_BLACK" -LogPath $logPath
    }

    if (-not $SkipModes) {
        Invoke-TestCase "${prefix}_MODE_REPRESENTATIVE" {
            & (Join-Path $PSScriptRoot 'Invoke-ModeExercise.ps1') -DeviceName $DeviceName -Kind Representative -StepSeconds $ModeStepSeconds -TestId "${prefix}_MODE_REPRESENTATIVE" -LogPath $logPath
        }
        if ($IncludeRefreshModes) {
            Invoke-TestCase "${prefix}_MODE_REFRESH" {
                & (Join-Path $PSScriptRoot 'Invoke-ModeExercise.ps1') -DeviceName $DeviceName -Kind Refresh -StepSeconds $ModeStepSeconds -TestId "${prefix}_MODE_REFRESH" -LogPath $logPath
            }
        }
    }

    if (-not $SkipPatterns) {
        foreach ($case in @($config.patternTests)) {
            $caseId = "${prefix}_$($case.id)"
            Invoke-TestCase $caseId {
                $args = @{
                    DeviceName=$DeviceName; Pattern=[string]$case.pattern; DurationSeconds=[int]$case.durationSeconds;
                    TestId=$caseId; LogPath=$logPath
                }
                if ($null -ne $case.PSObject.Properties['seed']) { $args.Seed = [int]$case.seed }
                & (Join-Path $PSScriptRoot 'Show-TestPattern.ps1') @args
            }
        }
    }

    if (-not $SkipRegions) {
        foreach ($case in @($config.regionTests)) {
            $caseId = "${prefix}_$($case.id)"
            Invoke-TestCase $caseId {
                & (Join-Path $PSScriptRoot 'Invoke-RegionExercise.ps1') -DeviceName $DeviceName -Axis ([string]$case.axis) -StepSeconds $RegionStepSeconds -TestId $caseId -LogPath $logPath
            }
        }
    }

    if (-not $SkipCursor) {
        foreach ($case in @($config.cursorTests)) {
            $caseId = "${prefix}_$($case.id)"
            Invoke-TestCase $caseId {
                & (Join-Path $PSScriptRoot 'Invoke-CursorExercise.ps1') -DeviceName $DeviceName -Mode ([string]$case.mode) -StepSeconds $CursorStepSeconds -TestId $caseId -LogPath $logPath
            }
        }
    }

    if (-not $SkipIdle) {
        foreach ($case in @($config.idleTests)) {
            $caseId = "${prefix}_$($case.id)"
            Invoke-TestCase $caseId {
                & (Join-Path $PSScriptRoot 'Show-TestPattern.ps1') -DeviceName $DeviceName -Pattern ([string]$case.pattern) -DurationSeconds ([int]$case.durationSeconds) -TestId $caseId -LogPath $logPath
            }
        }
    }

    if (-not $SkipMotion) {
        foreach ($case in @($config.motionTests)) {
            $caseId = "${prefix}_$($case.id)"
            Invoke-TestCase $caseId {
                $args = @{
                    DeviceName=$DeviceName; Pattern=[string]$case.pattern; DurationSeconds=[int]$case.durationSeconds;
                    TestId=$caseId; LogPath=$logPath
                }
                if ($null -ne $case.PSObject.Properties['stepMilliseconds']) { $args.StepMilliseconds = [int]$case.stepMilliseconds }
                & (Join-Path $PSScriptRoot 'Show-TestPattern.ps1') @args
            }
        }
    }
}

try {
    foreach ($roleName in $roles) {
        Write-Host ''
        Write-Host "=== Running MCT as Windows $roleName display ===" -ForegroundColor Green
        Run-Role $roleName
    }
} finally {
    Write-Host ''
    Write-Host 'Attempting to restore initial target mode and original primary display...' -ForegroundColor Yellow
    try {
        $attached = @(Get-MctDisplayDevices)
        if ($attached | Where-Object { $_.DeviceName -ieq $DeviceName }) {
            Set-MctDisplayMode -DeviceName $DeviceName -Width $initialTargetMode.Width -Height $initialTargetMode.Height -FrequencyHz $initialTargetMode.FrequencyHz -BitsPerPixel $initialTargetMode.BitsPerPixel | Out-Null
        }
        if ($initialPrimary -and ($attached | Where-Object { $_.DeviceName -ieq $initialPrimary.DeviceName })) {
            Set-MctPrimaryDisplay -DeviceName $initialPrimary.DeviceName | Out-Null
        }
        Write-MctEvent -LogPath $logPath -TestId 'SESSION' -Event 'initial_primary_and_target_mode_restored'
    } catch {
        Write-Warning "Automatic restoration was incomplete: $($_.Exception.Message)"
        Write-MctEvent -LogPath $logPath -TestId 'SESSION' -Event 'restore_failed' -Data @{message=$_.Exception.Message}
    }

    Save-MctDisplaySnapshot -Path $finalSnapshotPath | Out-Null
    Write-MctEvent -LogPath $logPath -TestId 'SESSION' -Event 'session_end'
}

Write-Host ''
Write-Host 'Display exercise complete.' -ForegroundColor Green
Write-Host "Event log: $logPath"
Write-Host "Initial snapshot: $initialSnapshotPath"
Write-Host "Final snapshot: $finalSnapshotPath"
