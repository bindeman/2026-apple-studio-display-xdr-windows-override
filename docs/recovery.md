# Recovery

If the EDID override creates a bad display state, use one of these recovery paths.

## Normal Recovery

Open an elevated PowerShell in the repo folder:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\Uninstall-StudioXdrEdidOverride.ps1
```

Then reboot Windows.

## If The Screen Is Unusable

1. Boot Windows in Safe Mode.
2. Open an elevated PowerShell.
3. Run:

```powershell
cd "C:\path\to\studio-display-xdr-windows"
powershell -ExecutionPolicy Bypass -File .\scripts\Uninstall-StudioXdrEdidOverride.ps1
```

4. Reboot normally.

## CRU Fallback

If CRU was used instead of the built-in installer, CRU's reset tool can clear all CRU overrides:

```powershell
.\downloads\cru-1.5.3\reset-all.exe
```

Then reboot.
