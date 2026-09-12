# Screenshot Checklist

Recommended screenshots for the README:

0. Setup launcher: `docs/screenshots/setup-launcher.png`.
1. Control panel: `docs/screenshots/control-panel.png`.
2. Control panel lower section: `docs/screenshots/control-panel-about.png`.
3. Windows Settings before the EDID override, showing only `1920 x 1080`.
4. Installer PowerShell output after `Install-StudioXdrEdidOverride.ps1`.
5. Windows Display resolution list showing `5120 x 2880`.
6. Advanced display showing `5120 x 2880` and `120 Hz`.
7. HDR state after running `Enable-StudioXdrHdr.ps1`, ideally with `BitsPerChannel=10`.
8. Device Manager or PowerShell output showing `USB4 Router (2.0), Apple - Studio Display XDR`.
9. Optional: Windows Color Management screen showing any custom ICC profile associated with the Studio XDR.
10. Brightness status output showing `Current=60000 (~60%)` or another raw/percent value.

Place final images in:

```text
docs/screenshots/
```

Suggested file names:

```text
control-panel.png
control-panel-about.png
setup-launcher.png
01-before-resolution.png
02-install-output.png
03-native-resolution.png
04-advanced-display-120hz.png
05-hdr-enabled.png
06-device-manager.png
```
