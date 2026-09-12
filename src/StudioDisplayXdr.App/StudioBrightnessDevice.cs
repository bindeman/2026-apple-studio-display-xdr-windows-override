using System.ComponentModel;
using System.Runtime.InteropServices;
using Microsoft.Win32;
using Microsoft.Win32.SafeHandles;

namespace StudioDisplayXdr.App;

internal sealed class StudioBrightnessDevice
{
    private const uint DigcfPresent = 0x00000002;
    private const uint DigcfDeviceInterface = 0x00000010;
    private const uint GenericRead = 0x80000000;
    private const uint GenericWrite = 0x40000000;
    private const uint FileShareRead = 0x00000001;
    private const uint FileShareWrite = 0x00000002;
    private const uint OpenExisting = 3;
    private const int HidpStatusSuccess = 0x00110000;
    private const string HidInterfaceGuid = "{4d1e55b2-f16f-11cf-88cb-001111000030}";

    private enum HidpReportType : short
    {
        Input = 0,
        Output = 1,
        Feature = 2
    }

    public string Path { get; private init; } = "";
    public uint CurrentValue { get; private init; }
    public int LogicalMin { get; private init; }
    public int LogicalMax { get; private init; }

    public int EffectiveMin => LogicalMax > LogicalMin ? LogicalMin : 0;
    public int EffectiveMax => LogicalMax > LogicalMin ? LogicalMax : 100000;

    public int Percent =>
        (int)Math.Round(((double)CurrentValue - EffectiveMin) * 100.0 / (EffectiveMax - EffectiveMin));

    public static StudioBrightnessDevice? Find()
    {
        return FindAll().FirstOrDefault();
    }

    public static IReadOnlyList<StudioBrightnessDevice> FindAll()
    {
        HidD_GetHidGuid(out var hidGuid);
        var set = SetupDiGetClassDevs(ref hidGuid, IntPtr.Zero, IntPtr.Zero, DigcfPresent | DigcfDeviceInterface);
        if (set == new IntPtr(-1))
        {
            throw new Win32Exception(Marshal.GetLastWin32Error(), "SetupDiGetClassDevs failed");
        }

        var found = new List<StudioBrightnessDevice>();
        var seenPaths = new HashSet<string>(StringComparer.OrdinalIgnoreCase);

        try
        {
            for (uint i = 0; ; i++)
            {
                var interfaceData = new SpDeviceInterfaceData
                {
                    CbSize = Marshal.SizeOf<SpDeviceInterfaceData>()
                };

                if (!SetupDiEnumDeviceInterfaces(set, IntPtr.Zero, ref hidGuid, i, ref interfaceData))
                {
                    if (Marshal.GetLastWin32Error() == 259)
                    {
                        break;
                    }

                    continue;
                }

                SetupDiGetDeviceInterfaceDetail(set, ref interfaceData, IntPtr.Zero, 0, out var requiredSize, IntPtr.Zero);
                var detail = Marshal.AllocHGlobal(requiredSize);
                try
                {
                    Marshal.WriteInt32(detail, IntPtr.Size == 8 ? 8 : 6);
                    if (!SetupDiGetDeviceInterfaceDetail(set, ref interfaceData, detail, requiredSize, out _, IntPtr.Zero))
                    {
                        continue;
                    }

                    var path = Marshal.PtrToStringUni(IntPtr.Add(detail, 4));
                    if (string.IsNullOrWhiteSpace(path))
                    {
                        continue;
                    }

                    var lower = path.ToLowerInvariant();
                    if (!lower.StartsWith(@"\\?\hid#") || !lower.Contains("vid_05ac") || !lower.Contains("pid_1116"))
                    {
                        continue;
                    }

                    var device = Probe(path);
                    if (device is not null)
                    {
                        AddIfNew(found, seenPaths, device);
                    }
                }
                finally
                {
                    Marshal.FreeHGlobal(detail);
                }
            }
        }
        finally
        {
            SetupDiDestroyDeviceInfoList(set);
        }

        if (found.Count == 0)
        {
            foreach (var device in FindFromRegistryFallback())
            {
                AddIfNew(found, seenPaths, device);
            }
        }

        return found;
    }

