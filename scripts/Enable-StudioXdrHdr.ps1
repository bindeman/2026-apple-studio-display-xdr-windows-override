$ErrorActionPreference = "Stop"

$source = @"
using System;
using System.Runtime.InteropServices;

public static class StudioXdrHdr
{
    const uint QDC_ONLY_ACTIVE_PATHS = 0x00000002;
    const int ERROR_SUCCESS = 0;

    enum InfoType : uint
    {
        GetTargetName = 2,
        GetAdvancedColorInfo = 9,
        SetAdvancedColorState = 10
    }

    [StructLayout(LayoutKind.Sequential)] struct LUID { public uint LowPart; public int HighPart; }
    [StructLayout(LayoutKind.Sequential)] struct Rational { public uint Numerator; public uint Denominator; }
    [StructLayout(LayoutKind.Sequential)] struct PathSourceInfo { public LUID adapterId; public uint id; public uint modeInfoIdx; public uint statusFlags; }
    [StructLayout(LayoutKind.Sequential)] struct PathTargetInfo { public LUID adapterId; public uint id; public uint modeInfoIdx; public uint outputTechnology; public uint rotation; public uint scaling; public Rational refreshRate; public uint scanLineOrdering; [MarshalAs(UnmanagedType.Bool)] public bool targetAvailable; public uint statusFlags; }
    [StructLayout(LayoutKind.Sequential)] struct PathInfo { public PathSourceInfo sourceInfo; public PathTargetInfo targetInfo; public uint flags; }
    [StructLayout(LayoutKind.Sequential)] struct ModeInfo { public uint infoType; public uint id; public LUID adapterId; public ulong a; public ulong b; public ulong c; public ulong d; public ulong e; }
    [StructLayout(LayoutKind.Sequential)] struct Header { public InfoType type; public uint size; public LUID adapterId; public uint id; }
    [StructLayout(LayoutKind.Sequential, CharSet=CharSet.Unicode)] struct TargetName { public Header header; public uint flags; public uint outputTechnology; public ushort edidManufactureId; public ushort edidProductCodeId; public uint connectorInstance; [MarshalAs(UnmanagedType.ByValTStr, SizeConst=64)] public string monitorFriendlyDeviceName; [MarshalAs(UnmanagedType.ByValTStr, SizeConst=128)] public string monitorDevicePath; }
    [StructLayout(LayoutKind.Sequential)] struct AdvancedColorInfo { public Header header; public uint value; public uint colorEncoding; public uint bitsPerColorChannel; }
    [StructLayout(LayoutKind.Sequential)] struct AdvancedColorState { public Header header; public uint value; }

    [DllImport("user32.dll")] static extern int GetDisplayConfigBufferSizes(uint flags, out uint pathCount, out uint modeCount);
    [DllImport("user32.dll")] static extern int QueryDisplayConfig(uint flags, ref uint pathCount, [Out] PathInfo[] paths, ref uint modeCount, [Out] ModeInfo[] modes, IntPtr topologyId);
    [DllImport("user32.dll")] static extern int DisplayConfigGetDeviceInfo(ref TargetName packet);
    [DllImport("user32.dll")] static extern int DisplayConfigGetDeviceInfo(ref AdvancedColorInfo packet);
    [DllImport("user32.dll")] static extern int DisplayConfigSetDeviceInfo(ref AdvancedColorState packet);

    public static string Set(bool enable)
    {
        uint pathCount, modeCount;
        int err = GetDisplayConfigBufferSizes(QDC_ONLY_ACTIVE_PATHS, out pathCount, out modeCount);
        if (err != ERROR_SUCCESS) return "GetDisplayConfigBufferSizes failed: " + err;

        var paths = new PathInfo[pathCount];
        var modes = new ModeInfo[modeCount];
        err = QueryDisplayConfig(QDC_ONLY_ACTIVE_PATHS, ref pathCount, paths, ref modeCount, modes, IntPtr.Zero);
        if (err != ERROR_SUCCESS) return "QueryDisplayConfig failed: " + err;

        for (int i = 0; i < pathCount; i++)
        {
            var p = paths[i];
            var name = new TargetName();
            name.header.type = InfoType.GetTargetName;
            name.header.size = (uint)Marshal.SizeOf(typeof(TargetName));
            name.header.adapterId = p.targetInfo.adapterId;
            name.header.id = p.targetInfo.id;
            DisplayConfigGetDeviceInfo(ref name);
            if (name.monitorFriendlyDeviceName == null || !name.monitorFriendlyDeviceName.Contains("Studio")) continue;

            var state = new AdvancedColorState();
            state.header.type = InfoType.SetAdvancedColorState;
            state.header.size = (uint)Marshal.SizeOf(typeof(AdvancedColorState));
            state.header.adapterId = p.targetInfo.adapterId;
            state.header.id = p.targetInfo.id;
            state.value = enable ? 1u : 0u;
            err = DisplayConfigSetDeviceInfo(ref state);

            var info = new AdvancedColorInfo();
            info.header.type = InfoType.GetAdvancedColorInfo;
            info.header.size = (uint)Marshal.SizeOf(typeof(AdvancedColorInfo));
            info.header.adapterId = p.targetInfo.adapterId;
            info.header.id = p.targetInfo.id;
            int infoErr = DisplayConfigGetDeviceInfo(ref info);

            return String.Format("Display={0}; SetError={1}; InfoError={2}; Raw={3}; Supported={4}; Enabled={5}; BitsPerChannel={6}; ColorEncoding={7}",
                name.monitorFriendlyDeviceName,
                err,
                infoErr,
                info.value,
                (info.value & 0x1) != 0,
                (info.value & 0x2) != 0,
                info.bitsPerColorChannel,
                info.colorEncoding);
        }

        return "No active Studio display target found.";
    }
}
"@

Add-Type -TypeDefinition $source
[StudioXdrHdr]::Set($true)
