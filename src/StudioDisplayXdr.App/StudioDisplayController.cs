using System.ComponentModel;
using System.Runtime.InteropServices;

namespace StudioDisplayXdr.App;

[StructLayout(LayoutKind.Sequential)]
internal struct DisplayConfigLuid
{
    public uint lowPart;
    public int highPart;
}

internal sealed record StudioDisplayStatus(
    string MonitorName,
    string MonitorPath,
    string GdiDeviceName,
    uint SourceWidth,
    uint SourceHeight,
    uint TargetActiveWidth,
    uint TargetActiveHeight,
    double TargetRefreshHz,
    double PixelClockMHz,
    bool AdvancedColorSupported,
    bool AdvancedColorEnabled,
    uint BitsPerColorChannel,
    uint ColorEncoding,
    DisplayConfigLuid AdapterId,
    uint TargetId);

internal static class StudioDisplayController
{
    private const uint QdcOnlyActivePaths = 0x00000002;
    private const int ErrorSuccess = 0;
    private const int EnumCurrentSettings = -1;
    private const int DispChangeSuccessful = 0;
    private const uint CdsUpdateRegistry = 0x00000001;
    private const uint DmPelsWidth = 0x00080000;
    private const uint DmPelsHeight = 0x00100000;
    private const uint DmDisplayFrequency = 0x00400000;
    private const uint NativeWidth = 5120;
    private const uint NativeHeight = 2880;

    public static StudioDisplayStatus? GetStatus()
    {
        return GetActiveTargets().FirstOrDefault(IsStudioTarget);
    }

    public static string SetRefreshRate(int refreshRate)
    {
        return SetNativeRefreshRate(refreshRate);
    }

    public static string Optimize()
    {
        var messages = new List<string>
        {
            SetNativeRefreshRate(120)
        };

        var target = GetStatus();
        if (target is null)
        {
            messages.Add("No active Studio Display XDR target found for HDR.");
        }
        else if (!target.AdvancedColorSupported)
        {
            messages.Add("HDR is not reported as supported for the active signal.");
        }
        else if (target.AdvancedColorEnabled)
        {
            messages.Add("HDR is already on.");
        }
        else
        {
            messages.Add(SetAdvancedColor(true));
        }

        return string.Join(" ", messages);
    }

    private static string SetNativeRefreshRate(int refreshRate)
    {
        var target = GetStatus();
        if (target is null || string.IsNullOrWhiteSpace(target.GdiDeviceName))
        {
            return "No active Studio Display XDR target found.";
        }

        var mode = new DevMode
        {
            dmSize = (ushort)Marshal.SizeOf<DevMode>()
        };

        if (!EnumDisplaySettings(target.GdiDeviceName, EnumCurrentSettings, ref mode))
        {
            throw new Win32Exception(Marshal.GetLastWin32Error(), $"Could not read current display mode for {target.GdiDeviceName}");
        }

        var before = $"{mode.dmPelsWidth} x {mode.dmPelsHeight} @ {mode.dmDisplayFrequency} Hz";
        mode.dmFields = DmPelsWidth | DmPelsHeight | DmDisplayFrequency;
        mode.dmPelsWidth = NativeWidth;
        mode.dmPelsHeight = NativeHeight;
        mode.dmDisplayFrequency = (uint)refreshRate;

        var result = ChangeDisplaySettingsEx(target.GdiDeviceName, ref mode, IntPtr.Zero, CdsUpdateRegistry, IntPtr.Zero);
        if (result != DispChangeSuccessful)
        {
            return $"Windows rejected {NativeWidth} x {NativeHeight} @ {refreshRate} Hz. Result: {result}.";
        }

        return $"Changed from {before} to {NativeWidth} x {NativeHeight} @ {refreshRate} Hz.";
    }

    public static string SetAdvancedColor(bool enabled)
    {
        var target = GetStatus();
        if (target is null)
        {
            return "No active Studio Display XDR target found.";
        }

        if (!target.AdvancedColorSupported)
        {
            return "HDR is not reported as supported for the active Studio Display XDR signal.";
        }

        var state = new AdvancedColorState
        {
            header =
            {
                type = DisplayConfigDeviceInfoType.SetAdvancedColorState,
                size = (uint)Marshal.SizeOf<AdvancedColorState>(),
                adapterId = target.AdapterId,
                id = target.TargetId
            },
            value = enabled ? 1u : 0u
        };

        var result = DisplayConfigSetDeviceInfo(ref state);
        if (result != ErrorSuccess)
        {
            return $"Windows rejected the HDR change. Result: {result}.";
        }

        return enabled ? "HDR is on." : "HDR is off.";
    }

