# Profiles

This folder contains optional Studio Display XDR `.icc` / `.icm` color profiles.

Bundled profile:

```text
StudioDisplayXDR-DisplayP3.icm
```

This is a generated matrix/TRC Display P3 D65 gamma 2.2 profile for Windows color management. It is not an Apple-authored Studio Display XDR reference-mode profile.

Install and associate it with the active Studio Display XDR:

```text
Install-Color-Profile.cmd
```

Or install a profile manually:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\Install-StudioXdrColorProfile.ps1 -ProfilePath .\profiles\StudioDisplayXDR-DisplayP3.icm
```

Use a hardware calibrator for color-critical work. A calibrator-generated profile for your specific panel should be preferred over this generated baseline.