    private static List<StudioBrightnessDevice> FindFromRegistryFallback()
    {
        var found = new List<StudioBrightnessDevice>();
        using var hidKey = Registry.LocalMachine.OpenSubKey(@"SYSTEM\CurrentControlSet\Enum\HID");
        if (hidKey is null)
        {
            return found;
        }

        foreach (var deviceKeyName in hidKey.GetSubKeyNames())
        {
            if (!deviceKeyName.StartsWith("VID_05AC&PID_1116", StringComparison.OrdinalIgnoreCase))
            {
                continue;
            }

            using var deviceKey = hidKey.OpenSubKey(deviceKeyName);
            if (deviceKey is null)
            {
                continue;
            }

            foreach (var instanceKeyName in deviceKey.GetSubKeyNames())
            {
                var deviceId = $@"HID\{deviceKeyName}\{instanceKeyName}";
                var path = @"\\?\" + deviceId.ToLowerInvariant().Replace('\\', '#') + "#" + HidInterfaceGuid;
                var device = Probe(path);
                if (device is not null)
                {
                    found.Add(device);
                }
            }
        }

        return found;
    }

    private static void AddIfNew(List<StudioBrightnessDevice> devices, HashSet<string> seenPaths, StudioBrightnessDevice device)
    {
        if (seenPaths.Add(device.Path))
        {
            devices.Add(device);
        }
    }

    public static void SetPercent(string path, int percent)
    {
        var clamped = Math.Max(0, Math.Min(100, percent));
        SetBrightness(path, (uint)Math.Round(clamped * 1000.0));
    }

    private static StudioBrightnessDevice? Probe(string path)
    {
        using var handle = CreateFile(
            path,
            GenericRead | GenericWrite,
            FileShareRead | FileShareWrite,
            IntPtr.Zero,
            OpenExisting,
            0,
            IntPtr.Zero);

        if (handle.IsInvalid)
        {
            return null;
        }

        if (!HidD_GetPreparsedData(handle, out var preparsedData))
        {
            return null;
        }

        try
        {
            var status = HidP_GetCaps(preparsedData, out var caps);
            if (status != HidpStatusSuccess || caps.NumberFeatureValueCaps == 0)
            {
                return null;
            }

            var valueCaps = new HidpValueCaps[caps.NumberFeatureValueCaps];
            var count = caps.NumberFeatureValueCaps;
            status = HidP_GetValueCaps(HidpReportType.Feature, valueCaps, ref count, preparsedData);
            if (status != HidpStatusSuccess)
            {
                return null;
            }

            HidpValueCaps? chosen = null;
            for (var index = 0; index < count; index++)
            {
                var cap = valueCaps[index];
                var usage = cap.IsRange ? cap.UsageMin : cap.Usage;
                if (cap.UsagePage == 0x0082 && usage == 0x0010)
                {
                    chosen = cap;
                    break;
                }
            }

            if (chosen is null)
            {
                return null;
            }

            var brightnessCap = chosen.Value;
            var report = new byte[caps.FeatureReportByteLength];
            report[0] = brightnessCap.ReportId;
            if (!HidD_GetFeature(handle, report, report.Length))
            {
                return null;
            }

            var brightnessUsage = brightnessCap.IsRange ? brightnessCap.UsageMin : brightnessCap.Usage;
            status = HidP_GetUsageValue(
                HidpReportType.Feature,
                brightnessCap.UsagePage,
                0,
                brightnessUsage,
                out var currentValue,
                preparsedData,
                report,
                report.Length);

            if (status != HidpStatusSuccess)
            {
                return null;
            }

            return new StudioBrightnessDevice
            {
                Path = path,
                CurrentValue = currentValue,
                LogicalMin = brightnessCap.LogicalMin,
                LogicalMax = brightnessCap.LogicalMax
            };
        }
        finally
        {
            HidD_FreePreparsedData(preparsedData);
        }
    }

