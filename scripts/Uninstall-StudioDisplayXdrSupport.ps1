param(
    [switch]$RemoveEdidOverride,
    [switch]$RemoveColorProfile,
    [switch]$RemoveProfileFile,
    [switch]$RemoveLibUsbFilter,
    [switch]$RemoveInstalledApp,
    [switch]$KeepInstalledApp,
    [switch]$KeepShortcuts,
    [switch]$KeepStartup,
    [switch]$NoPrompt,
    [string]$InstallRoot = ""
)

$ErrorActionPreference = "Stop"

function Get-RepoRoot {
    Split-Path -Parent $PSScriptRoot
}

function Get-DefaultInstallRoot {
    Join-Path (Join-Path ([Environment]::GetFolderPath("LocalApplicationData")) "StudioDisplayXdr") "Support"
}

function Assert-SafeInstallRoot {
    param([string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path)) {
        $Path = Get-DefaultInstallRoot
    }

    $base = Join-Path ([Environment]::GetFolderPath("LocalApplicationData")) "StudioDisplayXdr"
    $trimChars = [char[]]@([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar)
    $baseFull = [System.IO.Path]::GetFullPath($base).TrimEnd($trimChars)
    $targetFull = [System.IO.Path]::GetFullPath($Path).TrimEnd($trimChars)
    $prefix = "$baseFull$([System.IO.Path]::DirectorySeparatorChar)"

    if (-not $targetFull.Equals($baseFull, [System.StringComparison]::OrdinalIgnoreCase) -and
        -not $targetFull.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "InstallRoot must be under $baseFull. Refusing to use: $targetFull"
    }

    $targetFull
}

function Write-Step([string]$text) {
    Write-Host ""
    Write-Host "== $text ==" -ForegroundColor Cyan
}

function Confirm-Step([string]$question, [bool]$defaultYes = $true) {
    if ($NoPrompt) {
        return $defaultYes
    }

    $suffix = if ($defaultYes) { "[Y/n]" } else { "[y/N]" }
    $answer = Read-Host "$question $suffix"
    if ([string]::IsNullOrWhiteSpace($answer)) {
        return $defaultYes
    }

    return $answer -match "^(y|yes)$"
}

function Test-Admin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Remove-AppShortcuts {
    $programs = [Environment]::GetFolderPath("Programs")
    $desktop = [Environment]::GetFolderPath("DesktopDirectory")
    $folder = Join-Path $programs "Studio Display XDR"
    $desktopShortcut = Join-Path $desktop "Studio Display XDR.lnk"

    foreach ($path in @($desktopShortcut, (Join-Path $folder "Studio Display XDR.lnk"), (Join-Path $folder "Studio Display XDR Support Report.lnk"), (Join-Path $folder "Studio Display XDR Check Status.lnk"), (Join-Path $folder "Studio Display XDR Check Ambient.lnk"), (Join-Path $folder "Studio Display XDR Check Color.lnk"))) {
        if (Test-Path -LiteralPath $path) {
            Remove-Item -LiteralPath $path -Force
            Write-Host "Removed $path"
        }
    }

    if (Test-Path -LiteralPath $folder) {
        $remaining = @(Get-ChildItem -LiteralPath $folder -Force)
        if ($remaining.Count -eq 0) {
            Remove-Item -LiteralPath $folder -Force
            Write-Host "Removed $folder"
        }
    }
}

function Remove-StartupEntry {
    $runKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run"
    if (Test-Path -LiteralPath $runKey) {
        Remove-ItemProperty -LiteralPath $runKey -Name "StudioDisplayXdr" -ErrorAction SilentlyContinue
        Write-Host "Removed HKCU startup entry StudioDisplayXdr if present."
    }
}

function Remove-InstalledAppPackage {
    param([string]$InstallRoot)

    $targetFull = Assert-SafeInstallRoot -Path $InstallRoot
    if (-not (Test-Path -LiteralPath $targetFull)) {
        Write-Host "Installed app folder not found: $targetFull"
        return
    }

    Remove-Item -LiteralPath $targetFull -Recurse -Force
    Write-Host "Removed $targetFull"
}

function Remove-GeneratedColorProfile {
    param([bool]$DeleteFile)

    $source = @"
using System;
using System.ComponentModel;
using System.Runtime.InteropServices;

public static class StudioXdrColorProfileRemoval
{
    const uint QDC_ONLY_ACTIVE_PATHS = 0x00000002;
    const int ERROR_SUCCESS = 0;
    const uint ScopeCurrentUser = 0;

    enum InfoType : uint
    {
        GetSourceName = 1,
        GetTargetName = 2
    }

    [StructLayout(LayoutKind.Sequential)] public struct LUID { public uint LowPart; public int HighPart; }
    [StructLayout(LayoutKind.Sequential)] struct Rational { public uint Numerator; public uint Denominator; }
    [StructLayout(LayoutKind.Sequential)] struct PathSourceInfo { public LUID adapterId; public uint id; public uint modeInfoIdx; public uint statusFlags; }
    [StructLayout(LayoutKind.Sequential)] struct PathTargetInfo { public LUID adapterId; public uint id; public uint modeInfoIdx; public uint outputTechnology; public uint rotation; public uint scaling; public Rational refreshRate; public uint scanLineOrdering; [MarshalAs(UnmanagedType.Bool)] public bool targetAvailable; public uint statusFlags; }
    [StructLayout(LayoutKind.Sequential)] struct PathInfo { public PathSourceInfo sourceInfo; public PathTargetInfo targetInfo; public uint flags; }
    [StructLayout(LayoutKind.Sequential)] struct ModeInfo { public uint infoType; public uint id; public LUID adapterId; public ulong a; public ulong b; public ulong c; public ulong d; public ulong e; }
    [StructLayout(LayoutKind.Sequential)] struct Header { public InfoType type; public uint size; public LUID adapterId; public uint id; }
    [StructLayout(LayoutKind.Sequential, CharSet=CharSet.Unicode)] struct SourceName { public Header header; [MarshalAs(UnmanagedType.ByValTStr, SizeConst=32)] public string viewGdiDeviceName; }
    [StructLayout(LayoutKind.Sequential, CharSet=CharSet.Unicode)] struct TargetName { public Header header; public uint flags; public uint outputTechnology; public ushort edidManufactureId; public ushort edidProductCodeId; public uint connectorInstance; [MarshalAs(UnmanagedType.ByValTStr, SizeConst=64)] public string monitorFriendlyDeviceName; [MarshalAs(UnmanagedType.ByValTStr, SizeConst=128)] public string monitorDevicePath; }

    public sealed class Target
    {
        public string GdiDeviceName;
        public LUID SourceAdapterId;
        public uint SourceId;
    }

    [DllImport("user32.dll")] static extern int GetDisplayConfigBufferSizes(uint flags, out uint pathCount, out uint modeCount);
    [DllImport("user32.dll")] static extern int QueryDisplayConfig(uint flags, ref uint pathCount, [Out] PathInfo[] paths, ref uint modeCount, [Out] ModeInfo[] modes, IntPtr topologyId);
    [DllImport("user32.dll")] static extern int DisplayConfigGetDeviceInfo(ref SourceName packet);
    [DllImport("user32.dll")] static extern int DisplayConfigGetDeviceInfo(ref TargetName packet);
    [DllImport("mscms.dll", CharSet=CharSet.Unicode)] static extern int ColorProfileRemoveDisplayAssociation(uint scope, string profileName, LUID targetAdapterID, uint sourceID, [MarshalAs(UnmanagedType.Bool)] bool dissociateAdvancedColor);
    [DllImport("mscms.dll", SetLastError=true, CharSet=CharSet.Unicode)] static extern bool DisassociateColorProfileFromDeviceW(string machineName, string profileName, string deviceName);
    [DllImport("mscms.dll", SetLastError=true, CharSet=CharSet.Unicode)] static extern bool UninstallColorProfileW(string machineName, string profileName, [MarshalAs(UnmanagedType.Bool)] bool deleteProfile);

    static Target FindStudioTarget()
    {
        uint pathCount, modeCount;
        int err = GetDisplayConfigBufferSizes(QDC_ONLY_ACTIVE_PATHS, out pathCount, out modeCount);
        if (err != ERROR_SUCCESS) return null;

        var paths = new PathInfo[pathCount];
        var modes = new ModeInfo[modeCount];
        err = QueryDisplayConfig(QDC_ONLY_ACTIVE_PATHS, ref pathCount, paths, ref modeCount, modes, IntPtr.Zero);
        if (err != ERROR_SUCCESS) return null;

        for (int i = 0; i < pathCount; i++)
        {
            var p = paths[i];

            var source = new SourceName();
            source.header.type = InfoType.GetSourceName;
            source.header.size = (uint)Marshal.SizeOf(typeof(SourceName));
            source.header.adapterId = p.sourceInfo.adapterId;
            source.header.id = p.sourceInfo.id;
            DisplayConfigGetDeviceInfo(ref source);

            var name = new TargetName();
            name.header.type = InfoType.GetTargetName;
            name.header.size = (uint)Marshal.SizeOf(typeof(TargetName));
            name.header.adapterId = p.targetInfo.adapterId;
            name.header.id = p.targetInfo.id;
            DisplayConfigGetDeviceInfo(ref name);

            string monitorName = name.monitorFriendlyDeviceName ?? "";
            string monitorPath = name.monitorDevicePath ?? "";
            if (monitorName.Contains("Studio") || monitorName.Contains("XDR") || monitorPath.Contains("AE42") || monitorPath.Contains("MS_0001"))
            {
                return new Target { GdiDeviceName = source.viewGdiDeviceName ?? "", SourceAdapterId = p.sourceInfo.adapterId, SourceId = p.sourceInfo.id };
            }
        }

        return null;
    }

    public static string Remove(string profileName, bool deleteFile)
    {
        var target = FindStudioTarget();
        var messages = new System.Collections.Generic.List<string>();

        if (target != null)
        {
            int normalHr = ColorProfileRemoveDisplayAssociation(ScopeCurrentUser, profileName, target.SourceAdapterId, target.SourceId, false);
            int advancedHr = ColorProfileRemoveDisplayAssociation(ScopeCurrentUser, profileName, target.SourceAdapterId, target.SourceId, true);
            messages.Add("ColorProfileRemoveDisplayAssociation(normal)=0x" + normalHr.ToString("X8"));
            messages.Add("ColorProfileRemoveDisplayAssociation(advanced)=0x" + advancedHr.ToString("X8"));

            if (!String.IsNullOrWhiteSpace(target.GdiDeviceName))
            {
                bool disassociated = DisassociateColorProfileFromDeviceW(null, profileName, target.GdiDeviceName);
                messages.Add("DisassociateColorProfileFromDevice=" + disassociated + " LastError=" + Marshal.GetLastWin32Error());
            }
        }
        else
        {
            messages.Add("No active Studio Display XDR target found for display association cleanup.");
        }

        bool uninstalled = UninstallColorProfileW(null, profileName, deleteFile);
        messages.Add("UninstallColorProfile(deleteFile=" + deleteFile + ")=" + uninstalled + " LastError=" + Marshal.GetLastWin32Error());
        return String.Join(Environment.NewLine, messages);
    }
}
"@

    if (-not ("StudioXdrColorProfileRemoval" -as [type])) {
        Add-Type -TypeDefinition $source
    }

    [StudioXdrColorProfileRemoval]::Remove("StudioDisplayXDR-DisplayP3.icm", $DeleteFile)
}

$repoRoot = Get-RepoRoot
Write-Host "Studio Display XDR Support Uninstaller" -ForegroundColor White

if (-not $KeepStartup -and (Confirm-Step "Remove Open at login startup entry?")) {
    Write-Step "Removing startup entry"
    Remove-StartupEntry
}

if (-not $KeepShortcuts -and (Confirm-Step "Remove Start Menu and Desktop shortcuts?")) {
    Write-Step "Removing shortcuts"
    Remove-AppShortcuts
}

if ($RemoveColorProfile -or (Confirm-Step "Remove generated Display P3 profile association?" $false)) {
    Write-Step "Removing generated Display P3 profile association"
    Remove-GeneratedColorProfile -DeleteFile:$RemoveProfileFile
}

if ($RemoveLibUsbFilter -or (Confirm-Step "Remove experimental libusb-win32 MI_08 filter? This requires administrator rights." $false)) {
    if (-not (Test-Admin)) {
        Write-Warning "Skipping libusb-win32 filter removal because this PowerShell session is not elevated."
    }
    else {
        Write-Step "Removing experimental libusb-win32 MI_08 filter"
        & (Join-Path $PSScriptRoot "Uninstall-StudioXdrLibUsbFilter.ps1") -Force
    }
}

if ($RemoveEdidOverride -or (Confirm-Step "Remove Studio Display XDR EDID override? This requires administrator rights." $false)) {
    if (-not (Test-Admin)) {
        Write-Warning "Skipping EDID override removal because this PowerShell session is not elevated."
    }
    else {
        Write-Step "Removing EDID override"
        & (Join-Path $PSScriptRoot "Uninstall-StudioXdrEdidOverride.ps1")
    }
}

$resolvedInstallRoot = Assert-SafeInstallRoot -Path $InstallRoot
if (-not $KeepInstalledApp -and (Test-Path -LiteralPath $resolvedInstallRoot) -and
    ($RemoveInstalledApp -or (Confirm-Step "Remove installed app files from $resolvedInstallRoot?" $true))) {
    Write-Step "Removing installed app files"
    Remove-InstalledAppPackage -InstallRoot $resolvedInstallRoot
}

Write-Host ""
Write-Host "Uninstall cleanup complete." -ForegroundColor Green
if (-not $NoPrompt) {
    Read-Host "Press Enter to close"
}