    private static List<StudioDisplayStatus> GetActiveTargets()
    {
        var err = GetDisplayConfigBufferSizes(QdcOnlyActivePaths, out var pathCount, out var modeCount);
        if (err != ErrorSuccess)
        {
            throw new InvalidOperationException($"GetDisplayConfigBufferSizes failed: {err}");
        }

        var paths = new PathInfo[pathCount];
        var modes = new ModeInfo[modeCount];
        err = QueryDisplayConfig(QdcOnlyActivePaths, ref pathCount, paths, ref modeCount, modes, IntPtr.Zero);
        if (err != ErrorSuccess)
        {
            throw new InvalidOperationException($"QueryDisplayConfig failed: {err}");
        }

        var targets = new List<StudioDisplayStatus>();
        for (var i = 0; i < pathCount; i++)
        {
            var path = paths[i];

            var source = new SourceName
            {
                header =
                {
                    type = DisplayConfigDeviceInfoType.GetSourceName,
                    size = (uint)Marshal.SizeOf<SourceName>(),
                    adapterId = path.sourceInfo.adapterId,
                    id = path.sourceInfo.id
                }
            };
            DisplayConfigGetDeviceInfo(ref source);

            var name = new TargetName
            {
                header =
                {
                    type = DisplayConfigDeviceInfoType.GetTargetName,
                    size = (uint)Marshal.SizeOf<TargetName>(),
                    adapterId = path.targetInfo.adapterId,
                    id = path.targetInfo.id
                }
            };
            DisplayConfigGetDeviceInfo(ref name);

            var color = new AdvancedColorInfo
            {
                header =
                {
                    type = DisplayConfigDeviceInfoType.GetAdvancedColorInfo,
                    size = (uint)Marshal.SizeOf<AdvancedColorInfo>(),
                    adapterId = path.targetInfo.adapterId,
                    id = path.targetInfo.id
                }
            };
            DisplayConfigGetDeviceInfo(ref color);

            uint sourceWidth = 0;
            uint sourceHeight = 0;
            uint targetWidth = 0;
            uint targetHeight = 0;
            double refresh = 0;
            double pixelClock = 0;

            if (path.sourceInfo.modeInfoIdx != uint.MaxValue && path.sourceInfo.modeInfoIdx < modeCount)
            {
                var sourceMode = modes[path.sourceInfo.modeInfoIdx].modeInfo.sourceMode;
                sourceWidth = sourceMode.width;
                sourceHeight = sourceMode.height;
            }

            if (path.targetInfo.modeInfoIdx != uint.MaxValue && path.targetInfo.modeInfoIdx < modeCount)
            {
                var signal = modes[path.targetInfo.modeInfoIdx].modeInfo.targetMode.targetVideoSignalInfo;
                targetWidth = signal.activeSize.cx;
                targetHeight = signal.activeSize.cy;
                refresh = Ratio(signal.vSyncFreq);
                pixelClock = Math.Round(signal.pixelRate / 1_000_000.0, 3);
            }

            targets.Add(new StudioDisplayStatus(
                name.monitorFriendlyDeviceName ?? string.Empty,
                name.monitorDevicePath ?? string.Empty,
                source.viewGdiDeviceName ?? string.Empty,
                sourceWidth,
                sourceHeight,
                targetWidth,
                targetHeight,
                refresh,
                pixelClock,
                (color.value & 0x1) != 0,
                (color.value & 0x2) != 0,
                color.bitsPerColorChannel,
                color.colorEncoding,
                path.targetInfo.adapterId,
                path.targetInfo.id));
        }

        return targets;
    }

    private static bool IsStudioTarget(StudioDisplayStatus target)
    {
        return target.MonitorName.Contains("Studio", StringComparison.OrdinalIgnoreCase)
            || target.MonitorName.Contains("XDR", StringComparison.OrdinalIgnoreCase)
            || target.MonitorPath.Contains("AE42", StringComparison.OrdinalIgnoreCase)
            || target.MonitorPath.Contains("MS_0001", StringComparison.OrdinalIgnoreCase)
            || target.MonitorPath.Contains("APP", StringComparison.OrdinalIgnoreCase);
    }

