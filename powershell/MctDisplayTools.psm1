Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Initialize-MctNativeDisplayApi {
    if ('MctDisplay.NativeMethods' -as [type]) { return }

    $source = @'
using System;
using System.Runtime.InteropServices;

namespace MctDisplay
{
    [StructLayout(LayoutKind.Sequential)]
    public struct POINTL
    {
        public int x;
        public int y;
    }

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    public struct DISPLAY_DEVICE
    {
        public int cb;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)]
        public string DeviceName;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)]
        public string DeviceString;
        public int StateFlags;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)]
        public string DeviceID;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)]
        public string DeviceKey;
    }

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    public struct DEVMODE
    {
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)]
        public string dmDeviceName;
        public short dmSpecVersion;
        public short dmDriverVersion;
        public short dmSize;
        public short dmDriverExtra;
        public int dmFields;
        public POINTL dmPosition;
        public int dmDisplayOrientation;
        public int dmDisplayFixedOutput;
        public short dmColor;
        public short dmDuplex;
        public short dmYResolution;
        public short dmTTOption;
        public short dmCollate;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)]
        public string dmFormName;
        public short dmLogPixels;
        public int dmBitsPerPel;
        public int dmPelsWidth;
        public int dmPelsHeight;
        public int dmDisplayFlags;
        public int dmDisplayFrequency;
        public int dmICMMethod;
        public int dmICMIntent;
        public int dmMediaType;
        public int dmDitherType;
        public int dmReserved1;
        public int dmReserved2;
        public int dmPanningWidth;
        public int dmPanningHeight;
    }

    public static class NativeMethods
    {
        public const int ENUM_CURRENT_SETTINGS = -1;
        public const int ENUM_REGISTRY_SETTINGS = -2;

        public const int DISPLAY_DEVICE_ATTACHED_TO_DESKTOP = 0x00000001;
        public const int DISPLAY_DEVICE_PRIMARY_DEVICE = 0x00000004;

        public const int DM_POSITION = 0x00000020;
        public const int DM_BITSPERPEL = 0x00040000;
        public const int DM_PELSWIDTH = 0x00080000;
        public const int DM_PELSHEIGHT = 0x00100000;
        public const int DM_DISPLAYFREQUENCY = 0x00400000;

        public const int CDS_UPDATEREGISTRY = 0x00000001;
        public const int CDS_TEST = 0x00000002;
        public const int CDS_SET_PRIMARY = 0x00000010;
        public const int CDS_NORESET = 0x10000000;

        public const int DISP_CHANGE_SUCCESSFUL = 0;

        [DllImport("user32.dll", CharSet = CharSet.Unicode)]
        public static extern bool EnumDisplayDevices(
            string lpDevice,
            uint iDevNum,
            ref DISPLAY_DEVICE lpDisplayDevice,
            uint dwFlags);

        [DllImport("user32.dll", CharSet = CharSet.Unicode)]
        public static extern bool EnumDisplaySettings(
            string lpszDeviceName,
            int iModeNum,
            ref DEVMODE lpDevMode);

        [DllImport("user32.dll", CharSet = CharSet.Unicode, EntryPoint = "ChangeDisplaySettingsExW")]
        public static extern int ChangeDisplaySettingsEx(
            string lpszDeviceName,
            ref DEVMODE lpDevMode,
            IntPtr hwnd,
            int dwflags,
            IntPtr lParam);

        [DllImport("user32.dll", CharSet = CharSet.Unicode, EntryPoint = "ChangeDisplaySettingsExW")]
        private static extern int ChangeDisplaySettingsExNull(
            string lpszDeviceName,
            IntPtr lpDevMode,
            IntPtr hwnd,
            int dwflags,
            IntPtr lParam);

        public static int ApplyDisplayChanges()
        {
            return ChangeDisplaySettingsExNull(null, IntPtr.Zero, IntPtr.Zero, 0, IntPtr.Zero);
        }

        [DllImport("user32.dll")]
        public static extern bool SetCursorPos(int X, int Y);
    }
}
'@

    Add-Type -TypeDefinition $source -Language CSharp
}

function New-MctDevMode {
    Initialize-MctNativeDisplayApi
    $dm = New-Object MctDisplay.DEVMODE
    $dm.dmSize = [System.Runtime.InteropServices.Marshal]::SizeOf([type][MctDisplay.DEVMODE])
    return $dm
}

