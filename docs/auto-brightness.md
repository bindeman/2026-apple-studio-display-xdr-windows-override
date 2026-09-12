# Automatic Brightness

Automatic brightness is the highest-priority experimental feature in this repo.

## Current Findings

Windows does not expose a standard ambient-light sensor for the tested Studio Display XDR:

```text
Windows.Devices.Sensors.LightSensor.GetDefault(): null
```

The only Apple sensor-class device currently visible on the test machine is `MI_09`, and Windows identifies it as an orientation sensor that fails to start. That is not usable for display auto-brightness.

The display does expose an Apple USB interface that looks like the right place to read ambient-light data:

```text
USB\VID_05AC&PID_1116&MI_08
Bus reported name: HID Relay
Current Windows driver: input.inf / HidUsb
Current state: Code 10
Driver problem: HID Report Descriptor failed validation
```

That means Windows' generic HID driver sees the interface, but rejects its descriptor. The interface is still present on USB, so it may be possible to talk to it with a custom user-mode connector.

Important: installing a WinUSB package is not enough. The exact `USB\VID_05AC&PID_1116&MI_08` interface must actually bind to that driver. If `Get-StudioXdrAmbientStatus.ps1` still reports `input.inf` / `HidUsb`, the connector is not active.

`Get-StudioXdrAmbientStatus.ps1` also prints the exact target hardware ID currently seen on the machine, for example:

```text
USB\VID_05AC&PID_1116&REV_1801&MI_08
```

That exact interface is the only target to use for any manual or guarded libusb filter experiment.

Apple's Studio Display XDR technology overview says the display has front and rear ambient light sensors. On macOS, those sensors can adjust brightness, black point, and white point when True Tone and automatic adjustments are active. On the tested Windows machine, those sensors are not exposed as a working Windows `LightSensor`, so the repo has to choose between standard Windows ALS from another device, the experimental `MI_08` connector, or the camera fallback.

Microsoft's Windows hardware guidance expects an ambient light sensor to integrate through Windows sensor/HID infrastructure and to be validated through normal automatic-brightness behavior. The Studio Display XDR `MI_08` interface currently fails Windows HID descriptor validation before Windows can treat it as that kind of sensor. That is why the native sensor path is a driver/USB-connector research problem rather than a missing Settings toggle.

## Upstream Clues

StudioBrightness++ is the closest open-source Windows project for Apple display brightness. It uses Windows `ISensorEvents` for automatic brightness and correlates ambient-light sensors to displays by `ContainerId`.

Its current support table lists:

```text
Studio Display XDR, PID 0x1116: no built-in ALS through the Windows Sensor API
Studio Display Gen 2, PID 0x1118: built-in ALS through the Windows Sensor API
```

That matches the local Windows Sensor API result on the tested `0x1116` display: manual brightness works through Apple HID, but no Windows ambient-light sensor is exposed.

This repo keeps the `MI_08` WinUSB path as a deeper experiment because the 2026 Studio Display XDR still presents a failing `HID Relay` interface. It may expose private packets, or it may not carry usable ALS data on `0x1116`.

## Why `MI_08` Matters

The open-source SDBC project for the 2022 Studio Display used the older Studio Display product ID:

```text
VID_05AC&PID_1114&MI_08
```

It read ambient-light packets from interrupt endpoint `0x89` / EP09. Each packet was 18 bytes, with bytes `2..5` interpreted as a little-endian ambient-light value from `0..1,000,000`.

The 2026 Studio Display XDR has the same `MI_08` interface number under product ID `1116`, so this repo includes an experimental connector using the same hypothesis.

Current HID mapping notes are in [hid-research.md](hid-research.md). The key point is that `MI_09` is a Sensor Page `0x20` Device Orientation collection, not an ambient-light collection. A standard HID ambient-light sensor would expose Sensor Page `0x20` Ambient Light usage `0x0041` and illuminance field `0x04D1`; those are not currently exposed as a working HID child collection on the tested machine.

The app now has two experimental `MI_08` user-mode paths:

- WinUSB, for a driver replacement or exact WinUSB binding.
- libusb/libusb-win32, for the SDBC-style filter-driver approach.

## Experimental Connector

Files:

