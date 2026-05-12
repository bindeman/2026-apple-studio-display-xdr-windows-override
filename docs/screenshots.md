# Screenshot Checklist

Recommended screenshots for the README:

1. Windows Settings before the EDID override, showing only `1920 x 1080`.
2. Installer PowerShell output after `Install-StudioXdrEdidOverride.ps1`.
3. Windows Display resolution list showing `5120 x 2880`.
4. Advanced display showing `5120 x 2880` and `120 Hz`.
5. HDR state after running `Enable-StudioXdrHdr.ps1`, ideally with `BitsPerChannel=10`.
6. Device Manager or PowerShell output showing `USB4 Router (2.0), Apple - Studio Display XDR`.
7. Optional: Windows Color Management screen showing any custom ICC profile associated with the Studio XDR.

Place final images in:

```text
docs/screenshots/
```

Suggested file names:

```text
01-before-resolution.png
02-install-output.png
03-native-resolution.png
04-advanced-display-120hz.png
05-hdr-enabled.png
06-device-manager.png
```