function Get-MctDisplayDevices {
    [CmdletBinding()]
    param([switch]$IncludeDetached)

    Initialize-MctNativeDisplayApi
    $result = @()
    $index = [uint32]0

    while ($true) {
        $device = New-Object MctDisplay.DISPLAY_DEVICE
        $device.cb = [System.Runtime.InteropServices.Marshal]::SizeOf([type][MctDisplay.DISPLAY_DEVICE])
        if (-not [MctDisplay.NativeMethods]::EnumDisplayDevices($null, $index, [ref]$device, 0)) { break }

        $attached = (($device.StateFlags -band [MctDisplay.NativeMethods]::DISPLAY_DEVICE_ATTACHED_TO_DESKTOP) -ne 0)
        if ($IncludeDetached -or $attached) {
            $dm = New-MctDevMode
            $hasMode = [MctDisplay.NativeMethods]::EnumDisplaySettings(
                $device.DeviceName,
                [MctDisplay.NativeMethods]::ENUM_CURRENT_SETTINGS,
                [ref]$dm)

            $result += [pscustomobject]@{
                Index       = [int]$index
                DeviceName  = $device.DeviceName
                Description = $device.DeviceString
                DeviceId    = $device.DeviceID
                DeviceKey   = $device.DeviceKey
                Attached    = $attached
                Primary     = (($device.StateFlags -band [MctDisplay.NativeMethods]::DISPLAY_DEVICE_PRIMARY_DEVICE) -ne 0)
                X           = if ($hasMode) { $dm.dmPosition.x } else { $null }
                Y           = if ($hasMode) { $dm.dmPosition.y } else { $null }
                Width       = if ($hasMode) { $dm.dmPelsWidth } else { $null }
                Height      = if ($hasMode) { $dm.dmPelsHeight } else { $null }
                FrequencyHz = if ($hasMode) { $dm.dmDisplayFrequency } else { $null }
                BitsPerPixel= if ($hasMode) { $dm.dmBitsPerPel } else { $null }
                StateFlags  = ('0x{0:X8}' -f $device.StateFlags)
            }
        }
        $index++
    }

    return $result
}

function Resolve-MctDisplayDevice {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$DeviceName
    )

    $display = Get-MctDisplayDevices | Where-Object { $_.DeviceName -ieq $DeviceName } | Select-Object -First 1
    if (-not $display) {
        throw "Display device '$DeviceName' is not currently attached to the desktop. Run Get-DisplaySnapshot.ps1 to inspect available devices."
    }
    return $display
}

function Select-MctDisplayDevice {
    [CmdletBinding()]
    param([string]$PreferredDeviceName)

    $displays = @(Get-MctDisplayDevices)
    if ($displays.Count -eq 0) { throw 'No attached Windows display devices were found.' }

    if ($PreferredDeviceName) {
        $preferred = $displays | Where-Object { $_.DeviceName -ieq $PreferredDeviceName } | Select-Object -First 1
        if ($preferred) { return $preferred }
    }

    Write-Host ''
    Write-Host 'Attached Windows display devices:' -ForegroundColor Cyan
    for ($i = 0; $i -lt $displays.Count; $i++) {
        $d = $displays[$i]
        $role = if ($d.Primary) { 'PRIMARY' } else { 'secondary' }
        Write-Host ("[{0}] {1}  {2}  {3}x{4}@{5}Hz  ({6})" -f $i, $d.DeviceName, $d.Description, $d.Width, $d.Height, $d.FrequencyHz, $role)
    }

    while ($true) {
        $answer = Read-Host 'Select the MCT Trigger 1+ display number'
        $selected = 0
        if ([int]::TryParse($answer, [ref]$selected) -and $selected -ge 0 -and $selected -lt $displays.Count) {
            return $displays[$selected]
        }
        Write-Warning 'Enter one of the numbers shown above.'
    }
}

