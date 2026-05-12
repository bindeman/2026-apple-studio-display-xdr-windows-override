# Apple Studio Display XDR on Windows

This repo documents and packages a Windows workaround for the 2026 Apple Studio Display XDR when Windows only exposes fallback modes such as `1920 x 1080`.

Validated locally:

- `5120 x 2880`
- `120 Hz`
- HDR / Advanced Color enabled through the Windows DisplayConfig API
- 10 bits per color channel after HDR enable
- Studio Display XDR USB devices detected: camera, speakers, microphone, HID brightness interface

## Why This Is Needed

On some Windows PCs, the Studio Display XDR connects successfully over Thunderbolt/USB4, but Windows reads a fallback monitor EDID:

```text
DISPLAY\MS_0001
640 x 480
1920 x 1080 @ 60 Hz
```

The display itself is capable of 5K/120/HDR. Linux reports confirm the display exposes the panel as a tiled MST display, `2x 2560x2880`, and compositors such as Hyprland merge it into one `5120x2880` display.

This project installs a complete Studio Display XDR EDID override so Windows can expose the native mode.

## Tested Setup

Primary tested Windows setup:

- Alienware Area-51 desktop
- NVIDIA GeForce RTX 5090
- Intel Thunderbolt/USB4 display path
- Apple Studio Display XDR, USB product ID `05AC:1116`
- Windows 11

Known-good Linux report:

- HP ZBook Ultra G1a
- AMD Ryzen AI MAX+ PRO 395 / Radeon 8060S
- NixOS, kernel 6.19.9
- Hyprland
- `5120x2880 @ 120 Hz`, HDR metadata, and sleep/wake working

## Quick Start

Disconnect other Apple external displays for the first install. This avoids accidentally applying the override to the wrong monitor.

Open an elevated PowerShell in this repo folder and run:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\Install-StudioXdrEdidOverride.ps1
```

Reboot Windows.

Then open:

```text
Settings > System > Display
```

Set:

```text
Display resolution: 5120 x 2880
Refresh rate:       120 Hz
```

If Windows Settings does not show HDR, run:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\Enable-StudioXdrHdr.ps1
```

Expected output after HDR is enabled:

```text
Display=Studio XDR
SetError=0
Supported=True
Enabled=True
BitsPerChannel=10
```

To turn HDR / Advanced Color back off:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\Disable-StudioXdrHdr.ps1
```

## Simple Launchers

These launchers are included for convenience:

```text
Install-StudioXdr.cmd
Enable-HDR.cmd
Disable-HDR.cmd
Uninstall-Override.cmd
```

`Install-StudioXdr.cmd` still needs to be run as administrator because Windows monitor EDID overrides live under `HKLM\SYSTEM`.

## Verify

Run:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\Get-StudioXdrStatus.ps1
```

Known-good active mode:

```text
Intel(R) Graphics
5120 x 2880
120 Hz
```

The HDR script verifies the Advanced Color state through the Windows DisplayConfig API.

## What The Installer Does

The installer:

1. Finds the active monitor node, usually `DISPLAY\MS_0001`.
2. Backs up current monitor EDIDs into `backups/`.
3. Writes `EDID_OVERRIDE` blocks from `edid/studio-display-xdr-ae42.bin`.
4. Leaves the original monitor EDID untouched.

The EDID identifies as:

```text
Manufacturer: Apple
Product:      AE42
Name:         Studio XDR
```

No Boot Camp driver is required for the native display mode.

## HDR Notes

After the EDID override, Windows may know HDR is supported but still hide or fail to expose the Settings toggle.

Locally, the Windows DisplayConfig API reported:

```text
Before: AdvancedColorRaw=5, Enabled=False, BitsPerChannel=8
After:  AdvancedColorRaw=7, Enabled=True,  BitsPerChannel=10
```

That is what `scripts\Enable-StudioXdrHdr.ps1` does.

## Color Profile Notes

The EDID override includes the display's wide-color and HDR metadata. Windows can then expose the display as a wide-color/HDR target and output a 10-bpc signal path when Advanced Color is enabled.