    private static void SetBrightness(string path, uint value)
    {
        using var handle = CreateFile(
            path,
            GenericRead | GenericWrite,
            FileShareRead | FileShareWrite,
            IntPtr.Zero,
            OpenExisting,
            0,
            IntPtr.Zero);

        if (handle.IsInvalid)
        {
            throw new Win32Exception(Marshal.GetLastWin32Error(), "CreateFile failed");
        }

        if (!HidD_GetPreparsedData(handle, out var preparsedData))
        {
            throw new Win32Exception(Marshal.GetLastWin32Error(), "HidD_GetPreparsedData failed");
        }

        try
        {
            var status = HidP_GetCaps(preparsedData, out var caps);
            if (status != HidpStatusSuccess)
            {
                throw new InvalidOperationException($"HidP_GetCaps failed: 0x{status:X8}");
            }

            var valueCaps = new HidpValueCaps[caps.NumberFeatureValueCaps];
            var count = caps.NumberFeatureValueCaps;
            status = HidP_GetValueCaps(HidpReportType.Feature, valueCaps, ref count, preparsedData);
            if (status != HidpStatusSuccess)
            {
                throw new InvalidOperationException($"HidP_GetValueCaps failed: 0x{status:X8}");
            }

            HidpValueCaps? chosen = null;
            for (var index = 0; index < count; index++)
            {
                var cap = valueCaps[index];
                var usage = cap.IsRange ? cap.UsageMin : cap.Usage;
                if (cap.UsagePage == 0x0082 && usage == 0x0010)
                {
                    chosen = cap;
                    break;
                }
            }

            if (chosen is null)
            {
                throw new InvalidOperationException("No Studio Display XDR brightness feature was found.");
            }

            var brightnessCap = chosen.Value;
            var report = new byte[caps.FeatureReportByteLength];
            report[0] = brightnessCap.ReportId;
            if (!HidD_GetFeature(handle, report, report.Length))
            {
                throw new Win32Exception(Marshal.GetLastWin32Error(), "HidD_GetFeature failed");
            }

            var brightnessUsage = brightnessCap.IsRange ? brightnessCap.UsageMin : brightnessCap.Usage;
            status = HidP_SetUsageValue(
                HidpReportType.Feature,
                brightnessCap.UsagePage,
                0,
                brightnessUsage,
                value,
                preparsedData,
                report,
                report.Length);

            if (status != HidpStatusSuccess)
            {
                throw new InvalidOperationException($"HidP_SetUsageValue failed: 0x{status:X8}");
            }

            if (!HidD_SetFeature(handle, report, report.Length))
            {
                throw new Win32Exception(Marshal.GetLastWin32Error(), "HidD_SetFeature failed");
            }
        }
        finally
        {
            HidD_FreePreparsedData(preparsedData);
        }
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct SpDeviceInterfaceData
    {
        public int CbSize;
        public Guid InterfaceClassGuid;
        public int Flags;
        public IntPtr Reserved;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct HidpCaps
    {
        public ushort Usage;
        public ushort UsagePage;
        public ushort InputReportByteLength;
        public ushort OutputReportByteLength;
        public ushort FeatureReportByteLength;

        [MarshalAs(UnmanagedType.ByValArray, SizeConst = 17)]
        public ushort[] Reserved;

        public ushort NumberLinkCollectionNodes;
        public ushort NumberInputButtonCaps;
        public ushort NumberInputValueCaps;
        public ushort NumberInputDataIndices;
        public ushort NumberOutputButtonCaps;
        public ushort NumberOutputValueCaps;
        public ushort NumberOutputDataIndices;
        public ushort NumberFeatureButtonCaps;
        public ushort NumberFeatureValueCaps;
        public ushort NumberFeatureDataIndices;
    }

    [StructLayout(LayoutKind.Explicit)]
    private struct HidpValueCaps
    {
        [FieldOffset(0)] public ushort UsagePage;
        [FieldOffset(2)] public byte ReportId;
        [FieldOffset(3)] [MarshalAs(UnmanagedType.U1)] public bool IsAlias;
        [FieldOffset(4)] public ushort BitField;
        [FieldOffset(6)] public ushort LinkCollection;
        [FieldOffset(8)] public ushort LinkUsage;
        [FieldOffset(10)] public ushort LinkUsagePage;
        [FieldOffset(12)] [MarshalAs(UnmanagedType.U1)] public bool IsRange;
        [FieldOffset(13)] [MarshalAs(UnmanagedType.U1)] public bool IsStringRange;
        [FieldOffset(14)] [MarshalAs(UnmanagedType.U1)] public bool IsDesignatorRange;
        [FieldOffset(15)] [MarshalAs(UnmanagedType.U1)] public bool IsAbsolute;
        [FieldOffset(56)] public ushort UsageMin;
        [FieldOffset(58)] public ushort UsageMax;
        [FieldOffset(56)] public ushort Usage;
        [FieldOffset(72)] public ushort BitSize;
        [FieldOffset(74)] public ushort ReportCount;
        [FieldOffset(88)] public uint UnitsExp;
        [FieldOffset(92)] public uint Units;
        [FieldOffset(96)] public int LogicalMin;
        [FieldOffset(100)] public int LogicalMax;
        [FieldOffset(104)] public int PhysicalMin;
        [FieldOffset(108)] public int PhysicalMax;
    }

    [DllImport("hid.dll")]
    private static extern void HidD_GetHidGuid(out Guid hidGuid);

    [DllImport("setupapi.dll", SetLastError = true)]
    private static extern IntPtr SetupDiGetClassDevs(ref Guid classGuid, IntPtr enumerator, IntPtr hwndParent, uint flags);

    [DllImport("setupapi.dll", SetLastError = true)]
    private static extern bool SetupDiEnumDeviceInterfaces(IntPtr deviceInfoSet, IntPtr deviceInfoData, ref Guid interfaceClassGuid, uint memberIndex, ref SpDeviceInterfaceData deviceInterfaceData);

    [DllImport("setupapi.dll", SetLastError = true)]
    private static extern bool SetupDiGetDeviceInterfaceDetail(IntPtr deviceInfoSet, ref SpDeviceInterfaceData deviceInterfaceData, IntPtr deviceInterfaceDetailData, int deviceInterfaceDetailDataSize, out int requiredSize, IntPtr deviceInfoData);

    [DllImport("setupapi.dll", SetLastError = true)]
    private static extern bool SetupDiDestroyDeviceInfoList(IntPtr deviceInfoSet);

    [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    private static extern SafeFileHandle CreateFile(string fileName, uint desiredAccess, uint shareMode, IntPtr securityAttributes, uint creationDisposition, uint flagsAndAttributes, IntPtr templateFile);

    [DllImport("hid.dll", SetLastError = true)]
    private static extern bool HidD_GetPreparsedData(SafeFileHandle hidDeviceObject, out IntPtr preparsedData);

    [DllImport("hid.dll", SetLastError = true)]
    private static extern bool HidD_FreePreparsedData(IntPtr preparsedData);

    [DllImport("hid.dll", SetLastError = true)]
    private static extern bool HidD_GetFeature(SafeFileHandle hidDeviceObject, byte[] reportBuffer, int reportBufferLength);

    [DllImport("hid.dll", SetLastError = true)]
    private static extern bool HidD_SetFeature(SafeFileHandle hidDeviceObject, byte[] reportBuffer, int reportBufferLength);

    [DllImport("hid.dll")]
    private static extern int HidP_GetCaps(IntPtr preparsedData, out HidpCaps capabilities);

    [DllImport("hid.dll")]
    private static extern int HidP_GetValueCaps(HidpReportType reportType, [Out] HidpValueCaps[] valueCaps, ref ushort valueCapsLength, IntPtr preparsedData);

    [DllImport("hid.dll")]
    private static extern int HidP_GetUsageValue(HidpReportType reportType, ushort usagePage, ushort linkCollection, ushort usage, out uint usageValue, IntPtr preparsedData, byte[] report, int reportLength);

    [DllImport("hid.dll")]
    private static extern int HidP_SetUsageValue(HidpReportType reportType, ushort usagePage, ushort linkCollection, ushort usage, uint usageValue, IntPtr preparsedData, byte[] report, int reportLength);
}
