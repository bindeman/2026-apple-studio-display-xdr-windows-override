# Release Checklist

Use this checklist before tagging a public release.

## Build Gate

Run from the repo root:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\Test-StudioDisplayXdrRelease.ps1
```

Required result:

```text
Studio Display XDR release gate passed.
```

The release gate runs build, ZIP verification for both package flavors, extracted-package smoke for both flavors, app runtime smoke, and app UI smoke in sequence. Do not run the app runtime and app UI smoke tests in parallel because both intentionally stop/start `StudioDisplayXdr`.

The build produces two ZIPs:

```text
dist\studio-display-xdr-windows.zip          full package (control panel GUI + setup launcher + scripts)
dist\studio-display-xdr-windows-scripts.zip  scripts-only package (no GUI, no .NET payload)
```

The scripts-only verifier also asserts that `StudioDisplayXdr.App/`, `StudioDisplayXdrSetup.exe`, `assets/`, and `tools/` are absent, and that `PACKAGE.json` carries `flavor = scripts` with empty `appPath` / `setupPath`.

GitHub Actions runs the same release gate with `-SkipInteractiveApp` because hosted runners do not have the connected display or interactive desktop needed for app UI validation. It runs on pull requests and pushes to `main` as a build check, and on `v*` tags it also creates the GitHub Release with both ZIPs attached.

## Versioning

Bump the repo-root `VERSION` file first. The build stamps that value into each ZIP's `PACKAGE.json` (`version`) and the control panel's About row shows it. The tag must match, for example `VERSION` = `0.1.0` and tag `v0.1.0`; the workflow fails the release if they differ.

```powershell
git tag v0.1.0
git push origin v0.1.0
```

## Extracted Package Smoke Test

Run the automated extracted-package smoke test for each flavor:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\Test-StudioDisplayXdrExtractedPackage.ps1 -Flavor Full
powershell -ExecutionPolicy Bypass -File .\scripts\Test-StudioDisplayXdrExtractedPackage.ps1 -ZipPath .\dist\studio-display-xdr-windows-scripts.zip -Flavor Scripts
```

It extracts the generated ZIP into a temporary folder, runs the support report from inside that extracted package, and confirms the report lists root package artifacts such as (full package):

```text
StudioDisplayXdrSetup.exe
StudioDisplayXdr.App\StudioDisplayXdr.exe
assets\StudioDisplayXdr.ico
tools\LibUsbDotNet.LibUsbDotNet.net45.dll
PACKAGE.json
```

It also confirms the support report includes app configuration fields such as settings path, Open at login state, and stable install root state.

It also checks that the guided installer stages a stable app copy under `%LOCALAPPDATA%\StudioDisplayXdr\Support`, that shortcuts can target the staged app instead of the extracted ZIP location, and that the guided uninstaller can remove that staged copy.
Release launchers are expected to prefer that stable app copy from non-git packages while preserving local-build behavior in development checkouts.

## Hardware Gate

