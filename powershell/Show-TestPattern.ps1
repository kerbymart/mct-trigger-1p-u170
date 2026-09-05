[CmdletBinding()]
param(
    [string]$DeviceName,

    [ValidateSet(
        'Black','White','Red','Green','Blue','Gray',
        'HorizontalSplit','VerticalSplit','Quadrants',
        'Checkerboard','Gradient','Noise','Region','Alternating','Text'
    )]
    [string]$Pattern = 'Black',

    [int]$DurationSeconds = 5,
    [int]$StepMilliseconds = 500,
    [int]$Seed = 1701,

    [int]$RegionX = 0,
    [int]$RegionY = 0,
    [int]$RegionWidth = 100,
    [int]$RegionHeight = 100,
    [ValidateSet('White','Red','Green','Blue','Gray','Yellow','Cyan','Magenta')]
    [string]$RegionColor = 'Red',

    [string]$Text = 'MCT Trigger 1+ test',
    [string]$TestId = 'PATTERN',
    [string]$LogPath,
    [switch]$NoTopMost,
    [switch]$HideCursor
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'MctDisplayTools.psm1') -Force
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

if (-not $DeviceName) {
    $DeviceName = (Select-MctDisplayDevice).DeviceName
}
$bounds = Get-MctScreenBounds -DeviceName $DeviceName

if ($LogPath) {
    Write-MctEvent -LogPath $LogPath -TestId $TestId -Event 'pattern_start' -Data @{
        deviceName=$DeviceName; pattern=$Pattern; durationSeconds=$DurationSeconds;
        regionX=$RegionX; regionY=$RegionY; regionWidth=$RegionWidth; regionHeight=$RegionHeight;
        regionColor=$RegionColor; seed=$Seed
    }
}

$form = New-Object System.Windows.Forms.Form
$form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::None
$form.StartPosition = [System.Windows.Forms.FormStartPosition]::Manual
$form.Location = New-Object System.Drawing.Point($bounds.X, $bounds.Y)
$form.Size = New-Object System.Drawing.Size($bounds.Width, $bounds.Height)
$form.ShowInTaskbar = $false
$form.TopMost = -not $NoTopMost
$form.KeyPreview = $true
$form.BackColor = [System.Drawing.Color]::Black

$alternateWhite = $false
$noiseBitmap = $null

if ($Pattern -eq 'Noise') {
    $noiseBitmap = New-Object System.Drawing.Bitmap 256, 256
    $random = New-Object System.Random $Seed
    for ($y = 0; $y -lt 256; $y++) {
        for ($x = 0; $x -lt 256; $x++) {
            $r = $random.Next(0, 256)
            $g = $random.Next(0, 256)
            $b = $random.Next(0, 256)
            $noiseBitmap.SetPixel($x, $y, [System.Drawing.Color]::FromArgb($r, $g, $b))
        }
    }
}

$form.Add_KeyDown({
    param($sender, $eventArgs)
    if ($eventArgs.KeyCode -eq [System.Windows.Forms.Keys]::Escape) { $sender.Close() }
})

