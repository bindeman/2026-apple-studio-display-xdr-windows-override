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
Apple-Brightness-Tray.cmd
Brightness-Up.cmd
Brightness-Down.cmd
Brightness-Status.cmd
```

`Apple-Brightness-Tray.cmd` starts a small tray app with display selection and brightness controls. It supports both:

```text
Studio Display XDR: PID_1116
Pro Display XDR:    PID_9243
```

The tray app attempts to register global `F1` and `F2` hotkeys:

```text
F1: brightness down 5%
F2: brightness up 5%
```

This is best-effort. Some keyboards, firmware layers, or apps may reserve these keys. If registration fails, the tray app disables the hotkey checkbox and the tray menu controls remain available.

The other launchers are simple one-shot wrappers around the PowerShell script.

## Notes

The HID descriptor reports logical min/max as `0..0`, so the script uses an Apple-style raw fallback range of `0..100000`. This matches observed behavior:

```text
60000 ~= 60%
55000 ~= 55%
```

No administrator privileges are required for brightness control when Windows exposes the HID interface normally.

## Future Work

- Add global hotkeys for brightness up/down.
- Add a signed EXE wrapper for the tray app.
- Support multiple Apple displays and route brightness to the focused monitor.
- Investigate reference mode / preset control over Apple HID.
