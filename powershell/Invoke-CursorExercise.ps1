[CmdletBinding()]
param(
    [string]$DeviceName,
    [ValidateSet('Horizontal','Vertical','Diagonal','Shapes')]
    [string]$Mode = 'Horizontal',
    [int]$StepSeconds = 2,
    [int]$BaselineSeconds = 3,
    [string]$TestId,
    [string]$LogPath,
    [switch]$NoTopMost
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'MctDisplayTools.psm1') -Force
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

if (-not $DeviceName) { $DeviceName = (Select-MctDisplayDevice).DeviceName }
if (-not $TestId) { $TestId = "CURSOR_$($Mode.ToUpperInvariant())" }
$bounds = Get-MctScreenBounds -DeviceName $DeviceName
$originalCursor = [System.Windows.Forms.Cursor]::Position

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

function Hold-Form([int]$Seconds) {
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    while (-not $form.IsDisposed -and $sw.Elapsed.TotalSeconds -lt $Seconds) {
        [System.Windows.Forms.Application]::DoEvents()
        Start-Sleep -Milliseconds 10
    }
}

$positions = @()
switch ($Mode) {
    'Horizontal' {
        $y = [int]($bounds.Height/2)
        foreach ($fraction in @(0.10,0.30,0.50,0.70,0.90)) {
            $positions += [pscustomobject]@{ X=[int]($bounds.Width*$fraction); Y=$y; Label="X=$fraction" }
        }
    }
    'Vertical' {
        $x = [int]($bounds.Width/2)
        foreach ($fraction in @(0.10,0.30,0.50,0.70,0.90)) {
            $positions += [pscustomobject]@{ X=$x; Y=[int]($bounds.Height*$fraction); Label="Y=$fraction" }
        }
    }
    'Diagonal' {
        foreach ($fraction in @(0.10,0.30,0.50,0.70,0.90)) {
            $positions += [pscustomobject]@{ X=[int]($bounds.Width*$fraction); Y=[int]($bounds.Height*$fraction); Label="XY=$fraction" }
        }
    }
}

if ($LogPath) { Write-MctEvent -LogPath $LogPath -TestId $TestId -Event 'cursor_exercise_start' -Data @{deviceName=$DeviceName;mode=$Mode} }
$form.Show(); $form.Activate()
try {
    [System.Windows.Forms.Cursor]::Position = New-Object System.Drawing.Point($bounds.X + [int]($bounds.Width/2), $bounds.Y + [int]($bounds.Height/2))
    if ($LogPath) { Write-MctEvent -LogPath $LogPath -TestId $TestId -Event 'baseline_cursor_center' }
    Hold-Form $BaselineSeconds

    if ($Mode -eq 'Shapes') {
        $shapes = @(
            @{ Name='Arrow'; Cursor=[System.Windows.Forms.Cursors]::Arrow },
            @{ Name='IBeam'; Cursor=[System.Windows.Forms.Cursors]::IBeam },
            @{ Name='Cross'; Cursor=[System.Windows.Forms.Cursors]::Cross },
            @{ Name='SizeAll'; Cursor=[System.Windows.Forms.Cursors]::SizeAll },
            @{ Name='Hand'; Cursor=[System.Windows.Forms.Cursors]::Hand }
        )
        $step = 0
        foreach ($shape in $shapes) {
            if ($form.IsDisposed) { break }
            $form.Cursor = $shape.Cursor
            [System.Windows.Forms.Cursor]::Position = New-Object System.Drawing.Point($bounds.X + [int]($bounds.Width/2), $bounds.Y + [int]($bounds.Height/2))
            if ($LogPath) { Write-MctEvent -LogPath $LogPath -TestId $TestId -Event 'cursor_shape_step' -Data @{step=$step;shape=$shape.Name} }
            Write-Host "[$TestId] Step $step: shape $($shape.Name)" -ForegroundColor Cyan
            Hold-Form $StepSeconds
            $step++
        }
    } else {
        $step = 0
        foreach ($position in $positions) {
            if ($form.IsDisposed) { break }
            $absoluteX = $bounds.X + $position.X
            $absoluteY = $bounds.Y + $position.Y
            [System.Windows.Forms.Cursor]::Position = New-Object System.Drawing.Point($absoluteX, $absoluteY)
            if ($LogPath) { Write-MctEvent -LogPath $LogPath -TestId $TestId -Event 'cursor_move_step' -Data @{step=$step;relativeX=$position.X;relativeY=$position.Y;absoluteX=$absoluteX;absoluteY=$absoluteY} }
            Write-Host "[$TestId] Step $step: cursor -> ($($position.X), $($position.Y))" -ForegroundColor Cyan
            Hold-Form $StepSeconds
            $step++
        }
    }
} finally {
    [System.Windows.Forms.Cursor]::Position = $originalCursor
    if (-not $form.IsDisposed) { $form.Close() }
    $form.Dispose()
}
if ($LogPath) { Write-MctEvent -LogPath $LogPath -TestId $TestId -Event 'cursor_exercise_end' }