$form.Add_Paint({
    param($sender, $eventArgs)
    $g = $eventArgs.Graphics
    $w = $sender.ClientSize.Width
    $h = $sender.ClientSize.Height

    switch ($Pattern) {
        'Black' { $g.Clear([System.Drawing.Color]::Black) }
        'White' { $g.Clear([System.Drawing.Color]::White) }
        'Red'   { $g.Clear([System.Drawing.Color]::Red) }
        'Green' { $g.Clear([System.Drawing.Color]::Lime) }
        'Blue'  { $g.Clear([System.Drawing.Color]::Blue) }
        'Gray'  { $g.Clear([System.Drawing.Color]::FromArgb(128,128,128)) }

        'HorizontalSplit' {
            $g.Clear([System.Drawing.Color]::Black)
            $left = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::Red)
            try { $g.FillRectangle($left, 0, 0, [int]($w/2), $h) } finally { $left.Dispose() }
        }

        'VerticalSplit' {
            $g.Clear([System.Drawing.Color]::Black)
            $top = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::Lime)
            try { $g.FillRectangle($top, 0, 0, $w, [int]($h/2)) } finally { $top.Dispose() }
        }

        'Quadrants' {
            $colors = @(
                [System.Drawing.Color]::Red,
                [System.Drawing.Color]::Lime,
                [System.Drawing.Color]::Blue,
                [System.Drawing.Color]::White
            )
            $rects = @(
                (New-Object System.Drawing.Rectangle 0,0,[int]($w/2),[int]($h/2)),
                (New-Object System.Drawing.Rectangle ([int]($w/2)),0,($w-[int]($w/2)),[int]($h/2)),
                (New-Object System.Drawing.Rectangle 0,([int]($h/2)),[int]($w/2),($h-[int]($h/2))),
                (New-Object System.Drawing.Rectangle ([int]($w/2)),([int]($h/2)),($w-[int]($w/2)),($h-[int]($h/2)))
            )
            for ($i=0; $i -lt 4; $i++) {
                $brush = New-Object System.Drawing.SolidBrush $colors[$i]
                try { $g.FillRectangle($brush, $rects[$i]) } finally { $brush.Dispose() }
            }
        }

        'Checkerboard' {
            $cell = 32
            $g.Clear([System.Drawing.Color]::Black)
            $brush = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::White)
            try {
                for ($y=0; $y -lt $h; $y += $cell) {
                    for ($x=0; $x -lt $w; $x += $cell) {
                        if ((([int]($x/$cell) + [int]($y/$cell)) % 2) -eq 0) {
                            $g.FillRectangle($brush, $x, $y, [Math]::Min($cell,$w-$x), [Math]::Min($cell,$h-$y))
                        }
                    }
                }
            } finally { $brush.Dispose() }
        }

        'Gradient' {
            $rect = New-Object System.Drawing.Rectangle 0,0,$w,$h
            $brush = New-Object System.Drawing.Drawing2D.LinearGradientBrush(
                $rect,
                [System.Drawing.Color]::Black,
                [System.Drawing.Color]::White,
                [System.Drawing.Drawing2D.LinearGradientMode]::Horizontal)
            try { $g.FillRectangle($brush, $rect) } finally { $brush.Dispose() }
        }

        'Noise' {
            $texture = New-Object System.Drawing.TextureBrush $noiseBitmap
            try {
                $texture.WrapMode = [System.Drawing.Drawing2D.WrapMode]::Tile
                $g.FillRectangle($texture, 0, 0, $w, $h)
            } finally { $texture.Dispose() }
        }

        'Region' {
            $g.Clear([System.Drawing.Color]::Black)
            $color = [System.Drawing.Color]::FromName($RegionColor)
            if ($RegionColor -eq 'Green') { $color = [System.Drawing.Color]::Lime }
            if ($RegionColor -eq 'Gray') { $color = [System.Drawing.Color]::FromArgb(128,128,128) }
            $brush = New-Object System.Drawing.SolidBrush $color
            try { $g.FillRectangle($brush, $RegionX, $RegionY, $RegionWidth, $RegionHeight) } finally { $brush.Dispose() }
        }

        'Alternating' {
            if ($alternateWhite) { $g.Clear([System.Drawing.Color]::White) }
            else { $g.Clear([System.Drawing.Color]::Black) }
        }

        'Text' {
            $g.Clear([System.Drawing.Color]::Black)
            $font = New-Object System.Drawing.Font 'Consolas', 28, ([System.Drawing.FontStyle]::Regular)
            $brush = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::White)
            try {
                $g.DrawString($Text, $font, $brush, 40, 40)
                $g.DrawString("$DeviceName  ${w}x${h}", $font, $brush, 40, 90)
            } finally { $brush.Dispose(); $font.Dispose() }
        }
    }
})

$originalCursor = [System.Windows.Forms.Cursor]::Position
$form.Show()
$form.Activate()
if ($HideCursor) { [System.Windows.Forms.Cursor]::Hide() }

try {
    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    $nextToggle = 0
    while (-not $form.IsDisposed -and $stopwatch.Elapsed.TotalSeconds -lt $DurationSeconds) {
        if ($Pattern -eq 'Alternating' -and $stopwatch.ElapsedMilliseconds -ge $nextToggle) {
            $alternateWhite = -not $alternateWhite
            $nextToggle = $stopwatch.ElapsedMilliseconds + [Math]::Max(50,$StepMilliseconds)
            if ($LogPath) {
                Write-MctEvent -LogPath $LogPath -TestId $TestId -Event 'pattern_step' -Data @{ state=if($alternateWhite){'white'}else{'black'} }
            }
            $form.Invalidate()
        }
        [System.Windows.Forms.Application]::DoEvents()
        Start-Sleep -Milliseconds 10
    }
} finally {
    if ($HideCursor) { [System.Windows.Forms.Cursor]::Show() }
    [System.Windows.Forms.Cursor]::Position = $originalCursor
    if (-not $form.IsDisposed) { $form.Close() }
    $form.Dispose()
    if ($noiseBitmap) { $noiseBitmap.Dispose() }
}

if ($LogPath) {
    Write-MctEvent -LogPath $LogPath -TestId $TestId -Event 'pattern_end' -Data @{ deviceName=$DeviceName; pattern=$Pattern }
}
