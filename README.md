# MCT Trigger 1+ / NComputing U170 display exercise harness

PowerShell tools for generating deterministic Windows display activity while the **MCT Trigger 1+ USB-to-VGA controller inside an NComputing U170** is observed independently with USBPcap/Wireshark.

The PowerShell harness deliberately **does not start, stop, filter, or control USBPcap**. Its job is only to create repeatable display stimuli and timestamped human-action markers. This keeps the display workload independent from the packet-capture mechanism.

The primary campaign runs the same workload with the Trigger 1+ display in two Windows roles:

1. **Secondary display** in an extended desktop, with another monitor kept as Windows primary.
2. **Primary display** in an extended desktop.

This is research/test tooling. The scripts must still be validated on the actual U170 hardware and installed MCT/NComputing driver before relying on them for unattended runs.

## Requirements

- Windows 10/11 or another Windows version supported by the installed U170 driver
- Windows PowerShell 5.1 or newer
- Interactive local desktop session
- NComputing U170 and its display driver installed
- Two active displays for the secondary-display role
- USBPcap/Wireshark only when packet capture is desired

Avoid running the display campaign through Remote Desktop if possible. RDP can replace or virtualize the physical Windows display topology.

## Repository layout

```text
config/
  test-cases.json                    Data-driven visual test definitions

powershell/
  MctDisplayTools.psm1               Win32 display API and shared helpers
  Test-LabEnvironment.ps1            Preflight checks
  Get-DisplaySnapshot.ps1            Display/monitor inventory and JSON snapshot
  Set-DisplayTopology.ps1            Extend/duplicate/internal/external wrapper
  Set-PrimaryDisplay.ps1             Make a selected display Windows primary
  Set-DisplayMode.ps1                Set one explicit supported display mode
  Show-TestPattern.ps1               Deterministic fullscreen visual patterns
  Invoke-ModeExercise.ps1            Supported resolution/refresh-rate exercise
  Invoke-RegionExercise.ps1          Controlled X/Y/width/height/color updates
  Invoke-CursorExercise.ps1          Controlled cursor movement and shape changes
  Invoke-PhysicalConnectionExercise.ps1
                                      Human-assisted VGA/USB plug/unplug tests
  Invoke-DisplayExercise.ps1         Main primary/secondary campaign orchestrator
```

Local results are written under `artifacts/` by default and are not intended to be source-controlled.

## First run

Open a local PowerShell window in the repository directory.

```powershell
Set-ExecutionPolicy -Scope Process Bypass

.\powershell\Test-LabEnvironment.ps1
```

Then inspect the displays:

```powershell
.\powershell\Get-DisplaySnapshot.ps1 -IncludeModes
```

The inventory shows Windows device names such as:

```text
\\.\DISPLAY1
\\.\DISPLAY2
```

Do not assume that `DISPLAY2` is always the U170. Select the display by its current inventory and verify it visually when first configuring the lab.

## Run the complete primary + secondary campaign

```powershell
.\powershell\Invoke-DisplayExercise.ps1 -Role Both
```

If `-DeviceName` is omitted, the harness asks which Windows display is the Trigger 1+ output.

To explicitly select it:

```powershell
.\powershell\Invoke-DisplayExercise.ps1 `
    -DeviceName '\\.\DISPLAY2' `
    -Role Both
```

The default campaign performs, for both roles:

- role/topology setup
- clean black baseline
- representative supported resolution changes
- full-screen black, white, red, green, blue, and gray
- horizontal and vertical split patterns
- four-quadrant pattern
- checkerboard
- gradient
- deterministic high-entropy noise
- controlled rectangle X movement
- controlled rectangle Y movement
- rectangle width changes
- rectangle height changes
- rectangle color changes
- one-region versus two-region update
- horizontal cursor movement
- vertical cursor movement
- diagonal cursor movement
- cursor shape changes
- short and 30-second idle states
- full-screen black/white alternation

The same test IDs are prefixed with:

- `SEC_` when the MCT display is secondary
- `PRI_` when the MCT display is primary

This makes primary/secondary PCAP comparisons straightforward.

## Synchronizing with independent USBPcap captures

The harness never controls USBPcap itself.

For manual or agent-driven capture synchronization, add:

```powershell
.\powershell\Invoke-DisplayExercise.ps1 `
    -Role Both `
    -ExternalCapturePrompts
```

At every test boundary the harness pauses and asks the operator/agent to:

1. start the independent USBPcap/Wireshark capture;
2. confirm that capture is running;
3. let the deterministic display test execute;
4. stop/save the independent capture.

Without `-ExternalCapturePrompts`, tests run continuously and can be correlated afterward using `events.jsonl` timestamps.

## Include physical VGA and USB actions

Physical cable operations are intentionally interactive.

Run them separately:

```powershell
.\powershell\Invoke-PhysicalConnectionExercise.ps1 `
    -Sequence Full `
    -ExternalCapturePrompts
```

`Full` performs:

```text
VGA disconnect
VGA connect
USB disconnect
USB reconnect
```

The script captures display snapshots before and after each action and asks the human operator for confirmation. VGA connect and USB reconnect also request a simple visible-output result such as `PASS`, `ARTIFACT`, `NO_IMAGE`, or `NO_SYNC`.

The physical cycle can also be inserted before the automated display campaign:

```powershell
.\powershell\Invoke-DisplayExercise.ps1 `
    -Role Both `
    -IncludePhysical `
    -ExternalCapturePrompts
