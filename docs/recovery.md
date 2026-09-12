# Recovery

If the EDID override creates a bad display state, use one of these recovery paths.

## Normal Recovery

Run the guided uninstaller from the repo folder:

```text
Uninstall-StudioDisplayXdrSupport.cmd
```

It can remove the app startup entry, Start Menu/Desktop shortcuts, the stable per-user app copy under `%LOCALAPPDATA%\StudioDisplayXdr\Support`, the generated Display P3 profile association, the optional experimental libusb-win32 `MI_08` filter, and the Studio Display XDR EDID override.

For EDID-only recovery, open an elevated PowerShell in the repo folder:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\Uninstall-StudioXdrEdidOverride.ps1
```

Then reboot Windows.

## Full Command-Line Cleanup

Open an elevated PowerShell in the repo folder:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\Uninstall-StudioDisplayXdrSupport.ps1 -RemoveColorProfile -RemoveProfileFile -RemoveEdidOverride
```

This removes the same support-package state as the guided uninstaller, plus the generated profile file from the Windows color directory when present. Reboot Windows if the EDID override was removed.

To keep the installed control panel files but remove shortcuts/startup/profile state, add:

```powershell
-KeepInstalledApp
```

If the experimental libusb-win32 ambient filter was installed, use the guided uninstaller's optional filter cleanup or run:

```text
Uninstall-LibUsb-Ambient-Filter.cmd
```

That removal path targets only the Studio Display XDR `MI_08` interface and still asks for confirmation.

## If The Screen Is Unusable

Some GPU / driver / connection paths accept the override but cannot actually drive the Studio Display XDR modes it advertises. The reported case is a Mac Pro 2019 running Boot Camp Windows 10 on a Radeon Pro W6900X: after the override and a reboot the display stayed black, without even the `640 x 480` fallback. The override lives only in the registry, so it is always recoverable.

### Safe Mode

1. Get to the Windows Recovery Environment (WinRE). If you cannot see anything: power on, and as soon as Windows starts loading hold the power button until the PC turns off. Repeat twice. On the third boot Windows opens **Automatic Repair**. Choose **Advanced options**.
2. Choose **Troubleshoot** > **Advanced options** > **Startup Settings** > **Restart**, then press `4` (or `F4`) for **Safe Mode**.
3. In Safe Mode, open an elevated PowerShell and run:

```powershell
cd "C:\path\to\studio-display-xdr-windows"
powershell -ExecutionPolicy Bypass -File .\scripts\Uninstall-StudioXdrEdidOverride.ps1 -All
```

`-All` removes every `EDID_OVERRIDE` key that this project created (the key is tagged with the name `Studio XDR`), even when the Studio Display XDR is not the active monitor. Add `-Force` to also remove overrides created by other tools such as CRU.

4. Reboot normally.

If Safe Mode is also black on the Studio Display XDR, connect any other monitor (or use the laptop's built-in screen) for the recovery steps. The override only affects the Apple display.

### Offline Registry Cleanup From WinRE

If Windows cannot reach the desktop at all, remove the override from the WinRE **Command Prompt** (**Troubleshoot** > **Advanced options** > **Command Prompt**):

```text
rem The Windows drive is often C: in WinRE, but check with: dir C:\Windows
reg load HKLM\OfflineSystem C:\Windows\System32\config\SYSTEM

rem Find which control set is current (0x1 means ControlSet001)
reg query HKLM\OfflineSystem\Select /v Current

rem List every EDID_OVERRIDE key
reg query HKLM\OfflineSystem\ControlSet001\Enum\DISPLAY /s /f EDID_OVERRIDE /k

rem Delete the one under the Studio Display XDR monitor instance (adjust the path from the query output)
reg delete "HKLM\OfflineSystem\ControlSet001\Enum\DISPLAY\MS_0001\4&219099A4&0&UID45127\Device Parameters\EDID_OVERRIDE" /f

reg unload HKLM\OfflineSystem
```

Then close the Command Prompt and choose **Continue** to boot Windows normally.

### Boot Camp Notes

Boot Camp Macs use Apple's own GPU firmware/driver path, and Apple documents the Studio Display XDR for Apple silicon Macs and Thunderbolt/USB4 PCs. Windows 10 Boot Camp on an Intel Mac Pro with a Radeon Pro W6900X is untested by this project and the one report so far is a black screen. Recover with the steps above, then run `Check-Status.cmd` / `Support-Report.cmd` from a working state and attach the report to a GitHub issue before retrying.

## CRU Fallback

If CRU was used instead of the built-in installer, CRU's reset tool can clear all CRU overrides:

```powershell
.\downloads\cru-1.5.3\reset-all.exe
```

Then reboot.