With the Studio Display XDR connected over the known-good Thunderbolt/USB4 path, run:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\Get-StudioXdrStatus.ps1
powershell -ExecutionPolicy Bypass -File .\scripts\Test-StudioXdrReadiness.ps1
powershell -ExecutionPolicy Bypass -File .\scripts\Get-StudioXdrColorStatus.ps1
powershell -ExecutionPolicy Bypass -File .\scripts\Find-StudioXdrColorProfiles.ps1
powershell -ExecutionPolicy Bypass -File .\scripts\Set-StudioXdrDisplayMode.ps1 -RefreshRate 120 -TestOnly
powershell -ExecutionPolicy Bypass -File .\scripts\StudioXdrBrightness.ps1 -ListOnly
powershell -ExecutionPolicy Bypass -File .\scripts\Test-StudioXdrAmbientPreflight.ps1
powershell -ExecutionPolicy Bypass -File .\scripts\Test-StudioXdrAmbientDriverTarget.ps1
powershell -ExecutionPolicy Bypass -File .\scripts\Get-StudioXdrAmbientStatus.ps1
powershell -ExecutionPolicy Bypass -File .\scripts\Get-AppleDisplaySensorCorrelation.ps1
```

Required current result:

- Active Studio XDR DisplayConfig target is detected.
- `5120x2880` is active or available.
- `5120x2880 @ 120 Hz` test succeeds.
- Brightness HID endpoint is detected.
- Color-profile discovery reports the bundled generated profile and any Apple/Pro Display candidates found locally.
- Camera, speakers, and microphone enumerate as standard Windows devices.
- Windows light-sensor enumeration reports candidate count and selected sensor, if any.
- `MI_08` status is documented, even if still `HidUsb` / Code 10.
- The packaged WinUSB INF includes both `USB\VID_05AC&PID_1116&REV_1801&MI_08` and `USB\VID_05AC&PID_1116&MI_08`.
- Ambient driver target dry-run reports whether the package matches the connected `MI_08` and whether Windows is actually bound to it.
- Apple display sensor correlation reports whether Pro Display XDR, older Studio Display, or Studio Display XDR expose Windows Sensor-class / WinRT `LightSensor` candidates.
- HID collection dump distinguishes brightness HID, `MI_08`, and non-ambient `MI_09` orientation sensor state.
- Ambient preflight prints a clear verdict and next steps for native sensor vs camera fallback.
- Ambient driver target check prints the PnP matching-driver view, including whether Windows only sees `input.inf` or also sees a WinUSB/libwdi package for the exact `MI_08` interface.
- Ambient connector installer prints before/after target checks and clearly warns when the experimental WinUSB INF is unsigned or lacks a signed catalog.
- Ambient driver package preparation detects WDK `inf2cat.exe` / `signtool.exe`, can generate/test-sign `StudioXdrAmbientWinUsb.cat`, and is packaged as `Prepare-Ambient-Driver.cmd`.

## App Gate

Open:

```text
Studio-Display-XDR.cmd
```

Confirm:

- Brightness slider reads the current display value.
- Control panel and setup launcher show the bundled Studio Display XDR icon.
- Moving the slider changes Studio Display XDR brightness.
- Signal card shows the active resolution and refresh.
- HDR toggle reflects Windows Advanced Color state.
- Color profile row detects the bundled generated Display P3 profile.
- Color profile `Check` button reports whether Apple/Pro Display/wide-color profile candidates are present.
- Automatic brightness row shows the best available source.
- Automatic brightness `Check` button runs preflight and reports the current native-sensor vs camera-fallback verdict plus WinUSB package/binding and ambient catalog/signing state from structured JSON.
- Minimum, Maximum, and Response sliders persist after app restart.
- Diagnostics `Check` runs the readiness check and summarizes pass/warn/fail counts in the app.
- `Test-StudioDisplayXdrAppUi.ps1` passes for Color, Ambient, Diagnostics `Check`, and Diagnostics `Report` buttons.
- Diagnostics generates a support report under `reports/`.
- Open at login writes/removes the per-user startup entry and starts the app in the notification area with Show/Refresh/Exit tray actions.
- Launching the app while a hidden tray instance is already running opens the existing control panel instead of creating a second process.
- About row shows package build/runtime/source metadata and can copy it for support.
- Generated support report includes app settings, automatic-brightness tuning values, Open at login state, stable install state, and running process state.
- `Check-Status.cmd` prints a pass/warn/info summary and next steps before pausing.
- `Check-Ambient.cmd` prints the automatic-brightness preflight verdict before pausing.
- `Check-Gaming.cmd` prints the active signal, 5K120 test, GPU driver, Windows graphics toggles, and frame-cap recommendation before pausing.
- `Check-Color.cmd` prints HDR/color target status and color-profile discovery before pausing.
- Guided install offers to stage app files under `%LOCALAPPDATA%\StudioDisplayXdr\Support`, then Start Menu/Desktop shortcuts target that stable app copy.
- From a non-git release package, `Studio-Display-XDR.cmd`, `Apple-Brightness-Tray.cmd`, and setup Open Control Panel prefer the stable app copy when it exists.
- Guided install creates Start Menu shortcuts for the control panel, support report, readiness check, ambient preflight, and color/profile check.

## Documentation Gate

Confirm these files are current:

- `README.md`
- `RELEASE_NOTES.md`
- `CONTINUE.md`
- `docs/support-matrix.md`
- `docs/parity-audit.md`
- `docs/auto-brightness.md`
- `docs/color-management.md`
- `docs/hid-research.md`
- `docs/recovery.md`
- `docs/screenshots/control-panel.png`
- `docs/screenshots/control-panel-about.png`
- `docs/screenshots/setup-launcher.png`

## Release Gate

Do not tag a release if:

- The ZIP verifier fails.
- The extracted-package smoke test cannot run support reports.
- The display mode/HDR claims in the README exceed what was actually verified.
- The ambient-sensor docs imply native `MI_08` support is working before the packet probe returns real data.
- Research folders such as `tools\SDBC`, `tools\asdcontrol`, `tools\studi`, `tools\BetterDisplay`, `downloads`, `backups`, or `.git` appear inside the ZIP.
