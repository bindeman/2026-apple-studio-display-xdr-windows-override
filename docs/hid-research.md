# HID Research Notes

These notes document the current Studio Display XDR USB HID map on Windows. They keep the automatic-brightness work focused on real light-sensor candidates instead of every Apple HID interface that happens to enumerate.

## Current Local HID Map

Run:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\Dump-StudioXdrHidCollections.ps1
```

Current useful findings:

| Interface | HID collection | Meaning |
| --- | --- | --- |
| `MI_07`, collection 1 | Usage Page `0x0080`, Usage `0x0001`; value Usage Page `0x0082`, Usage `0x0010` | Working monitor brightness control path. |
| `MI_07`, collection 2 | Vendor input plus Sensor Page `0x20`, Usage `0x030E` feature | Not illuminance. `0x030E` is the sensor `Report Interval` property. |
| `MI_08` | USB HID Relay, Code 10 | Main native-sensor experiment. Windows rejects the HID report descriptor before exposing a usable HID collection. |
| `MI_09` | Sensor Page `0x20`, Usage `0x008A` | Device Orientation sensor, not ambient light. Currently fails Windows sensor initialization locally. |

Per the USB HID Sensor Usage Tables, a standard ambient-light sensor collection would use Sensor Page `0x20` with Ambient Light Usage `0x0041`, and illuminance data would use `0x04D1`. Those are not exposed as a working HID child collection on the tested Studio Display XDR.

## What This Means

The working brightness path is separate from automatic brightness. Brightness writes go through the monitor-control HID collection, while automatic brightness needs an ambient source.

The current native automatic-brightness candidates are:

1. A normal Windows `LightSensor`, if Windows exposes one from any connected Apple display or PC sensor.
2. The experimental `MI_08` WinUSB/libusb path, if the exact `USB\VID_05AC&PID_1116&REV_1801&MI_08` interface can be bound and returns packets.
3. The opt-in Studio Display Camera fallback.

Do not bind filters to `MI_09` for brightness. It is an orientation sensor path, and the standard HID usage does not match ambient light.

## References

- USB-IF HID Sensor Usages, Usage Page `0x20`: <https://www.usb.org/sites/default/files/hutrr39b_0.pdf>
- USB-IF HID Usage Tables: <https://usb.org/sites/default/files/hut1_3_0.pdf>
- Microsoft Sensor HID class driver notes: <https://learn.microsoft.com/en-us/windows-hardware/drivers/hid/sensor-hid-class-driver>