```

## Run only the MCT secondary-display campaign

```powershell
.\powershell\Invoke-DisplayExercise.ps1 -Role Secondary
```

If more than one non-MCT display exists, specify which one should remain Windows primary:

```powershell
.\powershell\Invoke-DisplayExercise.ps1 `
    -Role Secondary `
    -DeviceName '\\.\DISPLAY3' `
    -ReferencePrimaryDeviceName '\\.\DISPLAY1'
```

## Run only the MCT primary-display campaign

```powershell
.\powershell\Invoke-DisplayExercise.ps1 `
    -Role Primary `
    -DeviceName '\\.\DISPLAY2'
```

## Run individual experiments

### Static fullscreen pattern

```powershell
.\powershell\Show-TestPattern.ps1 `
    -DeviceName '\\.\DISPLAY2' `
    -Pattern Quadrants `
    -DurationSeconds 10
```

Available pattern types include:

```text
Black
White
Red
Green
Blue
Gray
HorizontalSplit
VerticalSplit
Quadrants
Checkerboard
Gradient
Noise
Region
Alternating
Text
```

### Controlled region movement

```powershell
.\powershell\Invoke-RegionExercise.ps1 `
    -DeviceName '\\.\DISPLAY2' `
    -Axis X
```

Valid axes/tests:

```text
X
Y
Width
Height
Color
TwoRegions
```

Each run keeps a black fullscreen window open and changes only the requested property between steps, avoiding desktop exposure between region states.

### Cursor movement

```powershell
.\powershell\Invoke-CursorExercise.ps1 `
    -DeviceName '\\.\DISPLAY2' `
    -Mode Horizontal
```

Modes:

```text
Horizontal
Vertical
Diagonal
Shapes
```

### Representative supported resolutions

```powershell
.\powershell\Invoke-ModeExercise.ps1 `
    -DeviceName '\\.\DISPLAY2' `
    -Kind Representative
```

The script enumerates modes reported by Windows and selects representative supported resolutions. It does not blindly force a hard-coded unsupported mode.

Refresh-rate-only testing at the current resolution is available with:

```powershell
.\powershell\Invoke-ModeExercise.ps1 `
    -DeviceName '\\.\DISPLAY2' `
    -Kind Refresh
```

The main campaign only runs refresh-rate testing when `-IncludeRefreshModes` is supplied.

### Explicit display mode

```powershell
.\powershell\Set-DisplayMode.ps1 `
    -DeviceName '\\.\DISPLAY2' `
    -Width 1024 `
    -Height 768 `
    -FrequencyHz 60
```

The helper performs a Windows `CDS_TEST` before applying the requested mode.

### Change Windows primary display

```powershell
.\powershell\Set-PrimaryDisplay.ps1 -DeviceName '\\.\DISPLAY2'
```

### Change Windows topology

```powershell
.\powershell\Set-DisplayTopology.ps1 -Mode Extend
```

Supported values:

```text
Extend
Duplicate
InternalOnly
ExternalOnly
```

The primary/secondary research campaign itself uses `Extend`.

## Customizing the campaign

Most visual cases are defined in:

```text
config/test-cases.json
```

Durations and test entries can be changed without modifying the orchestration logic.

The main runner also supports selective skips:

```powershell
.\powershell\Invoke-DisplayExercise.ps1 `
    -Role Both `
    -SkipModes `
    -SkipCursor `
    -SkipIdle
```

Available skip switches include:

- `-SkipModes`
- `-SkipPatterns`
- `-SkipRegions`
- `-SkipCursor`
- `-SkipIdle`
- `-SkipMotion`

Timing can be adjusted with parameters such as:

- `-PreActionSeconds`
- `-PostActionSeconds`
- `-RegionStepSeconds`
- `-CursorStepSeconds`
- `-ModeStepSeconds`

## Result artifacts

A normal session produces data similar to:

```text
artifacts/display-YYYYMMDD-HHMMSS/
  events.jsonl
  snapshot-initial.json
  snapshot-sec-role.json
  snapshot-pri-role.json
  snapshot-final.json
```

Physical tests add their own before/after snapshots.

`events.jsonl` records UTC and local timestamps, test IDs, state transitions, exact region coordinates, requested display modes, cursor coordinates, operator confirmations, and failures. It is intended to be correlated with timestamps in independently captured USB PCAP files.

## Restoration behavior

`Invoke-DisplayExercise.ps1` records the initial target mode and initial Windows primary display. At the end of the campaign it attempts to restore both.

The campaign normalizes the active topology to **Extend** because primary-versus-secondary testing requires an extended desktop. It does not currently attempt to reconstruct an arbitrary pre-test Duplicate/InternalOnly/ExternalOnly topology.

If a driver crash, USB removal, Windows display reset, or unexpected hardware failure prevents automatic restoration, use Windows Display Settings or the helper scripts to restore the desired layout.

## Design principles

The harness follows four rules important for protocol reverse engineering:

1. **Change one major variable at a time.**
2. **Use deterministic content whenever possible.**
3. **Timestamp every transition so PCAP traffic can be correlated later.**
4. **Keep packet capture independent from display stimulation.**

The scripts do not assume that Trigger 1+ uses the same packet format or compression scheme as later MCT Trigger generations. Their purpose is to generate controlled evidence from which the Trigger 1+ protocol can be inferred.