```text
drivers/StudioXdrAmbientWinUsb.inf
scripts/Install-StudioXdrAmbientConnector.ps1
scripts/Test-StudioXdrAmbientConnector.ps1
scripts/Test-StudioXdrLibUsbAmbient.ps1
scripts/Test-StudioXdrAmbientPreflight.ps1
scripts/Test-StudioXdrAmbientDriverTarget.ps1
scripts/New-StudioXdrAmbientDriverPackage.ps1
scripts/Get-StudioXdrAmbientStatus.ps1
scripts/Install-StudioXdrLibUsbFilter.ps1
Prepare-Ambient-Driver.cmd
Install-Ambient-Connector.cmd
Install-LibUsb-Ambient-Filter.cmd
Check-Ambient.cmd
```

The connector targets only:

```text
USB\VID_05AC&PID_1116&REV_1801&MI_08
USB\VID_05AC&PID_1116&MI_08
```

The exact `REV_1801` form is listed first because that is what the tested 2026 Studio Display XDR currently exposes. If Windows keeps the interface on `input.inf` / `HidUsb`, the connector is not active even if the INF file exists in the repo.

The bundled INF follows Microsoft's current WinUSB custom-INF pattern:

```text
[USB_Install]
Include = winusb.inf
Needs   = WINUSB.NT

[USB_Install.Services]
Include = winusb.inf
Needs   = WINUSB.NT.Services
```

It also registers the repo's device-interface GUID under `DeviceInterfaceGUIDs`, which is how the app finds the WinUSB path after binding.

Important limitation: the repo does not ship a signed catalog for this experimental driver package. Microsoft's WinUSB packaging guidance says a signed catalog is required for normal installation. That means a local Windows machine may reject the INF until it is signed/test-signed, or until a tool such as Zadig/libwdi creates a signed WinUSB package for the exact `MI_08` interface.

To prepare a local test-signed package when the Windows Driver Kit is installed:

```text
Prepare-Ambient-Driver.cmd
```

or:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\New-StudioXdrAmbientDriverPackage.ps1
```

The helper checks for `inf2cat.exe` and `signtool.exe`, generates `drivers\StudioXdrAmbientWinUsb.cat`, creates or reuses a current-user code-signing certificate, and signs the catalog. Passing `-InstallCertificate` from an elevated PowerShell also installs that local test certificate into the machine Root and TrustedPublisher stores. This is for local experimentation only; it is not a public release signature.

Before changing drivers, run the dry-run target check:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\Test-StudioXdrAmbientDriverTarget.ps1
```

It confirms the connected hardware ID, whether the packaged INF matches it, whether the INF follows the documented WinUSB include pattern, whether any matching OEM INF is already in the Windows driver store, what Windows lists as matching drivers, and whether `MI_08` is actually bound to WinUSB.

It does not replace the camera, microphone, speakers, brightness HID interface, USB hub, or display path.

The test probe first looks for this WinUSB device-interface GUID:

```text
{6F94F6F0-7B76-4DFB-AD85-905E20C82D9D}
```

If a manual Zadig/libwdi binding does not register that GUID, the probe also checks Windows' generic USB device-interface GUID and filters for `VID_05AC&PID_1116&MI_08`.

Then it reads pipe:

```text
0x89
```

and decodes bytes `2..5` as an ambient reading.

The packaged app also includes an SDBC-style libusb reader using USB configuration `1`, interface `8`, interrupt endpoint `0x89`, 18-byte packets, and bytes `2..5` as a `0..1,000,000` ambient value. For Studio Display XDR the product ID is `0x1116`.

## App Behavior

The Studio Display XDR app now has an `Automatically adjust brightness` toggle.

Current source priority:

1. Windows native ambient-light sensor. The app and console checks enumerate Windows light sensors, prefer Apple/display-looking sensors by name/device ID, then fall back to `LightSensor.GetDefault()`.
2. Experimental Studio Display XDR `MI_08` connector, if it is bound to WinUSB and returns packets.
3. Experimental Studio Display XDR `MI_08` libusb connector, if a libusb/libusb-win32-compatible filter exposes interface `8`.
4. Studio Display Camera fallback, if no sensor path is available.

This means a connected Pro Display XDR or older Studio Display can be reused as the automatic-brightness sensor for Studio Display XDR if Windows exposes that other display's sensor through the standard Windows `LightSensor` API.
The shared script `scripts\WindowsLightSensorTools.ps1` keeps the console readiness and ambient checks aligned with the app's enumeration behavior.

Use `scripts\Get-AppleDisplaySensorCorrelation.ps1` to correlate Apple display USB containers with Windows Sensor-class and WinRT `LightSensor` candidates. This is the clearest read-only check when a Pro Display XDR or older Studio Display is connected alongside Studio Display XDR.

