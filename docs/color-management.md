# Color Management

This project fixes Windows display mode negotiation for Studio Display XDR. Color management is related, but separate.

## What Works Now

With the EDID override installed:

- Windows can use `5120x2880 @ 120 Hz`.
- The imported EDID exposes wide-color/HDR metadata.
- The HDR script enables Windows Advanced Color through the DisplayConfig API.
- Local verification reported `BitsPerChannel=10` after HDR was enabled.
- `scripts/Get-StudioXdrColorStatus.ps1` can identify the active Studio XDR DisplayConfig target/source IDs needed by modern Windows color-profile APIs.
- `profiles/StudioDisplayXDR-DisplayP3.icm` provides a generated Display P3 D65 gamma 2.2 baseline profile.

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

Apple's Studio Display XDR technology overview explicitly separates macOS from non-macOS behavior. It says Windows and Linux use VESA DisplayID / EDID to learn the display capabilities, and that non-macOS hosts can see BT.2020-style capability reporting while the actual system-level color space is limited to P3. That matches the safest current claim for this repo: native transport, Windows Advanced Color, and a P3 baseline profile, not full Apple preset parity.

It does include a generated Windows baseline profile:

```text
profiles\StudioDisplayXDR-DisplayP3.icm
```

This generated profile is a matrix/TRC Display P3 D65 gamma 2.2 profile. It is not an Apple reference-mode profile and does not encode Apple's preset luminance behavior.

On the tested Windows machine, no Apple display profiles were present under:

```text
C:\Windows\System32\spool\drivers\color
```

No reusable Pro Display XDR `.icc` or `.icm` files were found in the locally extracted Boot Camp package either.

The current workaround gets Windows into the correct high-bandwidth display mode and enables HDR/Advanced Color, but it does not recreate Apple's macOS reference-mode UI.

## Profile Status

Run:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\Get-StudioXdrColorStatus.ps1
```

Example local output:

```text
MonitorName:            Studio XDR
GdiDeviceName:          \\.\DISPLAY2
SourceAdapterLuid:      00000000:00017D62
SourceId:               1
TargetId:               69
AdvancedColorSupported: True
AdvancedColorEnabled:   True
BitsPerColorChannel:    10
AdvancedColorRaw:       7
```

The script also lists installed profiles whose filenames look relevant to Apple, Studio Display, P3, Adobe RGB, BT.2020, HDR, or XDR. On the current test machine that list is empty.

For a broader read-only search, run:

```text
Check-Color.cmd
```

or:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\Find-StudioXdrColorProfiles.ps1 -IncludeUserFolders
```

This scans the bundled `profiles` folder, the Windows color-profile store, likely Apple/Boot Camp install folders, and optionally user folders for valid `.icc` / `.icm` files. It flags names/descriptions that look relevant to Apple, Studio Display, Pro Display XDR, P3, Adobe RGB, BT.2020, HDR, or ST 2084.

The Studio Display XDR control panel's Color profile row has a `Check` button for the same discovery path and summarizes whether it found Apple/Pro Display candidates or only the generated Display P3 baseline.

If a real Apple or Pro Display XDR profile is found, treat it as a candidate, not proof of correctness for Studio Display XDR. Install it only after deciding the profile is appropriate for the target mode and preferably validating with measurement.

## Installing A Profile

Install and associate the generated Display P3 baseline profile:

```text
Install-Color-Profile.cmd
```

You can also install the bundled profile from the Studio Display XDR control panel. The Color profile row detects whether the generated profile is available and whether it already exists in Windows' color-profile folder.

Or run the script directly:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\Install-StudioXdrColorProfile.ps1 -ProfilePath .\profiles\StudioDisplayXDR-DisplayP3.icm
```

Install and associate another `.icc` or `.icm` profile with the active Studio XDR target:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\Install-StudioXdrColorProfile.ps1 -ProfilePath .\profiles\StudioXDR.icm
```

For an HDR / Advanced Color profile association, use:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\Install-StudioXdrColorProfile.ps1 -ProfilePath .\profiles\StudioXDR-HDR.icm -AdvancedColor
```

The installer:

1. Installs the profile into Windows Color Management.
2. Finds the active Studio XDR DisplayConfig source.
3. Calls the modern display color-profile association API.
4. Attempts legacy per-user profile association for the detected GDI display name, for example `\\.\DISPLAY2`.

The generated profile can be rebuilt with:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\New-StudioXdrDisplayP3Profile.ps1
```

## Luminance Metadata

Peak HDR luminance is not normally controlled by an ICC profile. For Windows HDR detection, the relevant values are in the display EDID / CTA HDR Static Metadata block.

The bundled Studio XDR EDID currently contains:

```text
HDR metadata bytes: E6 06 05 01 AB 73 00
Desired content max luminance:        code 0xAB ~= 2030.5 nits
Desired max frame-average luminance:  code 0x73 ~= 603.7 nits
Minimum luminance:                    code 0x00
```

So the EDID already advertises roughly 2000 nits peak HDR luminance. It is not carrying a 1600-nit Pro Display XDR value.

The `603.7 nits` frame-average value should not be blindly treated as "SDR brightness." Apple's SDR/reference-mode brightness behavior is part of its display preset system and local dimming behavior, not just an ICC profile field. Patching the EDID frame-average luminance to approximate 1000 nits may be possible, but it should be tested as a separate experimental EDID variant rather than made the default.

## Recommended Path For Accurate Color

For casual use, the EDID + Windows HDR path is enough to expose wide color and HDR behavior.

For color-critical work:

1. Use the display in the desired Windows mode, for example `5120x2880 @ 120 Hz`.
2. Decide whether you are targeting SDR, HDR, P3, Adobe RGB, or sRGB.
3. Use a hardware colorimeter/spectroradiometer and calibration software that can create a Windows ICC profile for that exact mode.
4. Associate the generated ICC profile with the Studio XDR in Windows Color Management.

## Open Work

Useful future improvements:

- Find whether Apple provides a redistributable Studio Display XDR ICC/ICM profile for Windows.
- Use `Find-StudioXdrColorProfiles.ps1 -IncludeUserFolders` against Boot Camp or Apple installer extracts to catalog candidate Apple display profiles before importing them.
- Investigate whether Apple reference presets can be selected over the same USB HID path used for brightness.
- Add measured profiles for common modes, if licensing and accuracy are acceptable.
- Investigate whether Apple CMF 2026 measurement support becomes accessible to third-party Windows calibration tools. Apple's white paper says Studio Display XDR factory calibration and some presets use Apple CMF 2026, while other reference modes remain based on CIE 1931.

## References

- Apple Studio Display XDR tech specs: https://support.apple.com/en-us/126323
- Apple display presets and reference modes: https://support.apple.com/en-ca/108321
- Studio Display XDR technology overview: https://www.apple.com.cn/studio-display-xdr/pdf/Studio_Display_XDR_Technology_Overview_White_Paper_ROW.pdf
- Microsoft `ColorProfileAddDisplayAssociation`: https://learn.microsoft.com/en-us/windows/win32/api/icm/nf-icm-colorprofileadddisplayassociation
- Microsoft `AssociateColorProfileWithDevice`: https://learn.microsoft.com/windows/win32/api/icm/nf-icm-associatecolorprofilewithdevicea
- Microsoft `WcsSetDefaultColorProfile`: https://learn.microsoft.com/windows/win32/api/icm/nf-icm-wcssetdefaultcolorprofile
