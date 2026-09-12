using System.IO;
using System.ComponentModel;
using System.Runtime.InteropServices;

namespace StudioDisplayXdr.App;

internal static class StudioColorProfileController
{
    private const string ProfileFileName = "StudioDisplayXDR-DisplayP3.icm";
    private const uint QdcOnlyActivePaths = 0x00000002;
    private const int ErrorSuccess = 0;
    private const uint ScopeCurrentUser = 0;
    private const uint CptIcc = 0;
    private const uint CpstRgbWorkingSpace = 1;

    public static ColorProfileStatus GetStatus()
    {
        var bundledPath = GetBundledProfilePath();
        var installedPath = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.System), "spool", "drivers", "color", ProfileFileName);

        return new ColorProfileStatus(
            bundledPath,
            File.Exists(bundledPath),
            File.Exists(installedPath),
            installedPath);
    }

    public static string InstallBundledProfile()
    {
        var status = GetStatus();
        if (!status.BundledProfileExists)
        {
            return "Bundled Display P3 profile was not found.";
        }

        var target = FindStudioTarget();
        if (target is null)
        {
            return "No active Studio Display XDR target found.";
        }

        if (!InstallColorProfileW(null, status.BundledProfilePath))
        {
            throw new Win32Exception(Marshal.GetLastWin32Error(), "InstallColorProfileW failed");
        }

        var messages = new List<string>
        {
            $"Installed {ProfileFileName}."
        };

        var association = ColorProfileAddDisplayAssociation(ScopeCurrentUser, ProfileFileName, target.SourceAdapterId, target.SourceId, true, false);
        messages.Add($"Display association result: 0x{association:X8}.");

        if (!string.IsNullOrWhiteSpace(target.GdiDeviceName))
        {
            var associated = AssociateColorProfileWithDeviceW(null, ProfileFileName, target.GdiDeviceName);
            if (!associated)
            {
                messages.Add($"Legacy association result: {Marshal.GetLastWin32Error()}.");
            }

            var defaultSet = WcsSetDefaultColorProfile(ScopeCurrentUser, target.GdiDeviceName, CptIcc, CpstRgbWorkingSpace, 0, ProfileFileName);
            if (!defaultSet)
            {
                messages.Add($"Default profile result: {Marshal.GetLastWin32Error()}.");
            }
        }

        return string.Join(" ", messages);
    }

    private static string GetBundledProfilePath()
    {
        var candidates = new[]
        {
            Path.Combine(AppContext.BaseDirectory, "profiles", ProfileFileName),
            Path.Combine(AppContext.BaseDirectory, "..", "profiles", ProfileFileName),
            Path.Combine(AppContext.BaseDirectory, "..", "..", "profiles", ProfileFileName),
            Path.Combine(Environment.CurrentDirectory, "profiles", ProfileFileName)
        };

        foreach (var candidate in candidates)
        {
            var fullPath = Path.GetFullPath(candidate);
            if (File.Exists(fullPath))
            {
                return fullPath;
            }
        }

        return Path.GetFullPath(candidates[1]);
    }

    private static ColorTarget? FindStudioTarget()
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

            var monitorName = name.monitorFriendlyDeviceName ?? string.Empty;
            var monitorPath = name.monitorDevicePath ?? string.Empty;
            if (monitorName.Contains("Studio", StringComparison.OrdinalIgnoreCase)
                || monitorName.Contains("XDR", StringComparison.OrdinalIgnoreCase)
                || monitorPath.Contains("AE42", StringComparison.OrdinalIgnoreCase)
                || monitorPath.Contains("MS_0001", StringComparison.OrdinalIgnoreCase))
            {
                return new ColorTarget(source.viewGdiDeviceName ?? string.Empty, path.sourceInfo.adapterId, path.sourceInfo.id);
            }
        }

        return null;
    }

    private sealed record ColorTarget(string GdiDeviceName, DisplayConfigLuid SourceAdapterId, uint SourceId);

    private enum DisplayConfigDeviceInfoType : uint
    {
        GetSourceName = 1,
        GetTargetName = 2
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct Rational
    {
        public uint numerator;
        public uint denominator;
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
    private struct ModeInfo
    {
        public uint infoType;
        public uint id;
        public DisplayConfigLuid adapterId;
        public ulong a;
        public ulong b;
        public ulong c;
        public ulong d;
        public ulong e;
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

    [DllImport("user32.dll")]
    private static extern int GetDisplayConfigBufferSizes(uint flags, out uint pathCount, out uint modeCount);

    [DllImport("user32.dll")]
    private static extern int QueryDisplayConfig(uint flags, ref uint pathCount, [Out] PathInfo[] paths, ref uint modeCount, [Out] ModeInfo[] modes, IntPtr topologyId);

    [DllImport("user32.dll")]
    private static extern int DisplayConfigGetDeviceInfo(ref SourceName packet);

    [DllImport("user32.dll")]
    private static extern int DisplayConfigGetDeviceInfo(ref TargetName packet);

    [DllImport("mscms.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    private static extern bool InstallColorProfileW(string? machineName, string profileName);

    [DllImport("mscms.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    private static extern bool AssociateColorProfileWithDeviceW(string? machineName, string profileName, string deviceName);

    [DllImport("mscms.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    private static extern bool WcsSetDefaultColorProfile(uint scope, string deviceName, uint colorProfileType, uint colorProfileSubType, uint profileId, string profileName);

    [DllImport("mscms.dll", CharSet = CharSet.Unicode)]
    private static extern int ColorProfileAddDisplayAssociation(uint scope, string profileName, DisplayConfigLuid targetAdapterId, uint sourceId, [MarshalAs(UnmanagedType.Bool)] bool setAsDefault, [MarshalAs(UnmanagedType.Bool)] bool associateAsAdvancedColor);
}

internal sealed record ColorProfileStatus(
    string BundledProfilePath,
    bool BundledProfileExists,
    bool InstalledProfileExists,
    string InstalledProfilePath);
