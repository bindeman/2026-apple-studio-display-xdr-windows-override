param(
    [Parameter(Mandatory=$true)]
    [string]$ProfilePath,

    [switch]$AdvancedColor,
    [switch]$SystemWide
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path -LiteralPath $ProfilePath)) {
    throw "Profile not found: $ProfilePath"
}

$resolvedProfile = (Resolve-Path -LiteralPath $ProfilePath).Path
$profileName = Split-Path -Leaf $resolvedProfile

$source = @"
using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Runtime.InteropServices;

public static class StudioXdrColorProfileInstaller
{
    const uint QDC_ONLY_ACTIVE_PATHS = 0x00000002;
    const int ERROR_SUCCESS = 0;
    const uint ScopeCurrentUser = 0;
    const uint ScopeSystemWide = 1;
    const uint CptIcc = 0;
    const uint CpstRgbWorkingSpace = 1;

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
        public string MonitorName;
        public string MonitorPath;
        public string GdiDeviceName;
        public LUID SourceAdapterId;
        public uint SourceId;
    }

    [DllImport("user32.dll")] static extern int GetDisplayConfigBufferSizes(uint flags, out uint pathCount, out uint modeCount);
    [DllImport("user32.dll")] static extern int QueryDisplayConfig(uint flags, ref uint pathCount, [Out] PathInfo[] paths, ref uint modeCount, [Out] ModeInfo[] modes, IntPtr topologyId);
    [DllImport("user32.dll")] static extern int DisplayConfigGetDeviceInfo(ref SourceName packet);
    [DllImport("user32.dll")] static extern int DisplayConfigGetDeviceInfo(ref TargetName packet);
    [DllImport("mscms.dll", SetLastError=true, CharSet=CharSet.Unicode)] static extern bool InstallColorProfileW(string machineName, string profileName);
    [DllImport("mscms.dll", SetLastError=true, CharSet=CharSet.Unicode)] static extern bool AssociateColorProfileWithDeviceW(string machineName, string profileName, string deviceName);
    [DllImport("mscms.dll", SetLastError=true, CharSet=CharSet.Unicode)] static extern bool WcsSetDefaultColorProfile(uint scope, string deviceName, uint colorProfileType, uint colorProfileSubType, uint profileId, string profileName);
    [DllImport("mscms.dll", CharSet=CharSet.Unicode)] static extern int ColorProfileAddDisplayAssociation(uint scope, string profileName, LUID targetAdapterID, uint sourceID, [MarshalAs(UnmanagedType.Bool)] bool setAsDefault, [MarshalAs(UnmanagedType.Bool)] bool associateAsAdvancedColor);

    public static Target FindStudioTarget()
    {
        uint pathCount, modeCount;
        int err = GetDisplayConfigBufferSizes(QDC_ONLY_ACTIVE_PATHS, out pathCount, out modeCount);
        if (err != ERROR_SUCCESS) throw new InvalidOperationException("GetDisplayConfigBufferSizes failed: " + err);

        var paths = new PathInfo[pathCount];
        var modes = new ModeInfo[modeCount];
        err = QueryDisplayConfig(QDC_ONLY_ACTIVE_PATHS, ref pathCount, paths, ref modeCount, modes, IntPtr.Zero);
        if (err != ERROR_SUCCESS) throw new InvalidOperationException("QueryDisplayConfig failed: " + err);

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
                return new Target {
                    MonitorName = monitorName,
                    MonitorPath = monitorPath,
                    GdiDeviceName = source.viewGdiDeviceName ?? "",
                    SourceAdapterId = p.sourceInfo.adapterId,
                    SourceId = p.sourceInfo.id
                };
            }
        }

        return null;
    }

    public static string InstallAndAssociate(string sourceProfilePath, string installedProfileName, bool advancedColor, bool systemWide)
    {
        var target = FindStudioTarget();
        if (target == null) return "No active Studio Display XDR target found.";

        if (!InstallColorProfileW(null, sourceProfilePath))
        {
            throw new Win32Exception(Marshal.GetLastWin32Error(), "InstallColorProfileW failed");
        }

        var messages = new List<string>();
        uint scope = systemWide ? ScopeSystemWide : ScopeCurrentUser;

        int hr = ColorProfileAddDisplayAssociation(scope, installedProfileName, target.SourceAdapterId, target.SourceId, true, advancedColor);
        messages.Add("ColorProfileAddDisplayAssociation HRESULT=0x" + hr.ToString("X8"));

        if (!String.IsNullOrWhiteSpace(target.GdiDeviceName))
        {
            bool assoc = AssociateColorProfileWithDeviceW(null, installedProfileName, target.GdiDeviceName);
            messages.Add("AssociateColorProfileWithDevice(" + target.GdiDeviceName + ")=" + assoc + " LastError=" + Marshal.GetLastWin32Error());

            bool setDefault = WcsSetDefaultColorProfile(scope, target.GdiDeviceName, CptIcc, CpstRgbWorkingSpace, 0, installedProfileName);
            messages.Add("WcsSetDefaultColorProfile(" + target.GdiDeviceName + ")=" + setDefault + " LastError=" + Marshal.GetLastWin32Error());
        }

        messages.Insert(0, "Display=" + target.MonitorName + " GDI=" + target.GdiDeviceName + " Profile=" + installedProfileName + " AdvancedColor=" + advancedColor);
        return String.Join(Environment.NewLine, messages);
    }
}
"@

if (-not ("StudioXdrColorProfileInstaller" -as [type])) {
    Add-Type -TypeDefinition $source
}

[StudioXdrColorProfileInstaller]::InstallAndAssociate($resolvedProfile, $profileName, $AdvancedColor.IsPresent, $SystemWide.IsPresent)
