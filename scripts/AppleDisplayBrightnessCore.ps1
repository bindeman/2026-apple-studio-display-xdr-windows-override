$AppleDisplayBrightnessSource = @"
using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Runtime.InteropServices;
using Microsoft.Win32.SafeHandles;

public static class AppleDisplayBrightness
{
    const uint DIGCF_PRESENT = 0x00000002;
    const uint DIGCF_DEVICEINTERFACE = 0x00000010;
    const uint GENERIC_READ = 0x80000000;
    const uint GENERIC_WRITE = 0x40000000;
    const uint FILE_SHARE_READ = 0x00000001;
    const uint FILE_SHARE_WRITE = 0x00000002;
    const uint OPEN_EXISTING = 3;
    const int HIDP_STATUS_SUCCESS = 0x00110000;

    enum HIDP_REPORT_TYPE : short { HidP_Input = 0, HidP_Output = 1, HidP_Feature = 2 }

    [StructLayout(LayoutKind.Sequential)]
    struct SP_DEVICE_INTERFACE_DATA
    {
        public int cbSize;
        public Guid InterfaceClassGuid;
        public int Flags;
        public IntPtr Reserved;
    }

    [StructLayout(LayoutKind.Sequential)]
    struct HIDP_CAPS
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
    struct HIDP_VALUE_CAPS
    {
        [FieldOffset(0)] public ushort UsagePage;
        [FieldOffset(2)] public byte ReportID;
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

    public sealed class DeviceInfo
    {
        public string Path;
        public string ProductId;
        public string DisplayName;
        public ushort UsagePage;
        public ushort Usage;
        public byte ReportId;
        public ushort FeatureReportLength;
        public int LogicalMin;
        public int LogicalMax;
        public uint CurrentValue;
        public string Error;

        public int EffectiveMin { get { return LogicalMax > LogicalMin ? LogicalMin : 0; } }
        public int EffectiveMax { get { return LogicalMax > LogicalMin ? LogicalMax : 100000; } }
        public int Percent { get { return (int)Math.Round(((double)CurrentValue - EffectiveMin) * 100.0 / (EffectiveMax - EffectiveMin)); } }
    }

    [DllImport("hid.dll")] static extern void HidD_GetHidGuid(out Guid HidGuid);
    [DllImport("setupapi.dll", SetLastError = true)] static extern IntPtr SetupDiGetClassDevs(ref Guid ClassGuid, IntPtr Enumerator, IntPtr hwndParent, uint Flags);
    [DllImport("setupapi.dll", SetLastError = true)] static extern bool SetupDiEnumDeviceInterfaces(IntPtr DeviceInfoSet, IntPtr DeviceInfoData, ref Guid InterfaceClassGuid, uint MemberIndex, ref SP_DEVICE_INTERFACE_DATA DeviceInterfaceData);
    [DllImport("setupapi.dll", SetLastError = true)] static extern bool SetupDiGetDeviceInterfaceDetail(IntPtr DeviceInfoSet, ref SP_DEVICE_INTERFACE_DATA DeviceInterfaceData, IntPtr DeviceInterfaceDetailData, int DeviceInterfaceDetailDataSize, out int RequiredSize, IntPtr DeviceInfoData);
    [DllImport("setupapi.dll", SetLastError = true)] static extern bool SetupDiDestroyDeviceInfoList(IntPtr DeviceInfoSet);
    [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)] static extern SafeFileHandle CreateFile(string lpFileName, uint dwDesiredAccess, uint dwShareMode, IntPtr lpSecurityAttributes, uint dwCreationDisposition, uint dwFlagsAndAttributes, IntPtr hTemplateFile);
    [DllImport("hid.dll", SetLastError = true)] static extern bool HidD_GetPreparsedData(SafeFileHandle HidDeviceObject, out IntPtr PreparsedData);
    [DllImport("hid.dll", SetLastError = true)] static extern bool HidD_FreePreparsedData(IntPtr PreparsedData);
    [DllImport("hid.dll", SetLastError = true)] static extern bool HidD_GetFeature(SafeFileHandle HidDeviceObject, byte[] ReportBuffer, int ReportBufferLength);
    [DllImport("hid.dll", SetLastError = true)] static extern bool HidD_SetFeature(SafeFileHandle HidDeviceObject, byte[] ReportBuffer, int ReportBufferLength);
    [DllImport("hid.dll")] static extern int HidP_GetCaps(IntPtr PreparsedData, out HIDP_CAPS Capabilities);
    [DllImport("hid.dll")] static extern int HidP_GetValueCaps(HIDP_REPORT_TYPE ReportType, [Out] HIDP_VALUE_CAPS[] ValueCaps, ref ushort ValueCapsLength, IntPtr PreparsedData);
    [DllImport("hid.dll")] static extern int HidP_GetUsageValue(HIDP_REPORT_TYPE ReportType, ushort UsagePage, ushort LinkCollection, ushort Usage, out uint UsageValue, IntPtr PreparsedData, byte[] Report, int ReportLength);
    [DllImport("hid.dll")] static extern int HidP_SetUsageValue(HIDP_REPORT_TYPE ReportType, ushort UsagePage, ushort LinkCollection, ushort Usage, uint UsageValue, IntPtr PreparsedData, byte[] Report, int ReportLength);

