# DisplayPort to USB-C / Thunderbolt Adapters

Studio Display XDR is primarily a Thunderbolt 5 display. The known-good Windows path is:

```text
PC Thunderbolt / USB4 port with display output
  -> Thunderbolt cable
  -> Studio Display XDR upstream Thunderbolt port
```

## Black Screen With DP-to-Thunderbolt

If a DisplayPort-to-USB-C/Thunderbolt cable or adapter gives a black screen, this project cannot fix that in software unless Windows can at least see a monitor device.

Check:

```powershell
Get-PnpDevice -Class Monitor -PresentOnly
```

If no new `DISPLAY\...` monitor appears, Windows did not receive a usable EDID from the display. The EDID override installer has nothing to bind to.

## Direction Matters

Most USB-C-to-DisplayPort cables are one-way:

```text
USB-C / Thunderbolt host -> DisplayPort monitor
```

That is the opposite of what is needed here.

For an Apple display, the needed direction is:

```text
DisplayPort source -> USB-C display input
```

The cable/adapter must explicitly support that direction. A cable described only as "USB-C to DisplayPort" usually will not work in reverse.

## Thunderbolt Is Not Just A Connector

A USB-C connector does not guarantee Thunderbolt or USB4 tunneling.

There are several different paths:

```text
Thunderbolt / USB4 tunneling
DisplayPort Alt Mode over USB-C
Active DisplayPort source to USB-C display conversion
Passive cable with the wrong direction
```

Studio Display XDR's full feature set depends on the Thunderbolt/USB4 path. A plain DisplayPort-to-USB-C video path, if it works at all, may lose:

- camera
- speakers / microphone
- USB hub features
- Apple HID brightness control
- HDR / Adaptive Sync behavior
- 5K120 timing support

## Expected Limits

DisplayPort 1.4 may be enough for some 5K modes with DSC, but it is not the same as the known-good Thunderbolt 5 / USB4 path. For Studio Display XDR, expect DP adapter experiments to be limited and adapter-specific.

Practical expectations:

- `5K @ 60 Hz`: plausible with the right active DP-source-to-USB-C-display cable.
- `5K @ 120 Hz`: unlikely over a generic DP 1.4 adapter path; use Thunderbolt/USB4.
- USB features and brightness: unlikely unless the adapter also carries a working USB data path.

## What This Repo Can Support

This repo can help when Windows sees the display but exposes bad modes, for example:

```text
DISPLAY\MS_0001
1920x1080 only
```

In that case, the EDID override may expose the correct native modes.

This repo cannot make a black-screen adapter path work when the GPU, adapter, and display never complete link training or EDID discovery.

## Recommended Troubleshooting

1. Use the included Apple Thunderbolt cable through a PC Thunderbolt/USB4 port first.
2. Confirm the display works at `5120x2880 @ 120 Hz`.
3. Only then test DP adapters.
4. For DP adapter tests, use a cable explicitly described as `DisplayPort source to USB-C display`.
5. After connecting the adapter, check whether Windows sees a new monitor with `Get-PnpDevice -Class Monitor -PresentOnly`.
6. If it appears as a fallback monitor, try the EDID override.
7. If the screen is black and no monitor appears, treat it as a hardware/adapter incompatibility.
