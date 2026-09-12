# First-Party Parity Audit

This is a prompt-to-artifact checklist for the current goal: make the 2026 Apple Studio Display XDR feel as close as possible to first-party hardware on Windows without overstating gaps that still need native Apple or driver support.

## Deliverable Checklist

| Goal | Current status | Evidence | Remaining gap |
| --- | --- | --- | --- |
| Native `5120x2880` mode | Working locally | EDID override, `Get-StudioXdrStatus.ps1`, `Test-StudioXdrReadiness.ps1` | Requires install/reboot on a new machine. |
| `120 Hz` support | Working locally | `Set-StudioXdrDisplayMode.ps1 -RefreshRate 120 -TestOnly`, control panel 120 Hz button | Active local state may be 60 Hz if user switches it back. |
| HDR / Advanced Color | Working locally | `Enable-HDR.cmd`, `Disable-HDR.cmd`, control panel HDR toggle, `Get-StudioXdrColorStatus.ps1` | Windows Advanced Color only; not Apple reference-mode parity. |
| Brightness slider | Working locally | WPF control panel, `StudioXdrBrightness.ps1`, Apple HID core | Studio Display XDR only in the main app; Pro Display XDR intentionally deferred. |
| Windows ALS reuse | Working diagnostic, no local candidate | `WindowsLightSensorTools.ps1`, app source priority, `Check-Ambient.cmd` | Current local WinRT `LightSensor` candidate count is 0. A Pro Display XDR / older Studio Display can still be reused if Windows exposes it as a `LightSensor`. |
| Apple display sensor correlation | Working diagnostic | `Get-AppleDisplaySensorCorrelation.ps1`, support report `Apple Display Sensor Correlation` section | Current local result maps only Studio Display XDR, with one `MI_09` orientation sensor and no WinRT `LightSensor` candidates. |
| Automatic brightness | Partial | control panel toggle, `Check-Ambient.cmd`, `Test-StudioXdrAmbientPreflight.ps1`, camera fallback | Native `MI_08` sensor path is not returning packets yet on the tested machine. |
| Native Studio Display XDR ambient sensor | Experimental | `drivers/StudioXdrAmbientWinUsb.inf`, `Prepare-Ambient-Driver.cmd`, `Test-StudioXdrAmbientDriverTarget.ps1`, `Install-LibUsb-Ambient-Filter.cmd`, WinUSB/libusb probes | `MI_08` still binds to `HidUsb` / `input.inf` / Code 10 locally; exact filter target is `USB\VID_05AC&PID_1116&REV_1801&MI_08`. The WinUSB INF follows Microsoft's include/needs pattern and has a local test-signing helper, but no public signed catalog is bundled. |
| Ambient driver target | Working diagnostic | `Test-StudioXdrAmbientDriverTarget.ps1`, support report `Ambient Driver Target` section | Current dry-run status is `ReadyToInstall`: package matches the exact target, but no matching OEM INF is installed or bound. |
| HID collection map | Working diagnostic | `Dump-StudioXdrHidCollections.ps1`, `docs/hid-research.md`, support report HID section | Confirms `MI_07` collection 1 is brightness, `MI_08` is the failing native-sensor experiment, and `MI_09` is orientation, not ambient light. |
| Camera fallback auto-brightness | Working locally as proxy | `CameraAmbientSensor.cs`, automatic brightness loop, preflight reports camera fallback ready | Not calibrated lux, uses camera exposure, and can trigger camera privacy UI. |
| Color profile | Partial | `profiles/StudioDisplayXDR-DisplayP3.icm`, control panel install row, `Install-Color-Profile.cmd`, `Check-Color.cmd` | Generated Display P3 baseline only; no Apple-authored reference profile found locally yet. |
| P3 / Adobe RGB claims | Documented conservatively | `docs/color-management.md`, `docs/support-matrix.md` | Needs measured calibration to make stronger claims. |
| Webcam, microphone, speakers | Working locally | `Get-StudioXdrStatus.ps1`, support report camera/audio section | No custom package action needed. |
| Gaming / tearing diagnostics | Working diagnostic | `Check-Gaming.cmd`, `Get-StudioXdrGamingStatus.ps1`, `docs/gaming-tearing.md`, support report `Gaming And Tearing Diagnostic` section | Cannot force game swapchain, VRR, driver, or panel scheduling from this package alone. |
| DP-to-USB-C adapter path | Documented limitation | README and display adapter notes | No software override is possible if Windows never enumerates a display target. |
| Installer / app packaging | Working locally | `StudioDisplayXdrSetup.exe`, stable `%LOCALAPPDATA%\StudioDisplayXdr\Support` staging, Start Menu shortcuts, stable-app launcher preference | Package is unsigned. |
| Release ZIP | Working locally | `Build-StudioDisplayXdrPackage.ps1`, `Test-StudioDisplayXdrPackage.ps1`, `Test-StudioDisplayXdrExtractedPackage.ps1`, `Test-StudioDisplayXdrRelease.ps1` | Needs a tagged GitHub release when ready. |
| Support workflow | Working locally | support report, readiness check, ambient preflight, ambient target dry-run, GitHub issue templates | Public issue triage will validate more hardware combinations. |
| App smoke coverage | Working locally | `Test-StudioDisplayXdrAppRuntime.ps1`, `Test-StudioDisplayXdrAppUi.ps1` | UI automation depends on an interactive desktop and is skipped in hosted CI. |