    private static double Ratio(Rational rational)
    {
        if (rational.denominator == 0)
        {
            return 0;
        }

        return Math.Round((double)rational.numerator / rational.denominator, 3);
    }

    private enum DisplayConfigDeviceInfoType : uint
    {
        GetSourceName = 1,
        GetTargetName = 2,
        GetAdvancedColorInfo = 9,
        SetAdvancedColorState = 10
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct Rational
    {
        public uint numerator;
        public uint denominator;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct Region
    {
        public uint cx;
        public uint cy;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct PointL
    {
        public int x;
        public int y;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct PathSourceInfo
    {
        public DisplayConfigLuid adapterId;
        public uint id;
        public uint modeInfoIdx;
        public uint statusFlags;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct PathTargetInfo
    {
        public DisplayConfigLuid adapterId;
        public uint id;
        public uint modeInfoIdx;
        public uint outputTechnology;
        public uint rotation;
        public uint scaling;
        public Rational refreshRate;
        public uint scanLineOrdering;
        [MarshalAs(UnmanagedType.Bool)] public bool targetAvailable;
        public uint statusFlags;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct PathInfo
    {
        public PathSourceInfo sourceInfo;
        public PathTargetInfo targetInfo;
        public uint flags;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct SourceMode
    {
        public uint width;
        public uint height;
        public uint pixelFormat;
        public PointL position;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct VideoSignalInfo
    {
        public ulong pixelRate;
        public Rational hSyncFreq;
        public Rational vSyncFreq;
        public Region activeSize;
        public Region totalSize;
        public uint videoStandard;
        public uint scanLineOrdering;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct TargetMode
    {
        public VideoSignalInfo targetVideoSignalInfo;
    }

    [StructLayout(LayoutKind.Explicit)]
    private struct ModeUnion
    {
        [FieldOffset(0)] public TargetMode targetMode;
        [FieldOffset(0)] public SourceMode sourceMode;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct ModeInfo
    {
        public uint infoType;
        public uint id;
        public DisplayConfigLuid adapterId;
        public ModeUnion modeInfo;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct DeviceInfoHeader
    {
        public DisplayConfigDeviceInfoType type;
        public uint size;
        public DisplayConfigLuid adapterId;
        public uint id;
    }

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    private struct SourceName
    {
        public DeviceInfoHeader header;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string viewGdiDeviceName;
    }

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    private struct TargetName
    {
        public DeviceInfoHeader header;
        public uint flags;
        public uint outputTechnology;
        public ushort edidManufactureId;
        public ushort edidProductCodeId;
        public uint connectorInstance;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 64)] public string monitorFriendlyDeviceName;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)] public string monitorDevicePath;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct AdvancedColorInfo
    {
        public DeviceInfoHeader header;
        public uint value;
        public uint colorEncoding;
        public uint bitsPerColorChannel;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct AdvancedColorState
    {
        public DeviceInfoHeader header;
        public uint value;
    }

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    private struct DevMode
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

    [DllImport("user32.dll")]
    private static extern int GetDisplayConfigBufferSizes(uint flags, out uint pathCount, out uint modeCount);

    [DllImport("user32.dll")]
    private static extern int QueryDisplayConfig(uint flags, ref uint pathCount, [Out] PathInfo[] paths, ref uint modeCount, [Out] ModeInfo[] modes, IntPtr topologyId);

    [DllImport("user32.dll")]
    private static extern int DisplayConfigGetDeviceInfo(ref SourceName packet);

    [DllImport("user32.dll")]
    private static extern int DisplayConfigGetDeviceInfo(ref TargetName packet);

    [DllImport("user32.dll")]
    private static extern int DisplayConfigGetDeviceInfo(ref AdvancedColorInfo packet);

    [DllImport("user32.dll")]
    private static extern int DisplayConfigSetDeviceInfo(ref AdvancedColorState packet);

    [DllImport("user32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern bool EnumDisplaySettings(string deviceName, int modeNum, ref DevMode devMode);

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    private static extern int ChangeDisplaySettingsEx(string deviceName, ref DevMode devMode, IntPtr hwnd, uint flags, IntPtr lParam);
}