function Get-MctSupportedDisplayModes {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$DeviceName
    )

    $null = Resolve-MctDisplayDevice -DeviceName $DeviceName
    Initialize-MctNativeDisplayApi
    $modes = @()
    $modeIndex = 0

    while ($true) {
        $dm = New-MctDevMode
        if (-not [MctDisplay.NativeMethods]::EnumDisplaySettings($DeviceName, $modeIndex, [ref]$dm)) { break }
        if ($dm.dmPelsWidth -gt 0 -and $dm.dmPelsHeight -gt 0 -and $dm.dmBitsPerPel -ge 16) {
            $modes += [pscustomobject]@{
                Width       = $dm.dmPelsWidth
                Height      = $dm.dmPelsHeight
                FrequencyHz = $dm.dmDisplayFrequency
                BitsPerPixel= $dm.dmBitsPerPel
            }
        }
        $modeIndex++
    }

    return $modes | Sort-Object Width, Height, FrequencyHz, BitsPerPixel -Unique
}

function Set-MctDisplayMode {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)][string]$DeviceName,
        [Parameter(Mandatory)][int]$Width,
        [Parameter(Mandatory)][int]$Height,
        [int]$FrequencyHz,
        [int]$BitsPerPixel
    )

    $current = Resolve-MctDisplayDevice -DeviceName $DeviceName
    Initialize-MctNativeDisplayApi

    $dm = New-MctDevMode
    if (-not [MctDisplay.NativeMethods]::EnumDisplaySettings($DeviceName, [MctDisplay.NativeMethods]::ENUM_CURRENT_SETTINGS, [ref]$dm)) {
        throw "Unable to read current mode for $DeviceName."
    }

    $dm.dmPelsWidth = $Width
    $dm.dmPelsHeight = $Height
    $dm.dmFields = [MctDisplay.NativeMethods]::DM_PELSWIDTH -bor [MctDisplay.NativeMethods]::DM_PELSHEIGHT

    if ($FrequencyHz -gt 0) {
        $dm.dmDisplayFrequency = $FrequencyHz
        $dm.dmFields = $dm.dmFields -bor [MctDisplay.NativeMethods]::DM_DISPLAYFREQUENCY
    }
    if ($BitsPerPixel -gt 0) {
        $dm.dmBitsPerPel = $BitsPerPixel
        $dm.dmFields = $dm.dmFields -bor [MctDisplay.NativeMethods]::DM_BITSPERPEL
    }

    $test = [MctDisplay.NativeMethods]::ChangeDisplaySettingsEx(
        $DeviceName, [ref]$dm, [IntPtr]::Zero, [MctDisplay.NativeMethods]::CDS_TEST, [IntPtr]::Zero)
    if ($test -ne [MctDisplay.NativeMethods]::DISP_CHANGE_SUCCESSFUL) {
        throw "Windows rejected ${Width}x${Height}@${FrequencyHz}Hz for $DeviceName during CDS_TEST. Return code: $test"
    }

    if ($PSCmdlet.ShouldProcess($DeviceName, "Set display mode to ${Width}x${Height}@${FrequencyHz}Hz")) {
        $result = [MctDisplay.NativeMethods]::ChangeDisplaySettingsEx(
            $DeviceName, [ref]$dm, [IntPtr]::Zero, [MctDisplay.NativeMethods]::CDS_UPDATEREGISTRY, [IntPtr]::Zero)
        if ($result -ne [MctDisplay.NativeMethods]::DISP_CHANGE_SUCCESSFUL) {
            throw "Failed to change display mode for $DeviceName. Return code: $result"
        }
    }

    return [pscustomobject]@{
        DeviceName = $DeviceName
        Previous   = "{0}x{1}@{2}Hz" -f $current.Width, $current.Height, $current.FrequencyHz
        Requested  = "${Width}x${Height}@${FrequencyHz}Hz"
    }
}

