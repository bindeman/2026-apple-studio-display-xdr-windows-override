param(
    [int]$Width = 5120,
    [int]$Height = 2880,

    [ValidateSet(60,120)]
    [int]$RefreshRate = 120,

    [switch]$TestOnly
)

$ErrorActionPreference = "Stop"

$source = @"
using System;
using System.ComponentModel;
using System.Runtime.InteropServices;

public static class StudioXdrDisplayMode
{
    const uint QDC_ONLY_ACTIVE_PATHS = 0x00000002;
    const int ERROR_SUCCESS = 0;
    const int ENUM_CURRENT_SETTINGS = -1;
    const int DISP_CHANGE_SUCCESSFUL = 0;
    const uint CDS_UPDATEREGISTRY = 0x00000001;
    const uint CDS_TEST = 0x00000002;
    const uint DM_PELSWIDTH = 0x00080000;
    const uint DM_PELSHEIGHT = 0x00100000;
    const uint DM_DISPLAYFREQUENCY = 0x00400000;

    enum InfoType : uint
    {
        GetSourceName = 1,
        GetTargetName = 2
    }

    [StructLayout(LayoutKind.Sequential)] struct LUID { public uint LowPart; public int HighPart; }
    [StructLayout(LayoutKind.Sequential)] struct Rational { public uint Numerator; public uint Denominator; }
    [StructLayout(LayoutKind.Sequential)] struct PathSourceInfo { public LUID adapterId; public uint id; public uint modeInfoIdx; public uint statusFlags; }
    [StructLayout(LayoutKind.Sequential)] struct PathTargetInfo { public LUID adapterId; public uint id; public uint modeInfoIdx; public uint outputTechnology; public uint rotation; public uint scaling; public Rational refreshRate; public uint scanLineOrdering; [MarshalAs(UnmanagedType.Bool)] public bool targetAvailable; public uint statusFlags; }
    [StructLayout(LayoutKind.Sequential)] struct PathInfo { public PathSourceInfo sourceInfo; public PathTargetInfo targetInfo; public uint flags; }
    [StructLayout(LayoutKind.Sequential)] struct ModeInfo { public uint infoType; public uint id; public LUID adapterId; public ulong a; public ulong b; public ulong c; public ulong d; public ulong e; }
    [StructLayout(LayoutKind.Sequential)] struct Header { public InfoType type; public uint size; public LUID adapterId; public uint id; }
    [StructLayout(LayoutKind.Sequential, CharSet=CharSet.Unicode)] struct SourceName { public Header header; [MarshalAs(UnmanagedType.ByValTStr, SizeConst=32)] public string viewGdiDeviceName; }
    [StructLayout(LayoutKind.Sequential, CharSet=CharSet.Unicode)] struct TargetName { public Header header; public uint flags; public uint outputTechnology; public ushort edidManufactureId; public ushort edidProductCodeId; public uint connectorInstance; [MarshalAs(UnmanagedType.ByValTStr, SizeConst=64)] public string monitorFriendlyDeviceName; [MarshalAs(UnmanagedType.ByValTStr, SizeConst=128)] public string monitorDevicePath; }

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    struct DEVMODE
    {
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string dmDeviceName;
        public ushort dmSpecVersion;
        public ushort dmDriverVersion;
        public ushort dmSize;
        public ushort dmDriverExtra;
        public uint dmFields;
        public int dmPositionX;
        public int dmPositionY;
        public uint dmDisplayOrientation;
        public uint dmDisplayFixedOutput;
        public short dmColor;
        public short dmDuplex;
        public short dmYResolution;
        public short dmTTOption;
        public short dmCollate;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string dmFormName;
        public ushort dmLogPixels;
        public uint dmBitsPerPel;
        public uint dmPelsWidth;
        public uint dmPelsHeight;
        public uint dmDisplayFlags;
        public uint dmDisplayFrequency;
        public uint dmICMMethod;
        public uint dmICMIntent;
        public uint dmMediaType;
        public uint dmDitherType;
        public uint dmReserved1;
        public uint dmReserved2;
        public uint dmPanningWidth;
        public uint dmPanningHeight;
    }

    [DllImport("user32.dll")] static extern int GetDisplayConfigBufferSizes(uint flags, out uint pathCount, out uint modeCount);
    [DllImport("user32.dll")] static extern int QueryDisplayConfig(uint flags, ref uint pathCount, [Out] PathInfo[] paths, ref uint modeCount, [Out] ModeInfo[] modes, IntPtr topologyId);
    [DllImport("user32.dll")] static extern int DisplayConfigGetDeviceInfo(ref SourceName packet);
    [DllImport("user32.dll")] static extern int DisplayConfigGetDeviceInfo(ref TargetName packet);
    [DllImport("user32.dll", CharSet=CharSet.Unicode)] static extern bool EnumDisplaySettings(string deviceName, int modeNum, ref DEVMODE devMode);
    [DllImport("user32.dll", CharSet=CharSet.Unicode)] static extern int ChangeDisplaySettingsEx(string deviceName, ref DEVMODE devMode, IntPtr hwnd, uint flags, IntPtr lParam);

    public static string Set(int width, int height, int refreshRate, bool testOnly)
    {
        string display = FindStudioGdiDisplayName();
        if (String.IsNullOrWhiteSpace(display)) return "No active Studio Display XDR GDI display target found.";

        var mode = new DEVMODE();
        mode.dmSize = (ushort)Marshal.SizeOf(typeof(DEVMODE));
        if (!EnumDisplaySettings(display, ENUM_CURRENT_SETTINGS, ref mode))
        {
            throw new Win32Exception(Marshal.GetLastWin32Error(), "EnumDisplaySettings failed for " + display);
        }

        string before = String.Format("{0} current {1}x{2}@{3}Hz {4}bpp", display, mode.dmPelsWidth, mode.dmPelsHeight, mode.dmDisplayFrequency, mode.dmBitsPerPel);

        mode.dmFields = DM_PELSWIDTH | DM_PELSHEIGHT | DM_DISPLAYFREQUENCY;
        mode.dmPelsWidth = (uint)width;
        mode.dmPelsHeight = (uint)height;
        mode.dmDisplayFrequency = (uint)refreshRate;

        uint flags = testOnly ? CDS_TEST : CDS_UPDATEREGISTRY;
        int result = ChangeDisplaySettingsEx(display, ref mode, IntPtr.Zero, flags, IntPtr.Zero);
        string action = testOnly ? "test" : "apply";
        string status = result == DISP_CHANGE_SUCCESSFUL ? "success" : "failed";
        return String.Format("{0}; requested {1}x{2}@{3}Hz; {4} {5}; result={6}", before, width, height, refreshRate, action, status, result);
    }

    static string FindStudioGdiDisplayName()
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
                return source.viewGdiDeviceName;
            }
        }

        return null;
    }
}
"@

if (-not ("StudioXdrDisplayMode" -as [type])) {
    Add-Type -TypeDefinition $source
}

[StudioXdrDisplayMode]::Set($Width, $Height, $RefreshRate, $TestOnly.IsPresent)