    public static List<DeviceInfo> Enumerate()
    {
        Guid hidGuid;
        HidD_GetHidGuid(out hidGuid);
        IntPtr set = SetupDiGetClassDevs(ref hidGuid, IntPtr.Zero, IntPtr.Zero, DIGCF_PRESENT | DIGCF_DEVICEINTERFACE);
        if (set == new IntPtr(-1)) throw new Win32Exception(Marshal.GetLastWin32Error(), "SetupDiGetClassDevs failed");

        var found = new List<DeviceInfo>();
        try
        {
            for (uint i = 0; ; i++)
            {
                var ifd = new SP_DEVICE_INTERFACE_DATA();
                ifd.cbSize = Marshal.SizeOf(typeof(SP_DEVICE_INTERFACE_DATA));
                if (!SetupDiEnumDeviceInterfaces(set, IntPtr.Zero, ref hidGuid, i, ref ifd))
                {
                    int err = Marshal.GetLastWin32Error();
                    if (err == 259) break;
                    continue;
                }

                int need;
                SetupDiGetDeviceInterfaceDetail(set, ref ifd, IntPtr.Zero, 0, out need, IntPtr.Zero);
                IntPtr detail = Marshal.AllocHGlobal(need);
                try
                {
                    Marshal.WriteInt32(detail, IntPtr.Size == 8 ? 8 : 6);
                    if (!SetupDiGetDeviceInterfaceDetail(set, ref ifd, detail, need, out need, IntPtr.Zero)) continue;
                    string path = Marshal.PtrToStringUni(IntPtr.Add(detail, 4));
                    if (path == null) continue;
                    string lower = path.ToLowerInvariant();
                    if (!lower.StartsWith(@"\\?\hid#")) continue;
                    if (!lower.Contains("vid_05ac")) continue;
                    if (!lower.Contains("pid_1116")) continue;

                    var info = ProbePath(path);
                    if (lower.Contains("pid_1116")) { info.ProductId = "1116"; info.DisplayName = "Studio Display XDR"; }
                    found.Add(info);
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

        return found;
    }

    public static DeviceInfo ProbePath(string path)
    {
        var info = new DeviceInfo();
        info.Path = path;

        using (var h = CreateFile(path, GENERIC_READ | GENERIC_WRITE, FILE_SHARE_READ | FILE_SHARE_WRITE, IntPtr.Zero, OPEN_EXISTING, 0, IntPtr.Zero))
        {
            if (h.IsInvalid) { info.Error = "CreateFile failed: " + Marshal.GetLastWin32Error(); return info; }

            IntPtr prep;
            if (!HidD_GetPreparsedData(h, out prep)) { info.Error = "HidD_GetPreparsedData failed: " + Marshal.GetLastWin32Error(); return info; }

            try
            {
                HIDP_CAPS caps;
                int status = HidP_GetCaps(prep, out caps);
                if (status != HIDP_STATUS_SUCCESS) { info.Error = "HidP_GetCaps failed: 0x" + status.ToString("X8"); return info; }

                info.FeatureReportLength = caps.FeatureReportByteLength;
                ushort count = caps.NumberFeatureValueCaps;
                if (count == 0) { info.Error = "No feature value caps"; return info; }

                var vals = new HIDP_VALUE_CAPS[count];
                status = HidP_GetValueCaps(HIDP_REPORT_TYPE.HidP_Feature, vals, ref count, prep);
                if (status != HIDP_STATUS_SUCCESS) { info.Error = "HidP_GetValueCaps failed: 0x" + status.ToString("X8"); return info; }

                int chosen = -1;
                for (int n = 0; n < count; n++)
                {
                    ushort usage = vals[n].IsRange ? vals[n].UsageMin : vals[n].Usage;
                    if (vals[n].UsagePage == 0x0082 && usage == 0x0010) { chosen = n; break; }
                }

                if (chosen < 0) { info.Error = "No VESA brightness feature cap found"; return info; }

                var cap = vals[chosen];
                info.UsagePage = cap.UsagePage;
                info.Usage = cap.IsRange ? cap.UsageMin : cap.Usage;
                info.ReportId = cap.ReportID;
                info.LogicalMin = cap.LogicalMin;
                info.LogicalMax = cap.LogicalMax;

                byte[] report = new byte[caps.FeatureReportByteLength];
                report[0] = cap.ReportID;
                if (!HidD_GetFeature(h, report, report.Length)) { info.Error = "HidD_GetFeature failed: " + Marshal.GetLastWin32Error(); return info; }

                uint current;
                status = HidP_GetUsageValue(HIDP_REPORT_TYPE.HidP_Feature, cap.UsagePage, 0, info.Usage, out current, prep, report, report.Length);
                if (status != HIDP_STATUS_SUCCESS) { info.Error = "HidP_GetUsageValue failed: 0x" + status.ToString("X8"); return info; }
                info.CurrentValue = current;
            }
            finally
            {
                HidD_FreePreparsedData(prep);
            }
        }
        return info;
    }

    public static void SetPercent(string path, int percent)
    {
        percent = Math.Max(0, Math.Min(100, percent));
        SetBrightness(path, (uint)Math.Round(percent * 1000.0));
    }

    public static void StepPercent(string path, int currentPercent, int step)
    {
        SetPercent(path, Math.Max(0, Math.Min(100, currentPercent + step)));
    }

    public static void SetBrightness(string path, uint value)
    {
        using (var h = CreateFile(path, GENERIC_READ | GENERIC_WRITE, FILE_SHARE_READ | FILE_SHARE_WRITE, IntPtr.Zero, OPEN_EXISTING, 0, IntPtr.Zero))
        {
            if (h.IsInvalid) throw new Win32Exception(Marshal.GetLastWin32Error(), "CreateFile failed");
            IntPtr prep;
            if (!HidD_GetPreparsedData(h, out prep)) throw new Win32Exception(Marshal.GetLastWin32Error(), "HidD_GetPreparsedData failed");
            try
            {
                HIDP_CAPS caps;
                int status = HidP_GetCaps(prep, out caps);
                if (status != HIDP_STATUS_SUCCESS) throw new Exception("HidP_GetCaps failed: 0x" + status.ToString("X8"));

                ushort count = caps.NumberFeatureValueCaps;
                var vals = new HIDP_VALUE_CAPS[count];
                status = HidP_GetValueCaps(HIDP_REPORT_TYPE.HidP_Feature, vals, ref count, prep);
                if (status != HIDP_STATUS_SUCCESS) throw new Exception("HidP_GetValueCaps failed: 0x" + status.ToString("X8"));

                HIDP_VALUE_CAPS cap = new HIDP_VALUE_CAPS();
                bool ok = false;
                for (int n = 0; n < count; n++)
                {
                    ushort usage = vals[n].IsRange ? vals[n].UsageMin : vals[n].Usage;
                    if (vals[n].UsagePage == 0x0082 && usage == 0x0010) { cap = vals[n]; ok = true; break; }
                }
                if (!ok) throw new Exception("No VESA brightness feature cap found");

                byte[] report = new byte[caps.FeatureReportByteLength];
                report[0] = cap.ReportID;
                if (!HidD_GetFeature(h, report, report.Length)) throw new Win32Exception(Marshal.GetLastWin32Error(), "HidD_GetFeature failed");

                ushort brightnessUsage = cap.IsRange ? cap.UsageMin : cap.Usage;
                status = HidP_SetUsageValue(HIDP_REPORT_TYPE.HidP_Feature, cap.UsagePage, 0, brightnessUsage, value, prep, report, report.Length);
                if (status != HIDP_STATUS_SUCCESS) throw new Exception("HidP_SetUsageValue failed: 0x" + status.ToString("X8"));

                if (!HidD_SetFeature(h, report, report.Length)) throw new Win32Exception(Marshal.GetLastWin32Error(), "HidD_SetFeature failed");
            }
            finally
            {
                HidD_FreePreparsedData(prep);
            }
        }
    }
}

public class AppleBrightnessHotkeyWindow : System.Windows.Forms.Form
{
    public const int WM_HOTKEY = 0x0312;
    public event Action<int> HotkeyPressed;

    protected override void WndProc(ref System.Windows.Forms.Message m)
    {
        if (m.Msg == WM_HOTKEY && HotkeyPressed != null)
        {
            HotkeyPressed(m.WParam.ToInt32());
        }
        base.WndProc(ref m);
    }
}
"@

if (-not ("AppleDisplayBrightness" -as [type])) {
    Add-Type -TypeDefinition $AppleDisplayBrightnessSource -ReferencedAssemblies "System.dll","System.Windows.Forms.dll"
}

function Get-AppleDisplayBrightnessDevice {
    $devices = @([AppleDisplayBrightness]::Enumerate())
    if ($devices.Count -eq 0) {
        $hidInterfaceGuid = "{4d1e55b2-f16f-11cf-88cb-001111000030}"
        $instances = Get-CimInstance Win32_PnPEntity |
            Where-Object { $_.DeviceID -match "^HID\\VID_05AC&PID_1116" } |
            Select-Object -ExpandProperty DeviceID

        foreach ($instance in $instances) {
            $path = "\\?\" + ($instance.ToLowerInvariant() -replace "\\", "#") + "#" + $hidInterfaceGuid
            $device = [AppleDisplayBrightness]::ProbePath($path)
            $device.ProductId = "1116"
            $device.DisplayName = "Studio Display XDR"
            $devices += $device
        }
    }

    $devices | Where-Object { -not $_.Error -and $_.UsagePage -eq 0x82 -and $_.Usage -eq 0x10 }
}
