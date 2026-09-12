# Support Matrix

This project aims to make Studio Display XDR feel as close as possible to first-party hardware on Windows, while staying clear about what is working, experimental, or not replicated.

## Current State

| Area | Status | Package artifact | Notes |
| --- | --- | --- | --- |
| Native resolution | Working locally | EDID override, guided installer | Windows exposes `5120x2880` after the Studio Display XDR EDID override. |
| 120 Hz | Working locally | `Set-StudioXdrDisplayMode.ps1`, control panel | `5120x2880 @ 120 Hz` test succeeds. `120.04 Hz` may also appear as a timing variant. |
| HDR transport | Working locally | `Enable-HDR.cmd`, control panel | Uses Windows Advanced Color through DisplayConfig. This is not Apple reference-mode parity. |
| Brightness slider | Working locally | `StudioDisplayXdr.exe`, HID scripts | Uses Apple USB HID, not DDC/CI. Works when HDR is off locally; HDR state can affect perceived brightness behavior. |
| Automatic brightness | Partial | control panel, `Check-Ambient.cmd`, ambient scripts | Windows native ALS enumeration, `MI_08` connector, and camera fallback are tried in priority order. Camera fallback works as a practical opt-in proxy. |
| Apple display sensor correlation | Working diagnostic | `Get-AppleDisplaySensorCorrelation.ps1`, support report | Correlates Apple display USB containers with Windows Sensor-class and WinRT `LightSensor` candidates for Pro Display / older Studio Display comparison. |
| Native Studio Display XDR sensor | Experimental | `Prepare-Ambient-Driver.cmd`, `Install-LibUsb-Ambient-Filter.cmd`, `drivers/StudioXdrAmbientWinUsb.inf` | Current local state: `MI_08` is present but remains `HidUsb` / `input.inf` / Code 10. Exact target: `USB\VID_05AC&PID_1116&REV_1801&MI_08`. The bundled INF follows Microsoft's WinUSB include pattern but the public ZIP is unsigned; normal binding still needs signing/test-signing or a libwdi/Zadig package. |
| HID collection map | Working diagnostic | `Dump-StudioXdrHidCollections.ps1`, `docs/hid-research.md` | Confirms the working brightness HID path and documents that `MI_09` is device orientation, not ambient light. |
| Color profile | Partial | generated Display P3 profile, `Check-Color.cmd` | Bundled profile is a generated P3 D65 gamma 2.2 baseline, not an Apple-authored reference-mode profile. Discovery can find Apple/Pro Display candidates if they exist locally. |
| Apple reference modes | Not replicated | docs only | macOS presets combine firmware behavior, luminance targets, EOTF, gamut mapping, and Apple color management. |
| P3 / Adobe RGB | Partial | EDID + generated profile | Apple documents that non-macOS hosts use EDID/DisplayID and are color-space-limited to P3 even when BT.2020 capability is reported. |
| Webcam, microphone, speakers | Working locally | no custom driver | Enumerate as standard Windows camera and USB audio devices. |
| Adaptive Sync / tearing | Diagnostic packaged | `Check-Gaming.cmd`, `Get-StudioXdrGamingStatus.ps1`, `docs/gaming-tearing.md` | Apple documents Adaptive Sync support, but Windows behavior depends on GPU driver, mode timing, VRR/G-SYNC state, HDR, and the game swapchain. |
| DisplayPort adapter path | Hardware dependent | docs only | Thunderbolt/USB4 is the known-good path. A black-screen DP-to-USB-C path usually leaves Windows with no monitor to override. |

Run `Check-Status.cmd` for a concise local readiness summary and next steps.

## First-Party Gap

The largest remaining gap is real automatic brightness from the Studio Display XDR's own sensors.

Apple documents front and rear ambient light sensors. Windows currently does not expose them as a standard `LightSensor` on the tested machine, and the likely USB interface fails the inbox HID parser. The next native-sensor experiment is an exact libusb-win32 filter on only:

```text
USB\VID_05AC&PID_1116&REV_1801&MI_08
```

That experiment should be done only with a recovery path available. The package includes guarded install and uninstall launchers, but they intentionally require administrator approval and confirmation.

## Sources

- Apple Studio Display XDR technology overview: https://www.apple.com.cn/studio-display-xdr/pdf/Studio_Display_XDR_Technology_Overview_White_Paper_ROW.pdf
- Apple Studio Display XDR tech specs: https://support.apple.com/en-us/126323
- Apple display presets and reference modes: https://support.apple.com/en-ca/108321
- Microsoft ambient light sensor guidance: https://learn.microsoft.com/windows-hardware/design/component-guidelines/ambient-light-sensors
- Microsoft WinUSB installation guidance: https://learn.microsoft.com/windows-hardware/drivers/usbcon/winusb-installation