The camera fallback is opt-in through the same automatic brightness toggle. It uses the working Studio Display Camera, captures a still frame at low frequency, samples frame luminance, and maps that to the same Apple HID brightness control path.

The opt-in state is persistent. If automatic brightness is enabled and Open at login is also enabled, the app starts minimized after Windows starts and resumes automatic brightness when an ambient source is available.

Current local result:

```text
Windows native ALS: null
MI_08 connector: not bound; still input.inf / HidUsb / Code 10
Camera fallback: working; captured from Studio Display Camera and adjusted brightness through HID
```

Brightness curve:

```text
ambient 0..1,000,000
-> normalized 0.0..1.0
-> gamma curve 0.48
-> brightness 8%..100%
```

The app smooths changes to avoid harsh jumps.

The app also stores a small local calibration:

- Automatic brightness enabled/disabled state.
- Minimum brightness: prevents camera fallback from making the display too dim.
- Response: biases the curve darker or brighter for a given ambient reading.

Settings are stored per user under:

```text
%LOCALAPPDATA%\StudioDisplayXdr\settings.json
```

Camera fallback limitations:

- It is not a calibrated lux sensor.
- Camera auto-exposure affects the reading.
- The camera privacy indicator may turn on while automatic brightness is active.
- Near-black camera frames are treated as low-confidence and pause automatic brightness instead of dimming the display.
- Camera-derived automatic brightness uses a higher default floor than real sensor readings.

## Binding Status

Quick preflight:

```text
Check-Ambient.cmd
```

or:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\Test-StudioXdrAmbientPreflight.ps1
```

The preflight reduces the current state to a simple verdict:

- Standard Windows ambient-light sensor ready.
- Native Studio Display XDR `MI_08` WinUSB/libusb packets ready.
- Camera fallback ready, but native `MI_08` still not bound.
- No automatic-brightness source ready.

Check the current binding:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\Get-StudioXdrAmbientStatus.ps1
```

Expected before the connector is bound:

```text
Service: HidUsb
DriverInfPath: input.inf
ProblemCode: 10
Windows matching drivers: input.inf
Best-ranked/installed: input.inf
Ambient packet probe: No Studio XDR ambient WinUSB interface found.
```

If the PnP matching-driver view lists only `input.inf`, Windows has not accepted or ranked any WinUSB/libwdi package for the exact `MI_08` interface yet. That is different from merely having an INF file in the extracted ZIP.

Expected after a successful WinUSB/libusb binding:

```text
DriverProvider: libwdi or Studio Display XDR Windows Override
Service: WinUSB
Windows matching drivers: <WinUSB/libwdi package>, input.inf
Ambient packet probe returns Transferred=18 and Ambient=<number>
```

Current failed binding example:

```text
Driver Name: input.inf
Matching Drivers: input.inf only
Exact Studio XDR INF in driver store: none
libwdi WinUSB package may be installed, but MI_08 is not bound
No UpperFilters or LowerFilters are registered on the MI_08 device instance
Ambient packet probe: No Studio XDR ambient WinUSB interface found.
```

Current USB topology finding:

```text
Studio Display XDR 1116 MI_08 HIDClass Error USB Input Device HidUsb ProblemCode=10 DriverInf=input.inf
Bus reported name: HID Relay
Hardware IDs: USB\VID_05AC&PID_1116&REV_1801&MI_08; USB\VID_05AC&PID_1116&MI_08
Compatible IDs: USB\Class_03...
Problem: HID Report Descriptor failed validation.
```

That reinforces the current hypothesis: `MI_08` is visible as a USB HID interface, but Windows rejects the HID descriptor before exposing a normal sensor or usable HID collection. A WinUSB/libusb binding still looks like the best next native-sensor experiment because it bypasses the failing HID parser for this interface.

## Manual Zadig Binding

If `Get-StudioXdrAmbientStatus.ps1` still shows `input.inf` / `HidUsb`, the driver package is installed but the target interface is not bound.

Use Zadig carefully:

1. Open Zadig as administrator.
2. Choose `Options > List All Devices`.
3. Select the Studio Display XDR interface that corresponds to:

```text
USB\VID_05AC&PID_1116&MI_08
Bus reported device description: HID Relay
```

