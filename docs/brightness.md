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
Studio-Display-XDR.cmd
Apple-Brightness-Tray.cmd
Brightness-Up.cmd
Brightness-Down.cmd
Brightness-Status.cmd
```

`Studio-Display-XDR.cmd` opens the native Windows control panel:

```text
StudioDisplayXdr.App\StudioDisplayXdr.exe
```

In a development checkout, the staged build is also available at `dist\StudioDisplayXdr.App\StudioDisplayXdr.exe`.

The control panel is intentionally Studio Display XDR only:

```text
Studio Display XDR: PID_1116
```

`Apple-Brightness-Tray.cmd` is retained as a compatibility launcher. It opens the compiled app when available, otherwise it falls back to the PowerShell WPF control panel.

The control panel also includes an Open at login preference. It writes the normal per-user Windows startup entry and starts the app minimized:

```text
HKCU\Software\Microsoft\Windows\CurrentVersion\Run
Value: StudioDisplayXdr
"...\StudioDisplayXdr.exe" --minimized
```

If automatic brightness is enabled, that opt-in is also remembered and resumes on launch when an ambient source is available.

The control panel also reads the active Studio Display XDR signal through Windows DisplayConfig and shows:

```text
resolution
refresh rate
HDR / Advanced Color state
bits per color channel
```

The 60 Hz, 120 Hz, and HDR controls are manual. The app does not change refresh rate or HDR state on launch.

The other launchers are simple one-shot wrappers around the PowerShell script.

## Notes

The HID descriptor reports logical min/max as `0..0`, so the script uses an Apple-style raw fallback range of `0..100000`. This matches observed behavior:

```text
60000 ~= 60%
55000 ~= 55%
```

No administrator privileges are required for brightness control when Windows exposes the HID interface normally.

The compiled app uses a registry fallback to find the Studio HID path when SetupAPI enumeration does not return the device. The same fallback pattern is used by the PowerShell scripts.

## Automatic Brightness

Automatic brightness is implemented in the compiled app.

Source priority:

```text
Windows ambient-light sensor
Studio Display XDR MI_08 experimental connector
Studio Display Camera fallback
```

The camera fallback is a practical workaround for PID `0x1116`, where Windows currently does not expose a native ambient-light sensor. It is opt-in through the automatic brightness toggle and uses the working Studio Display Camera to estimate room brightness from frame luminance.

Check the connector:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\Get-StudioXdrAmbientStatus.ps1
```

When any ambient source returns readings, the app adjusts brightness through the same working Apple HID brightness path.

More detail: [auto-brightness.md](auto-brightness.md).

## Future Work

- Sign and harden the ambient connector driver flow.
- Add optional keyboard brightness shortcuts.
- Investigate reference mode / preset control over Apple HID.
