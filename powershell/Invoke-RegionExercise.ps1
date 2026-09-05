[CmdletBinding()]
param(
    [string]$DeviceName,
    [ValidateSet('X','Y','Width','Height','Color','TwoRegions')]
    [string]$Axis = 'X',
    [int]$StepSeconds = 3,
    [int]$BaselineSeconds = 3,
    [int]$RectangleSize = 100,
    [string]$TestId,
    [string]$LogPath,
    [switch]$NoTopMost
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'MctDisplayTools.psm1') -Force
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

if (-not $DeviceName) { $DeviceName = (Select-MctDisplayDevice).DeviceName }
if (-not $TestId) { $TestId = "REGION_$($Axis.ToUpperInvariant())" }
$bounds = Get-MctScreenBounds -DeviceName $DeviceName

$baseX = [Math]::Max(0, [int]($bounds.Width / 4))
$baseY = [Math]::Max(0, [int]($bounds.Height / 4))
$size = [Math]::Max(8, [Math]::Min($RectangleSize, [Math]::Min($bounds.Width, $bounds.Height)))

$states = @()
switch ($Axis) {
    'X' {
        $maxX = [Math]::Max(0, $bounds.Width - $size)
        foreach ($x in @(0, [int]($maxX/3), [int](2*$maxX/3), $maxX)) {
            $states += [pscustomobject]@{ Rects=@([pscustomobject]@{X=$x;Y=$baseY;W=$size;H=$size;Color='Red'}); Label="X=$x" }
        }
    }
    'Y' {
        $maxY = [Math]::Max(0, $bounds.Height - $size)
        foreach ($y in @(0, [int]($maxY/3), [int](2*$maxY/3), $maxY)) {
            $states += [pscustomobject]@{ Rects=@([pscustomobject]@{X=$baseX;Y=$y;W=$size;H=$size;Color='Red'}); Label="Y=$y" }
        }
    }
    'Width' {
        $values = @(32, 64, 128, 256, 400) | Where-Object { $_ -le ($bounds.Width - $baseX) } | Select-Object -Unique
        foreach ($w in $values) {
            $states += [pscustomobject]@{ Rects=@([pscustomobject]@{X=$baseX;Y=$baseY;W=$w;H=$size;Color='Red'}); Label="Width=$w" }
        }
    }
    'Height' {
        $values = @(32, 64, 128, 256, 400) | Where-Object { $_ -le ($bounds.Height - $baseY) } | Select-Object -Unique
        foreach ($h in $values) {
            $states += [pscustomobject]@{ Rects=@([pscustomobject]@{X=$baseX;Y=$baseY;W=$size;H=$h;Color='Red'}); Label="Height=$h" }
        }
    }
    'Color' {
        foreach ($color in @('Red','Green','Blue','White')) {
            $states += [pscustomobject]@{ Rects=@([pscustomobject]@{X=$baseX;Y=$baseY;W=$size;H=$size;Color=$color}); Label="Color=$color" }
        }
    }
    'TwoRegions' {
        $r1 = [pscustomobject]@{X=[int]($bounds.Width/8);Y=[int]($bounds.Height/3);W=$size;H=$size;Color='Red'}
        $r2 = [pscustomobject]@{X=[Math]::Max(0,[int](3*$bounds.Width/4)-$size);Y=[int]($bounds.Height/3);W=$size;H=$size;Color='Blue'}
        $states += [pscustomobject]@{ Rects=@($r1); Label='One region' }
        $states += [pscustomobject]@{ Rects=@($r1,$r2); Label='Two distant regions' }
    }
}

if ($states.Count -eq 0) { throw "No valid states could be generated for $Axis at $($bounds.Width)x$($bounds.Height)." }

$form = New-Object System.Windows.Forms.Form
$form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::None
$form.StartPosition = [System.Windows.Forms.FormStartPosition]::Manual
$form.Location = New-Object System.Drawing.Point($bounds.X, $bounds.Y)
$form.Size = New-Object System.Drawing.Size($bounds.Width, $bounds.Height)
$form.ShowInTaskbar = $false
$form.TopMost = -not $NoTopMost
$form.KeyPreview = $true
$form.BackColor = [System.Drawing.Color]::Black
$currentState = $null

$form.Add_KeyDown({ param($sender,$e) if ($e.KeyCode -eq [System.Windows.Forms.Keys]::Escape) { $sender.Close() } })
$form.Add_Paint({
    param($sender,$e)
    $e.Graphics.Clear([System.Drawing.Color]::Black)
    if ($null -eq $currentState) { return }
    foreach ($rect in $currentState.Rects) {
        $color = if ($rect.Color -eq 'Green') { [System.Drawing.Color]::Lime } else { [System.Drawing.Color]::FromName($rect.Color) }
        $brush = New-Object System.Drawing.SolidBrush $color
        try { $e.Graphics.FillRectangle($brush, [int]$rect.X, [int]$rect.Y, [int]$rect.W, [int]$rect.H) }
        finally { $brush.Dispose() }
    }
})

function Hold-Form([int]$Seconds) {
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    while (-not $form.IsDisposed -and $sw.Elapsed.TotalSeconds -lt $Seconds) {
        [System.Windows.Forms.Application]::DoEvents()
        Start-Sleep -Milliseconds 10
    }
}

if ($LogPath) { Write-MctEvent -LogPath $LogPath -TestId $TestId -Event 'region_exercise_start' -Data @{deviceName=$DeviceName;axis=$Axis;states=$states.Count} }
$form.Show(); $form.Activate()
try {
    $currentState = $null
    $form.Invalidate(); $form.Update()
    if ($LogPath) { Write-MctEvent -LogPath $LogPath -TestId $TestId -Event 'baseline_black' }
    Hold-Form $BaselineSeconds

    $step = 0
    foreach ($state in $states) {
        if ($form.IsDisposed) { break }
        $currentState = $state
        $form.Invalidate(); $form.Update()
        $rectData = @($state.Rects | ForEach-Object { @{x=$_.X;y=$_.Y;width=$_.W;height=$_.H;color=$_.Color} })
        if ($LogPath) { Write-MctEvent -LogPath $LogPath -TestId $TestId -Event 'region_step' -Data @{step=$step;label=$state.Label;rectangles=$rectData} }
        Write-Host "[$TestId] Step $step: $($state.Label)" -ForegroundColor Cyan
        Hold-Form $StepSeconds
        $step++
    }
} finally {
    if (-not $form.IsDisposed) { $form.Close() }
    $form.Dispose()
}
if ($LogPath) { Write-MctEvent -LogPath $LogPath -TestId $TestId -Event 'region_exercise_end' }
