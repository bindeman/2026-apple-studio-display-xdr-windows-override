# Release Notes

## v0.1.0

First tagged release. Two downloads:

- `studio-display-xdr-windows.zip`: full package with the self-contained control panel GUI and `StudioDisplayXdrSetup.exe`.
- `studio-display-xdr-windows-scripts.zip`: scripts-only package (no GUI, no .NET payload) with the same PowerShell scripts, `.cmd` launchers, EDID override, generated Display P3 profile, and docs. `Studio-Display-XDR.cmd` opens the PowerShell brightness tray instead of the control panel.

### Fixed

- `Install-StudioXdrEdidOverride.ps1` no longer ends with `Select-Object : Property "PSObject" cannot be found` under Windows PowerShell 5.1 (GitHub issue #3). The stale-block cleanup now uses the registry key's value names and is non-fatal. The installer also prints the registry key it changed and a clear reboot notice; in earlier packages the override had already been written when the error appeared, so a reboot still enabled 5K.
- The guided installer no longer aborts on machines without the `dotnet` CLI when the compiled control panel is absent.
- Support reports no longer fail the `OS And .NET` section on machines without the `dotnet` CLI, and now record the PowerShell version.

### Added

- `Uninstall-StudioXdrEdidOverride.ps1 -All` removes every EDID override this project created even when the Studio Display XDR is not the active monitor (Safe Mode / black-screen recovery). `-All -Force` also removes overrides written by other tools such as CRU.
- `docs/recovery.md` documents Safe Mode and WinRE offline-registry recovery for a black screen after the override, including the Mac Pro 2019 Boot Camp / Radeon Pro W6900X report.
- Repo-root `VERSION` file. The build stamps `version` and `flavor` into each ZIP's `PACKAGE.json`, and the control panel About row shows the package version.
- The GitHub Actions workflow builds and verifies both packages on pull requests and pushes to `main`, refuses a release tag that does not match `VERSION`, and attaches both ZIPs to the GitHub Release.
- Scripts-only package support in the guided installer: shortcuts and the final launch fall back to `Studio-Display-XDR.cmd` / the PowerShell brightness tray when the compiled control panel is absent.

## Current Package

This package is the first postable Windows support bundle for the 2026 Apple Studio Display XDR.

## Included

- Self-contained `win-x64` Studio Display XDR control panel.
- Root-level `StudioDisplayXdrSetup.exe` launcher for install/repair, uninstall, control panel, readiness check, ambient preflight, color/profile check, support report, and README actions.
- Polished setup launcher action grid with readable first-run tasks instead of stock utility buttons.
- Bundled Studio Display XDR icon applied to the setup launcher, control panel window, and packaged assets.
- One brightness slider per detected Studio Display XDR.
- One-click display optimization for `5120 x 2880 @ 120 Hz` plus HDR / Advanced Color.
- Manual 60 Hz / 120 Hz switching.
- Manual HDR / Advanced Color toggle.
- Generated Display P3 baseline profile and installer.
- In-app color/profile `Check` action for local Apple, Pro Display, P3, Adobe, and HDR ICC/ICM candidates.
- Guided installer and guided uninstaller.
- Guided installer can stage app files under `%LOCALAPPDATA%\StudioDisplayXdr\Support` so installed shortcuts keep working after the extracted ZIP is moved or deleted.
- Guided uninstaller can remove that staged app copy.
- Root release launchers and the setup launcher's Open Control Panel action prefer the stable installed app copy when it exists, while development checkouts keep opening the local build.
- Guided installer can test and optionally apply `5120 x 2880 @ 120 Hz`.
- Guided installer shows ambient-sensor status and can optionally launch the advanced MI_08 WinUSB/libusb experiments.
- Experimental WinUSB ambient INF targets the exact observed `USB\VID_05AC&PID_1116&REV_1801&MI_08` interface before the generic `MI_08` hardware ID.
- Ambient WinUSB INF now declares `CatalogFile = StudioXdrAmbientWinUsb.cat` and follows Microsoft's documented WinUSB include/needs pattern.
- `Prepare-Ambient-Driver.cmd` / `scripts\New-StudioXdrAmbientDriverPackage.ps1` checks for WDK `inf2cat.exe` and `signtool.exe`, generates the ambient WinUSB catalog, and can test-sign it with a local code-signing certificate.
- Support reports include an Ambient Driver Package Signing section so GitHub issues can show whether WDK signing tools, a catalog, and a local test certificate are present.
- Guided uninstaller can optionally remove the experimental libusb-win32 MI_08 filter.
- EDID override installer for native 5K modes.
- Generated `PACKAGE.json` build metadata for support reports.
- Brightness diagnostics over Apple USB HID.
- Read-only Apple display USB topology diagnostics for Studio Display XDR, older Studio Display, and Pro Display XDR comparison.
- Read-only Apple display sensor correlation for comparing Apple display USB containers with Windows Sensor-class devices and WinRT `LightSensor` candidates.
- Read-only Studio Display XDR HID collection dump and HID research notes so brightness, orientation, and ambient-sensor candidates are not confused.
- Support report generator for GitHub issues.
- Support reports include app settings, automatic-brightness tuning values, Open at login state, stable install state, and running control-panel process state.
- Concise readiness check through `Check-Status.cmd`, including a pass/warn/info summary and next steps.
- Focused gaming/tearing diagnostic through `Check-Gaming.cmd`, including active signal, HDR state, 5K120 mode test, GPU driver details, Windows graphics toggles, and a frame-cap recommendation.
- In-app diagnostics `Check` action that runs the readiness check and summarizes pass/warn/fail counts without opening a console window.
- Focused automatic-brightness preflight through `Check-Ambient.cmd`, including Windows ALS, native `MI_08`, libusb filter, packet probe, and camera fallback verdicts.
- Read-only ambient driver target check that validates the connected `MI_08` hardware ID against the packaged WinUSB INF and current driver-store/binding state.
- Read-only color-profile discovery through `Check-Color.cmd` / `Find-StudioXdrColorProfiles.ps1` for bundled, Windows, Apple, Boot Camp, and Pro Display candidate ICC/ICM files.
- Support report generation from the Studio Display XDR control panel.
- GitHub issue templates for normal support issues and ambient-sensor experiments.
- First-party parity audit that maps working, partial, experimental, and unsupported areas to concrete package artifacts.
- Experimental automatic brightness paths:
  - Windows ambient-light sensor if one exists, with Apple/display-looking sensors preferred.
  - Studio Display XDR `MI_08` WinUSB connector if it can be bound and read.
  - Studio Display XDR `MI_08` SDBC-style libusb reader if an exact filter exposes endpoint `0x89`.
  - Opt-in Studio Display Camera fallback.
- Console readiness and ambient checks use the same Windows light-sensor enumeration strategy as the app instead of relying only on `LightSensor.GetDefault()`.
- Persistent auto-brightness minimum, maximum, and response controls for practical camera fallback tuning.
- In-app automatic-brightness `Check` action that runs the same preflight through structured JSON and shows the current native-sensor vs camera-fallback verdict plus WinUSB package/binding state.
- The same in-app automatic-brightness `Check` action also summarizes ambient WinUSB catalog/signing readiness, including the missing-WDK-tools state.
- Persistent auto-brightness opt-in, so Open at login can resume automatic brightness after Windows starts.
- Open at login starts the app quietly in the Windows notification area, with tray actions for opening the control panel, refreshing displays, or exiting.
- Single-instance app startup: launching the app again opens the existing control panel instead of creating duplicate tray icons.
- Local app UI smoke test for Color, Ambient, Diagnostics `Check`, and Diagnostics `Report` buttons.
- Sequenced release gate script for build, package verification, extracted smoke, app runtime smoke, and app UI smoke.
- In-app About/build metadata row sourced from `PACKAGE.json`, with a copy action for support issues.

## Current Verified Local State

- Studio Display XDR active at `5120 x 2880`.
- `120 Hz` mode is available and has tested successfully.
- HDR / Advanced Color can be toggled through the Windows DisplayConfig API.
- Brightness control works through Apple USB HID.
- Camera, microphone, and speakers enumerate as standard Windows devices.

## Known Limitations

- The package is unsigned.
- The public ZIP does not include a signed ambient WinUSB catalog. Native `MI_08` WinUSB binding still needs a local test-signed catalog, a proper release signature, or a libwdi/Zadig package for the exact interface.
- The generated Display P3 profile is not an Apple-authored reference-mode profile.
- Windows does not currently expose the Studio Display XDR as a normal ambient-light sensor on the tested machine.
- The `MI_08` ambient connector is experimental and currently depends on getting the exact interface bound to WinUSB or exposed through a libusb-win32-compatible filter.
- Camera fallback automatic brightness is practical, but not calibrated like a true ambient-light sensor.
- HDR support is Windows Advanced Color support, not full macOS reference-mode parity.
- Apple documents P3-limited color behavior for non-macOS hosts even when BT.2020 capability is reported; this package intentionally avoids claiming Apple reference-mode parity.

## Verify A Build

Run:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\Build-StudioDisplayXdrPackage.ps1
powershell -ExecutionPolicy Bypass -File .\scripts\Test-StudioDisplayXdrPackage.ps1
powershell -ExecutionPolicy Bypass -File .\scripts\Test-StudioDisplayXdrRelease.ps1
```