function Set-MctPrimaryDisplay {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)][string]$DeviceName
    )

    Initialize-MctNativeDisplayApi
    $displays = @(Get-MctDisplayDevices)
    $target = $displays | Where-Object { $_.DeviceName -ieq $DeviceName } | Select-Object -First 1
    if (-not $target) { throw "Display '$DeviceName' is not attached." }
    if ($target.Primary) { return $target }

    if (-not $PSCmdlet.ShouldProcess($DeviceName, 'Make display primary while preserving relative extended-desktop layout')) {
        return $target
    }

    $shiftX = -[int]$target.X
    $shiftY = -[int]$target.Y

    foreach ($display in $displays) {
        $dm = New-MctDevMode
        if (-not [MctDisplay.NativeMethods]::EnumDisplaySettings($display.DeviceName, [MctDisplay.NativeMethods]::ENUM_CURRENT_SETTINGS, [ref]$dm)) {
            throw "Unable to read current mode for $($display.DeviceName)."
        }

        $dm.dmFields = [MctDisplay.NativeMethods]::DM_POSITION
        $dm.dmPosition.x = [int]$display.X + $shiftX
        $dm.dmPosition.y = [int]$display.Y + $shiftY

        $flags = [MctDisplay.NativeMethods]::CDS_UPDATEREGISTRY -bor [MctDisplay.NativeMethods]::CDS_NORESET
        if ($display.DeviceName -ieq $DeviceName) {
            $flags = $flags -bor [MctDisplay.NativeMethods]::CDS_SET_PRIMARY
        }

        $result = [MctDisplay.NativeMethods]::ChangeDisplaySettingsEx(
            $display.DeviceName, [ref]$dm, [IntPtr]::Zero, $flags, [IntPtr]::Zero)
        if ($result -ne [MctDisplay.NativeMethods]::DISP_CHANGE_SUCCESSFUL) {
            throw "Failed staging display-position change for $($display.DeviceName). Return code: $result"
        }
    }

    $apply = [MctDisplay.NativeMethods]::ApplyDisplayChanges()
    if ($apply -ne [MctDisplay.NativeMethods]::DISP_CHANGE_SUCCESSFUL) {
        throw "Failed applying primary-display change. Return code: $apply"
    }

    Start-Sleep -Milliseconds 1200
    return Resolve-MctDisplayDevice -DeviceName $DeviceName
}

function Set-MctDisplayTopology {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('Extend','Duplicate','InternalOnly','ExternalOnly')]
        [string]$Mode,
        [int]$SettleSeconds = 3
    )

    $argument = switch ($Mode) {
        'Extend'       { '/extend' }
        'Duplicate'    { '/clone' }
        'InternalOnly' { '/internal' }
        'ExternalOnly' { '/external' }
    }

    if ($PSCmdlet.ShouldProcess('Windows display topology', "DisplaySwitch.exe $argument")) {
        $process = Start-Process -FilePath "$env:SystemRoot\System32\DisplaySwitch.exe" -ArgumentList $argument -PassThru
        $process.WaitForExit(15000) | Out-Null
        Start-Sleep -Seconds $SettleSeconds
    }
}

function Get-MctScreenBounds {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$DeviceName)

    Add-Type -AssemblyName System.Windows.Forms
    $screen = [System.Windows.Forms.Screen]::AllScreens | Where-Object { $_.DeviceName -ieq $DeviceName } | Select-Object -First 1
    if (-not $screen) { throw "No Windows Forms screen maps to '$DeviceName'." }

    return [pscustomobject]@{
        DeviceName = $screen.DeviceName
        X = $screen.Bounds.X
        Y = $screen.Bounds.Y
        Width = $screen.Bounds.Width
        Height = $screen.Bounds.Height
        Primary = $screen.Primary
    }
}

function ConvertFrom-MctUInt16String {
    param($Value)
    if ($null -eq $Value) { return $null }
    return -join @($Value | Where-Object { $_ -ne 0 } | ForEach-Object { [char]$_ })
}

function Get-MctDisplaySnapshot {
    [CmdletBinding()]
    param()

    Add-Type -AssemblyName System.Windows.Forms

    $screens = @([System.Windows.Forms.Screen]::AllScreens | ForEach-Object {
        [pscustomobject]@{
            DeviceName = $_.DeviceName
            Primary = $_.Primary
            Bounds = [pscustomobject]@{ X=$_.Bounds.X; Y=$_.Bounds.Y; Width=$_.Bounds.Width; Height=$_.Bounds.Height }
            WorkingArea = [pscustomobject]@{ X=$_.WorkingArea.X; Y=$_.WorkingArea.Y; Width=$_.WorkingArea.Width; Height=$_.WorkingArea.Height }
        }
    })

    $monitorIds = @()
    try {
        $monitorIds = @(Get-CimInstance -Namespace root\wmi -ClassName WmiMonitorID -ErrorAction Stop | ForEach-Object {
            [pscustomobject]@{
                InstanceName = $_.InstanceName
                Active = $_.Active
                Manufacturer = ConvertFrom-MctUInt16String $_.ManufacturerName
                ProductCode = ConvertFrom-MctUInt16String $_.ProductCodeID
                SerialNumber = ConvertFrom-MctUInt16String $_.SerialNumberID
                UserFriendlyName = ConvertFrom-MctUInt16String $_.UserFriendlyName
            }
        })
    } catch {
        $monitorIds = @([pscustomobject]@{ Error = $_.Exception.Message })
    }

    $videoControllers = @()
    try {
        $videoControllers = @(Get-CimInstance Win32_VideoController -ErrorAction Stop | Select-Object Name, PNPDeviceID, DriverVersion, DriverDate, CurrentHorizontalResolution, CurrentVerticalResolution, CurrentRefreshRate, Status)
    } catch {
        $videoControllers = @([pscustomobject]@{ Error = $_.Exception.Message })
    }

    return [pscustomobject]@{
        TimestampUtc = [DateTime]::UtcNow.ToString('o')
        ComputerName = $env:COMPUTERNAME
        WindowsVersion = [Environment]::OSVersion.VersionString
        PowerShellVersion = $PSVersionTable.PSVersion.ToString()
        Displays = @(Get-MctDisplayDevices)
        Screens = $screens
        MonitorIds = $monitorIds
        VideoControllers = $videoControllers
    }
}

