# Brightness Control

Studio Display XDR brightness does not use normal DDC/CI. Windows tools that only speak DDC/CI will usually fail.

The display exposes brightness through Apple USB HID:

```text
USB vendor:  05AC
USB product: 1116
HID usage page: 0x0082  VESA Virtual Controls
HID usage:      0x0010  Brightness
```

The working local HID collection is:

```text
HID\VID_05AC&PID_1116&MI_07&COL01...
```

## Read Brightness

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\StudioXdrBrightness.ps1 -ListOnly
```

Example:

```text
UsagePage=0x0082 Usage=0x0010 ReportId=0x01 Range=0..100000 Current=60000 (~60%)
```

## Set Brightness

Set an approximate percentage:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\StudioXdrBrightness.ps1 -SetPercent 60
```

Set a raw value:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\StudioXdrBrightness.ps1 -SetRaw 60000
```

Step brightness:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\StudioXdrBrightness.ps1 -StepPercent 5
powershell -ExecutionPolicy Bypass -File .\scripts\StudioXdrBrightness.ps1 -StepPercent -5
```

## Launchers

```text
Brightness-Up.cmd
Brightness-Down.cmd
Brightness-Status.cmd
```

These are simple wrappers around the PowerShell script. They do not currently bind to keyboard brightness keys.

## Notes

The HID descriptor reports logical min/max as `0..0`, so the script uses an Apple-style raw fallback range of `0..100000`. This matches observed behavior:

```text
60000 ~= 60%
55000 ~= 55%
```

No administrator privileges are required for brightness control when Windows exposes the HID interface normally.

## Future Work

- Add a tray app.
- Add global hotkeys for brightness up/down.
- Support multiple Apple displays and route brightness to the focused monitor.
- Investigate reference mode / preset control over Apple HID.