This does not install Apple's macOS reference presets. Apple reference modes such as `Apple XDR Display (P3-2000 nits)` and `Apple XDR Display (P3 + Adobe RGB-2000 nits)` are part of Apple's display preset system on macOS. On Windows, this repo currently provides the display mode and HDR transport path, not Apple's full preset UI.

Practical current state:

- The display hardware supports P3 and Adobe RGB wide gamut.
- The imported EDID advertises BT.2020 / HDR static metadata.
- Windows HDR / Advanced Color can be enabled and reports 10 bits per channel.
- Color-managed apps can use Windows color management, but this repo does not yet install an Apple-authored Studio Display XDR ICC/ICM profile.

For color-critical work, use a hardware calibrator and create a Windows ICC profile for your specific display. A future version of this repo may add optional ICC profile install/association once a redistributable Apple profile or reliable generated profile is available.

Related Apple documentation:

- [Studio Display XDR tech specs](https://support.apple.com/en-us/126323) list Apple XDR Display reference modes and wide-color support.
- [Apple display preset documentation](https://support.apple.com/en-ca/108321) describes XDR presets including P3 and P3 + Adobe RGB modes.

More detail: [docs/color-management.md](docs/color-management.md).

## Pixelated Tile / Link Artifacts

If part of the screen appears pixelated after switching to 5K/120, especially a fixed section on the right side, it is likely a transient tile/link/DSC state.

Known local fix:

1. Change refresh rate from `120 Hz` to `60 Hz`.
2. Apply.
3. Change back to `120 Hz`, `120.04 Hz`, or Dynamic Refresh Rate.

This forces Windows, the GPU driver, and the Thunderbolt/DisplayPort link to retrain the display timing. If `120.04 Hz` is stable on your system, it is fine to use; it is just a slightly different timing entry, not inherently better than exact `120 Hz`.

## Brightness

Brightness is separate from the display mode issue.

Apple displays do not use normal DDC/CI brightness. Studio Display XDR exposes brightness through Apple USB HID:

```text
VID_05AC&PID_1116
Usage Page: 0x0082
Usage:      0x0010
```

The local prototype confirmed the Windows HID brightness feature is visible. Brightness tooling can be added after the 5K/120/HDR path is stable.

## Screenshots

Add screenshots under `docs/screenshots/`.

Recommended screenshot list:

- Before: Windows only exposes `1920 x 1080`
- Installer output
- Resolution list showing `5120 x 2880`
- Advanced display showing `120 Hz`
- HDR/Advanced Color enabled output
- Device Manager or PowerShell showing Studio Display XDR USB4/USB devices

See [docs/screenshots.md](docs/screenshots.md).

## Recovery

To remove the override, open an elevated PowerShell and run:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\Uninstall-StudioXdrEdidOverride.ps1
```

Then reboot.

More recovery notes are in [docs/recovery.md](docs/recovery.md).

## CRU Fallback

This repo no longer requires Custom Resolution Utility for the primary path.

CRU remains useful for inspection and manual fallback:

1. Select the active `Generic` / `MS_0001` display.
2. Import `edid/studio-display-xdr-ae42.bin`.
3. Choose `Import complete EDID`.
4. Restart the graphics driver or reboot.

## Packaging

The GitHub Actions workflow builds a release ZIP containing:

```text
README.md
LICENSE
Install-StudioXdr.cmd
Enable-HDR.cmd
Uninstall-Override.cmd
scripts/
edid/
docs/
```

Future work:

- Wrap the PowerShell scripts as a signed EXE.
- Add a small GUI that detects the active Studio Display XDR and applies the override.
- Add brightness control for `VID_05AC&PID_1116`.

## Disclaimer

This project modifies Windows monitor EDID override registry keys. It does not flash the display and does not modify GPU drivers, but a bad monitor override can temporarily produce an unusable display mode. Keep another display or Safe Mode recovery path available.

Apple is a trademark of Apple Inc. This project is unofficial and is not affiliated with or endorsed by Apple.
