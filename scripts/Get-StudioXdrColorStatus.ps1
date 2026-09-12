$ErrorActionPreference = "Stop"

$source = @"
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;

public static class StudioXdrColorStatus
{
    const uint QDC_ONLY_ACTIVE_PATHS = 0x00000002;
    const int ERROR_SUCCESS = 0;

    enum InfoType : uint
    {
        GetSourceName = 1,
        GetTargetName = 2,
        GetAdvancedColorInfo = 9
    }

    [StructLayout(LayoutKind.Sequential)] struct LUID { public uint LowPart; public int HighPart; public override string ToString() { return HighPart.ToString("X8") + ":" + LowPart.ToString("X8"); } }
    [StructLayout(LayoutKind.Sequential)] struct Rational { public uint Numerator; public uint Denominator; }
    [StructLayout(LayoutKind.Sequential)] struct Region { public uint cx; public uint cy; }
    [StructLayout(LayoutKind.Sequential)] struct PointL { public int x; public int y; }
    [StructLayout(LayoutKind.Sequential)] struct PathSourceInfo { public LUID adapterId; public uint id; public uint modeInfoIdx; public uint statusFlags; }
    [StructLayout(LayoutKind.Sequential)] struct PathTargetInfo { public LUID adapterId; public uint id; public uint modeInfoIdx; public uint outputTechnology; public uint rotation; public uint scaling; public Rational refreshRate; public uint scanLineOrdering; [MarshalAs(UnmanagedType.Bool)] public bool targetAvailable; public uint statusFlags; }
    [StructLayout(LayoutKind.Sequential)] struct PathInfo { public PathSourceInfo sourceInfo; public PathTargetInfo targetInfo; public uint flags; }
    [StructLayout(LayoutKind.Sequential)] struct SourceMode { public uint width; public uint height; public uint pixelFormat; public PointL position; }
    [StructLayout(LayoutKind.Sequential)] struct VideoSignalInfo { public ulong pixelRate; public Rational hSyncFreq; public Rational vSyncFreq; public Region activeSize; public Region totalSize; public uint videoStandard; public uint scanLineOrdering; }
    [StructLayout(LayoutKind.Sequential)] struct TargetMode { public VideoSignalInfo targetVideoSignalInfo; }
    [StructLayout(LayoutKind.Explicit)] struct ModeUnion { [FieldOffset(0)] public TargetMode targetMode; [FieldOffset(0)] public SourceMode sourceMode; }
    [StructLayout(LayoutKind.Sequential)] struct ModeInfo { public uint infoType; public uint id; public LUID adapterId; public ModeUnion modeInfo; }
    [StructLayout(LayoutKind.Sequential)] struct Header { public InfoType type; public uint size; public LUID adapterId; public uint id; }
    [StructLayout(LayoutKind.Sequential, CharSet=CharSet.Unicode)] struct SourceName { public Header header; [MarshalAs(UnmanagedType.ByValTStr, SizeConst=32)] public string viewGdiDeviceName; }
    [StructLayout(LayoutKind.Sequential, CharSet=CharSet.Unicode)] struct TargetName { public Header header; public uint flags; public uint outputTechnology; public ushort edidManufactureId; public ushort edidProductCodeId; public uint connectorInstance; [MarshalAs(UnmanagedType.ByValTStr, SizeConst=64)] public string monitorFriendlyDeviceName; [MarshalAs(UnmanagedType.ByValTStr, SizeConst=128)] public string monitorDevicePath; }
    [StructLayout(LayoutKind.Sequential)] struct AdvancedColorInfo { public Header header; public uint value; public uint colorEncoding; public uint bitsPerColorChannel; }

    [DllImport("user32.dll")] static extern int GetDisplayConfigBufferSizes(uint flags, out uint pathCount, out uint modeCount);
    [DllImport("user32.dll")] static extern int QueryDisplayConfig(uint flags, ref uint pathCount, [Out] PathInfo[] paths, ref uint modeCount, [Out] ModeInfo[] modes, IntPtr topologyId);
    [DllImport("user32.dll")] static extern int DisplayConfigGetDeviceInfo(ref SourceName packet);
    [DllImport("user32.dll")] static extern int DisplayConfigGetDeviceInfo(ref TargetName packet);
    [DllImport("user32.dll")] static extern int DisplayConfigGetDeviceInfo(ref AdvancedColorInfo packet);

    public sealed class DisplayTarget
    {
        public string MonitorName;
        public string MonitorPath;
        public string GdiDeviceName;
        public string SourceAdapterLuid;
        public uint SourceId;
        public string TargetAdapterLuid;
        public uint TargetId;
        public uint AdvancedColorRaw;
        public bool AdvancedColorSupported;
        public bool AdvancedColorEnabled;
        public uint BitsPerColorChannel;
        public uint ColorEncoding;
        public uint SourceWidth;
        public uint SourceHeight;
        public uint TargetActiveWidth;
        public uint TargetActiveHeight;
        public double TargetRefreshHz;
        public double PixelClockMHz;
    }

