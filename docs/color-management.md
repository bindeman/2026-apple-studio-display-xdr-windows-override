# Color Management

This project fixes Windows display mode negotiation for Studio Display XDR. Color management is related, but separate.

## What Works Now

With the EDID override installed:

- Windows can use `5120x2880 @ 120 Hz`.
- The imported EDID exposes wide-color/HDR metadata.
- The HDR script enables Windows Advanced Color through the DisplayConfig API.
- Local verification reported `BitsPerChannel=10` after HDR was enabled.

The panel itself may use 8-bit + FRC behavior internally. `BitsPerChannel=10` means the Windows output signal path is 10 bpc, not that the physical LCD subpixels are necessarily native 10-bit.

## P3, Adobe RGB, and Apple Presets

Apple advertises Studio Display XDR wide gamut support including P3 and Adobe RGB. The hardware can cover those gamuts, but macOS exposes that through Apple's display preset/reference-mode system.

Examples of Apple-side presets include:

- Apple XDR Display (P3-2000 nits)
- Apple XDR Display (P3 + Adobe RGB-2000 nits)
- HDR Video / ST 2084 style reference modes
- Photography / print-oriented presets

Those presets are not the same thing as simply installing a Windows ICC profile. They combine display firmware behavior, luminance targets, EOTF, gamut mapping, and color-management metadata.

## Current Windows Limitation

This repo does not currently include an Apple-authored Studio Display XDR ICC/ICM profile.

On the tested Windows machine, no Apple display profiles were present under:

```text
C:\Windows\System32\spool\drivers\color
```

The current workaround gets Windows into the correct high-bandwidth display mode and enables HDR/Advanced Color, but it does not recreate Apple's macOS reference-mode UI.

## Recommended Path For Accurate Color

For casual use, the EDID + Windows HDR path is enough to expose wide color and HDR behavior.

For color-critical work:

1. Use the display in the desired Windows mode, for example `5120x2880 @ 120 Hz`.
2. Decide whether you are targeting SDR, HDR, P3, Adobe RGB, or sRGB.
3. Use a hardware colorimeter/spectroradiometer and calibration software that can create a Windows ICC profile for that exact mode.
4. Associate the generated ICC profile with the Studio XDR in Windows Color Management.

## Open Work

Useful future improvements:

- Add a script to install and associate an ICC/ICM profile with the active Studio XDR monitor.
- Find whether Apple provides a redistributable Studio Display XDR ICC/ICM profile for Windows.
- Investigate whether Apple reference presets can be selected over the same USB HID path used for brightness.
- Add measured profiles for common modes, if licensing and accuracy are acceptable.

## References

- Apple Studio Display XDR tech specs: https://support.apple.com/en-us/126323
- Apple display presets and reference modes: https://support.apple.com/en-ca/108321
- Studio Display XDR technology overview: https://www.apple.com.cn/studio-display-xdr/pdf/Studio_Display_XDR_Technology_Overview_White_Paper_ROW.pdf