4. Do not select the Studio Display camera, audio device, USB hub, brightness HID interface, or the parent USB composite device.
5. Select `WinUSB`.
6. Click `Replace Driver`.
7. Unplug and reconnect the Studio Display XDR, or disable/enable the `MI_08` device.
8. Run:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\Get-StudioXdrAmbientStatus.ps1
```

The success condition is not just that a WinUSB package exists. The actual `USB\VID_05AC&PID_1116&MI_08` device must show a WinUSB/libwdi binding, and the packet probe must return data. The current app/probe can detect either the repo's custom interface GUID or a generic USB device-interface path from a manual libwdi binding.

The libusb probe is separate:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\Test-StudioXdrLibUsbAmbient.ps1
```

Current local result before an exact filter is installed:

```text
No Studio Display XDR libusb device opened. Install an exact libusb-win32 filter for USB\VID_05AC&PID_1116&MI_08 first.
```

## Manual libusb-win32 Filter Binding

The older SDBC Windows path for the 2022 Studio Display used a libusb-win32 filter on the display's `MI_08` interface instead of replacing the HID driver. That is now the next best experiment for Studio Display XDR because the current machine has generic libusb/libwdi packages installed, but no exact MI_08 filter.

Use the libusb-win32 Filter Wizard carefully:

1. Open `install-filter-win.exe` as administrator from a libusb-win32 package.
2. Choose `Install a device filter`.
3. Select only the Studio Display XDR interface that matches:

```text
vid:05ac pid:1116 rev:1801 mi:08
```

4. Do not select the camera, audio device, parent USB composite device, hub, brightness HID interface, or any non-`mi:08` interface.
5. Reboot. The older SDBC instructions call the reboot important.
6. Run:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\Get-StudioXdrAmbientStatus.ps1
```

For this path, the underlying HID device may still show `HidUsb`, but the MI_08 instance should have a libusb-compatible filter and the packaged app should be able to read the sensor through its optional LibUsbDotNet path.

After a successful filter install, expected libusb probe shape is:

```text
LibUSB path opened.
Transferred=18
Raw=<18 bytes>
Ambient=<number>
```

If `install-filter.exe` is already available, the repo includes a guarded launcher for the same exact target:

```text
Install-LibUsb-Ambient-Filter.cmd
```

It still requires elevation and confirmation, and it will not run silently by default.

The matching cleanup launcher is:

```text
Uninstall-LibUsb-Ambient-Filter.cmd
```

The guided uninstaller can also offer this removal path. It defaults to no.

## Notes

The included INF is a precise target spec for the interface. On normal Windows installs, unsigned INF installation may be rejected. Zadig/libwdi can generate a signed package for this exact interface; when doing that manually, select only the `HID Relay` / `MI_08` interface for `VID_05AC&PID_1116`, not the composite device.

Once the interface is bound and the packet probe returns values, the app-side auto-brightness loop is already implemented.

## USB Topology Dump

For native sensor research, collect a read-only dump of every Apple display USB interface:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\Get-AppleDisplayUsbTopology.ps1
```

This captures:

- Product ID and likely display family.
- USB interface number, for example `MI_08`.
- Current Windows class, service, problem code, and driver INF.
- Hardware IDs, compatible IDs, container ID, and location paths.

When a Pro Display XDR or older Studio Display is connected at the same time, this output is the easiest way to compare whether those displays expose a normal Windows sensor interface that the Studio Display XDR does not.

For direct Sensor-class and WinRT `LightSensor` correlation, run:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\Get-AppleDisplaySensorCorrelation.ps1
```

Current local result: one Studio Display XDR container, one Studio-owned `MI_09` orientation sensor, no ambient HID sensor, and WinRT `LightSensor` candidate count `0`.

Use:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\Get-AppleDisplayUsbTopology.ps1 -ProductId 1116,9243,1114,1118
```

to include Studio Display XDR, Pro Display XDR, older Studio Display, and future or alternate Studio Display product IDs in the same report.

References:

- Apple Studio Display XDR technology overview: https://www.apple.com.cn/studio-display-xdr/pdf/Studio_Display_XDR_Technology_Overview_White_Paper_ROW.pdf
- Microsoft ambient light sensor guidance: https://learn.microsoft.com/windows-hardware/design/component-guidelines/ambient-light-sensors
- https://github.com/LitteRabbit-37/Studio-Brightness-PlusPlus
- https://github.com/waydabber/BetterDisplay/wiki/Integration-features%2C-CLI
- https://www.scivision.dev/apple-studio-display-brightness-windows/