    public static DisplayTarget[] GetTargets()
    {
        uint pathCount, modeCount;
        int err = GetDisplayConfigBufferSizes(QDC_ONLY_ACTIVE_PATHS, out pathCount, out modeCount);
        if (err != ERROR_SUCCESS) throw new InvalidOperationException("GetDisplayConfigBufferSizes failed: " + err);

        var paths = new PathInfo[pathCount];
        var modes = new ModeInfo[modeCount];
        err = QueryDisplayConfig(QDC_ONLY_ACTIVE_PATHS, ref pathCount, paths, ref modeCount, modes, IntPtr.Zero);
        if (err != ERROR_SUCCESS) throw new InvalidOperationException("QueryDisplayConfig failed: " + err);

        var targets = new List<DisplayTarget>();
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

            var info = new AdvancedColorInfo();
            info.header.type = InfoType.GetAdvancedColorInfo;
            info.header.size = (uint)Marshal.SizeOf(typeof(AdvancedColorInfo));
            info.header.adapterId = p.targetInfo.adapterId;
            info.header.id = p.targetInfo.id;
            DisplayConfigGetDeviceInfo(ref info);

            uint sourceWidth = 0;
            uint sourceHeight = 0;
            uint targetActiveWidth = 0;
            uint targetActiveHeight = 0;
            double targetRefresh = 0;
            double pixelClock = 0;

            if (p.sourceInfo.modeInfoIdx != UInt32.MaxValue && p.sourceInfo.modeInfoIdx < modeCount)
            {
                var sourceMode = modes[p.sourceInfo.modeInfoIdx].modeInfo.sourceMode;
                sourceWidth = sourceMode.width;
                sourceHeight = sourceMode.height;
            }

            if (p.targetInfo.modeInfoIdx != UInt32.MaxValue && p.targetInfo.modeInfoIdx < modeCount)
            {
                var signal = modes[p.targetInfo.modeInfoIdx].modeInfo.targetMode.targetVideoSignalInfo;
                targetActiveWidth = signal.activeSize.cx;
                targetActiveHeight = signal.activeSize.cy;
                targetRefresh = Ratio(signal.vSyncFreq);
                pixelClock = Math.Round(signal.pixelRate / 1000000.0, 3);
            }

            targets.Add(new DisplayTarget {
                MonitorName = name.monitorFriendlyDeviceName ?? "",
                MonitorPath = name.monitorDevicePath ?? "",
                GdiDeviceName = source.viewGdiDeviceName ?? "",
                SourceAdapterLuid = p.sourceInfo.adapterId.ToString(),
                SourceId = p.sourceInfo.id,
                TargetAdapterLuid = p.targetInfo.adapterId.ToString(),
                TargetId = p.targetInfo.id,
                AdvancedColorRaw = info.value,
                AdvancedColorSupported = (info.value & 0x1) != 0,
                AdvancedColorEnabled = (info.value & 0x2) != 0,
                BitsPerColorChannel = info.bitsPerColorChannel,
                ColorEncoding = info.colorEncoding,
                SourceWidth = sourceWidth,
                SourceHeight = sourceHeight,
                TargetActiveWidth = targetActiveWidth,
                TargetActiveHeight = targetActiveHeight,
                TargetRefreshHz = targetRefresh,
                PixelClockMHz = pixelClock
            });
        }

        return targets.ToArray();
    }

    static double Ratio(Rational rational)
    {
        if (rational.Denominator == 0) return 0;
        return Math.Round((double)rational.Numerator / rational.Denominator, 3);
    }
}
"@

if (-not ("StudioXdrColorStatus" -as [type])) {
    Add-Type -TypeDefinition $source
}

Write-Host "== Active Studio Display XDR DisplayConfig targets =="
$targets = [StudioXdrColorStatus]::GetTargets() |
    Where-Object { $_.MonitorName -match "Studio|XDR|Apple" -or $_.MonitorPath -match "APP|AE42|MS_0001|Studio" }

if (-not $targets) {
    Write-Host "No active Studio Display XDR target found."
}
else {
    $targets | Format-List MonitorName,MonitorPath,GdiDeviceName,SourceAdapterLuid,SourceId,SourceWidth,SourceHeight,TargetAdapterLuid,TargetId,TargetActiveWidth,TargetActiveHeight,TargetRefreshHz,PixelClockMHz,AdvancedColorSupported,AdvancedColorEnabled,BitsPerColorChannel,ColorEncoding,AdvancedColorRaw
}

Write-Host ""
Write-Host "== Installed Apple / Studio / P3 / XDR color profiles =="
$colorDir = Join-Path $env:WINDIR "System32\spool\drivers\color"
Get-ChildItem -LiteralPath $colorDir -File |
    Where-Object { $_.Name -match "Apple|Studio|Display|XDR|P3|Adobe|BT2020|HDR" } |
    Select-Object Name,Length,LastWriteTime |
    Sort-Object Name |
    Format-Table -AutoSize