function Save-MctDisplaySnapshot {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path
    )

    $directory = Split-Path -Parent $Path
    if ($directory -and -not (Test-Path $directory)) { New-Item -ItemType Directory -Path $directory -Force | Out-Null }
    Get-MctDisplaySnapshot | ConvertTo-Json -Depth 8 | Set-Content -Path $Path -Encoding UTF8
    return Get-Item $Path
}

function Write-MctEvent {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$LogPath,
        [Parameter(Mandatory)][string]$TestId,
        [Parameter(Mandatory)][string]$Event,
        [hashtable]$Data = @{}
    )

    $directory = Split-Path -Parent $LogPath
    if ($directory -and -not (Test-Path $directory)) { New-Item -ItemType Directory -Path $directory -Force | Out-Null }

    $record = [ordered]@{
        timestampUtc = [DateTime]::UtcNow.ToString('o')
        timestampLocal = (Get-Date).ToString('o')
        testId = $TestId
        event = $Event
        data = $Data
    }
    Add-Content -Path $LogPath -Value ($record | ConvertTo-Json -Compress -Depth 6) -Encoding UTF8
    Write-Host ("[{0}] [{1}] {2}" -f (Get-Date -Format 'HH:mm:ss.fff'), $TestId, $Event) -ForegroundColor DarkCyan
}

function Wait-MctInterval {
    [CmdletBinding()]
    param(
        [int]$Seconds,
        [string]$Message = 'Holding state'
    )

    if ($Seconds -le 0) { return }
    for ($remaining = $Seconds; $remaining -gt 0; $remaining--) {
        Write-Progress -Activity $Message -Status "$remaining second(s) remaining" -PercentComplete ((($Seconds-$remaining)/[double]$Seconds)*100)
        Start-Sleep -Seconds 1
    }
    Write-Progress -Activity $Message -Completed
}

function Invoke-MctOperatorPrompt {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Message,
        [string]$LogPath,
        [string]$TestId = 'HUMAN'
    )

    Write-Host ''
    Write-Host 'HUMAN ACTION REQUIRED' -ForegroundColor Yellow
    Write-Host $Message -ForegroundColor Yellow
    if ($LogPath) { Write-MctEvent -LogPath $LogPath -TestId $TestId -Event 'operator_prompt' -Data @{ message=$Message } }
    $answer = Read-Host 'Press ENTER when the action is complete (or type a note)'
    if ($LogPath) { Write-MctEvent -LogPath $LogPath -TestId $TestId -Event 'operator_confirmed' -Data @{ response=$answer } }
    return $answer
}

Initialize-MctNativeDisplayApi

Export-ModuleMember -Function @(
    'Get-MctDisplayDevices',
    'Select-MctDisplayDevice',
    'Resolve-MctDisplayDevice',
    'Get-MctSupportedDisplayModes',
    'Set-MctDisplayMode',
    'Set-MctPrimaryDisplay',
    'Set-MctDisplayTopology',
    'Get-MctScreenBounds',
    'Get-MctDisplaySnapshot',
    'Save-MctDisplaySnapshot',
    'Write-MctEvent',
    'Wait-MctInterval',
    'Invoke-MctOperatorPrompt'
)