## Claims That Are Safe To Make

- The package can expose native Studio Display XDR `5120x2880` modes on the tested Windows setup.
- Windows accepts a `5120x2880 @ 120 Hz` test mode locally.
- Windows Advanced Color / HDR can be toggled through DisplayConfig locally.
- Studio Display XDR brightness control works through Apple USB HID when the USB/Thunderbolt path is present.
- Camera, microphone, and speakers enumerate as standard Windows devices on the tested machine.
- Automatic brightness has a practical camera fallback and a native-sensor research path.
- The package can tell whether the connected `MI_08` target matches the bundled WinUSB INF before any driver change is attempted.
- The package can distinguish the working brightness HID collection from non-ambient `MI_09` orientation HID state.

## Claims To Avoid

- Do not claim full Apple/macOS reference-mode parity.
- Do not claim native Studio Display XDR ambient-light sensor support until `MI_08` returns real packets.
- Do not claim `MI_09` is a useful ambient-light path; it maps as device orientation on the tested machine.
- Do not claim an Apple-authored color profile is bundled.
- Do not claim DisplayPort-to-USB-C adapters can be fixed in software when Windows shows a black screen and no display target.
- Do not claim Pro Display XDR support in the main app; use it only as research context for this repo.

## Verification Commands

Run these before a public release:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\Build-StudioDisplayXdrPackage.ps1
powershell -ExecutionPolicy Bypass -File .\scripts\Test-StudioDisplayXdrPackage.ps1
powershell -ExecutionPolicy Bypass -File .\scripts\Test-StudioDisplayXdrExtractedPackage.ps1
powershell -ExecutionPolicy Bypass -File .\scripts\Test-StudioDisplayXdrRelease.ps1
powershell -ExecutionPolicy Bypass -File .\scripts\Test-StudioXdrReadiness.ps1
powershell -ExecutionPolicy Bypass -File .\scripts\Test-StudioXdrAmbientPreflight.ps1
powershell -ExecutionPolicy Bypass -File .\scripts\Test-StudioXdrAmbientDriverTarget.ps1
powershell -ExecutionPolicy Bypass -File .\scripts\Get-AppleDisplaySensorCorrelation.ps1
powershell -ExecutionPolicy Bypass -File .\scripts\Find-StudioXdrColorProfiles.ps1
```

The package is not first-party complete until every row above is either working or explicitly documented as a limitation.
