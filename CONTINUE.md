# Continue Prompt

Paste this into Codex after reboot:

```text
Continue from C:\Users\Beast\Documents\Dev\Apple Studio Display XDR Windows.
Read README.md, CONTINUE.md, and current git status first.

Current state:
- We got the 2026 Apple Studio Display XDR working in Windows at 5120x2880 @ 120 Hz.
- Native mode works via a Studio Display XDR EDID override.
- HDR / Advanced Color was enabled through the Windows DisplayConfig API.
- The reusable HDR command is:
  powershell -ExecutionPolicy Bypass -File .\scripts\Enable-StudioXdrHdr.ps1
- The status command is:
  powershell -ExecutionPolicy Bypass -File .\scripts\Get-StudioXdrStatus.ps1
- GitHub repo:
  https://github.com/bindeman/2026-apple-studio-display-xdr-windows-override
- Local origin points to that repo.
- Repo description:
  Enable 5K 120Hz HDR on Apple Studio Display XDR in Windows.

Next goal:
Continue hacking brightness support, packaging, screenshots, docs, or EXE/GUI installer.
Current investigation:
- Refresh-rate toggling can clear a transient right-side pixelated/tile artifact.
- Color profile support is not complete; Windows gets EDID wide-color/HDR metadata, but Apple macOS reference presets/ICC profile handling still need research.
```

## Quick Verification

```powershell
cd "C:\Users\Beast\Documents\Dev\Apple Studio Display XDR Windows"
powershell -ExecutionPolicy Bypass -File .\scripts\Get-StudioXdrStatus.ps1
powershell -ExecutionPolicy Bypass -File .\scripts\Enable-StudioXdrHdr.ps1
git status
```
