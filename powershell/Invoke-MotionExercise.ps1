[CmdletBinding()]
param(
    [string]$DeviceName,
    [ValidateSet('MovingRectangle','FullscreenAlternating')]
    [string]$Mode = 'MovingRectangle',
    [int]$DurationSeconds = 12,
    [int]$StepMilliseconds = 100,
    [int]$RectangleSize = 128,
    [int]$PixelsPerStep = 24,
    [string]$TestId,
    [string]$LogPath,
    [switch]$NoTopMost
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'MctDisplayTools.psm1') -Force
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

if (-not $DeviceName) { $DeviceName = (Select-MctDisplayDevice).DeviceName }
if (-not $TestId) { $TestId = "MOTION_$($Mode.ToUpperInvariant())" }
$bounds = Get-MctScreenBounds -DeviceName $DeviceName

$size = [Math]::Max(8, [Math]::Min($RectangleSize, [Math]::Min($bounds.Width,$bounds.Height)))
$maxX = [Math]::Max(0, $bounds.Width - $size)
$y = [Math]::Max(0, [int](($bounds.Height-$size)/2))
$currentX = 0
$direction = 1
$white = $false
$stepCount = 0

$form = New-Object System.Windows.Forms.Form
$form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::None
$form.StartPosition = [System.Windows.Forms.FormStartPosition]::Manual
$form.Location = New-Object System.Drawing.Point($bounds.X, $bounds.Y)
$form.Size = New-Object System.Drawing.Size($bounds.Width, $bounds.Height)
$form.ShowInTaskbar = $false
$form.TopMost = -not $NoTopMost
$form.KeyPreview = $true
$form.BackColor = [System.Drawing.Color]::Black
$form.Add_KeyDown({ param($sender,$e) if ($e.KeyCode -eq [System.Windows.Forms.Keys]::Escape) { $sender.Close() } })

$form.Add_Paint({
    param($sender,$e)
    if ($Mode -eq 'FullscreenAlternating') {
        if ($white) { $e.Graphics.Clear([System.Drawing.Color]::White) }
        else { $e.Graphics.Clear([System.Drawing.Color]::Black) }
        return
    }

    $e.Graphics.Clear([System.Drawing.Color]::Black)
    $brush = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::Red)
    try { $e.Graphics.FillRectangle($brush, $currentX, $y, $size, $size) }
    finally { $brush.Dispose() }
})

if ($LogPath) {
    Write-MctEvent -LogPath $LogPath -TestId $TestId -Event 'motion_start' -Data @{
        deviceName=$DeviceName;mode=$Mode;durationSeconds=$DurationSeconds;stepMilliseconds=$StepMilliseconds;
        rectangleSize=$size;pixelsPerStep=$PixelsPerStep
    }
}

$form.Show(); $form.Activate()
try {
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $nextStep = 0L
    while (-not $form.IsDisposed -and $sw.Elapsed.TotalSeconds -lt $DurationSeconds) {
        if ($sw.ElapsedMilliseconds -ge $nextStep) {
            if ($Mode -eq 'FullscreenAlternating') {
                $white = -not $white
            } else {
                $currentX += ($direction * [Math]::Max(1,$PixelsPerStep))
                if ($currentX -ge $maxX) { $currentX = $maxX; $direction = -1 }
                elseif ($currentX -le 0) { $currentX = 0; $direction = 1 }
            }
            $stepCount++
            $form.Invalidate()
            $nextStep += [Math]::Max(16,$StepMilliseconds)
        }
        [System.Windows.Forms.Application]::DoEvents()
        Start-Sleep -Milliseconds 2
    }
} finally {
    if (-not $form.IsDisposed) { $form.Close() }
    $form.Dispose()
}

if ($LogPath) {
    Write-MctEvent -LogPath $LogPath -TestId $TestId -Event 'motion_end' -Data @{steps=$stepCount;finalX=$currentX}
}
