$ErrorActionPreference = "Stop"

$source = @"
using System;
using System.ComponentModel;
using System.Runtime.InteropServices;
using Microsoft.Win32.SafeHandles;

public static class StudioXdrAmbientProbe
{
    const uint DIGCF_PRESENT = 0x00000002;
    const uint DIGCF_DEVICEINTERFACE = 0x00000010;
    const uint GENERIC_READ = 0x80000000;
    const uint GENERIC_WRITE = 0x40000000;
    const uint FILE_SHARE_READ = 0x00000001;
    const uint FILE_SHARE_WRITE = 0x00000002;
    const uint OPEN_EXISTING = 3;
    const byte PIPE_ID = 0x89;
    static Guid InterfaceGuid = new Guid("6F94F6F0-7B76-4DFB-AD85-905E20C82D9D");
    static Guid UsbDeviceInterfaceGuid = new Guid("A5DCBF10-6530-11D2-901F-00C04FB951ED");

    [StructLayout(LayoutKind.Sequential)]
    struct SP_DEVICE_INTERFACE_DATA
    {
        public int cbSize;
        public Guid InterfaceClassGuid;
        public int Flags;
        public IntPtr Reserved;
    }

    [DllImport("setupapi.dll", SetLastError = true)] static extern IntPtr SetupDiGetClassDevs(ref Guid ClassGuid, IntPtr Enumerator, IntPtr hwndParent, uint Flags);
    [DllImport("setupapi.dll", SetLastError = true)] static extern bool SetupDiEnumDeviceInterfaces(IntPtr DeviceInfoSet, IntPtr DeviceInfoData, ref Guid InterfaceClassGuid, uint MemberIndex, ref SP_DEVICE_INTERFACE_DATA DeviceInterfaceData);
    [DllImport("setupapi.dll", SetLastError = true)] static extern bool SetupDiGetDeviceInterfaceDetail(IntPtr DeviceInfoSet, ref SP_DEVICE_INTERFACE_DATA DeviceInterfaceData, IntPtr DeviceInterfaceDetailData, int DeviceInterfaceDetailDataSize, out int RequiredSize, IntPtr DeviceInfoData);
    [DllImport("setupapi.dll", SetLastError = true)] static extern bool SetupDiDestroyDeviceInfoList(IntPtr DeviceInfoSet);
    [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)] static extern SafeFileHandle CreateFile(string lpFileName, uint dwDesiredAccess, uint dwShareMode, IntPtr lpSecurityAttributes, uint dwCreationDisposition, uint dwFlagsAndAttributes, IntPtr hTemplateFile);
    [DllImport("winusb.dll", SetLastError = true)] static extern bool WinUsb_Initialize(SafeFileHandle DeviceHandle, out IntPtr InterfaceHandle);
    [DllImport("winusb.dll", SetLastError = true)] static extern bool WinUsb_ReadPipe(IntPtr InterfaceHandle, byte PipeID, byte[] Buffer, int BufferLength, out int LengthTransferred, IntPtr Overlapped);
    [DllImport("winusb.dll", SetLastError = true)] static extern bool WinUsb_Free(IntPtr InterfaceHandle);

    public static string FindPath()
    {
        return FindPath(InterfaceGuid, false) ?? FindPath(UsbDeviceInterfaceGuid, true);
    }

    static string FindPath(Guid guid, bool requireStudioAmbientPath)
    {
        IntPtr set = SetupDiGetClassDevs(ref guid, IntPtr.Zero, IntPtr.Zero, DIGCF_PRESENT | DIGCF_DEVICEINTERFACE);
        if (set == new IntPtr(-1)) return null;
        try
        {
            for (uint i = 0; ; i++)
            {
                var ifd = new SP_DEVICE_INTERFACE_DATA();
                ifd.cbSize = Marshal.SizeOf(typeof(SP_DEVICE_INTERFACE_DATA));
                if (!SetupDiEnumDeviceInterfaces(set, IntPtr.Zero, ref guid, i, ref ifd))
                {
                    if (Marshal.GetLastWin32Error() == 259) break;
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
                    if (!requireStudioAmbientPath || IsStudioAmbientPath(path)) return path;
                }
                finally
                {
                    Marshal.FreeHGlobal(detail);
                }
            }
            return null;
        }
        finally
        {
            SetupDiDestroyDeviceInfoList(set);
        }
    }

    static bool IsStudioAmbientPath(string path)
    {
        return path != null && path.IndexOf("vid_05ac&pid_1116&mi_08", StringComparison.OrdinalIgnoreCase) >= 0;
    }

    public static string ReadOnce()
    {
        string path = FindPath();
        if (path == null) return "No Studio XDR ambient WinUSB interface found. Install or bind the ambient connector first.";
        using (var h = CreateFile(path, GENERIC_READ | GENERIC_WRITE, FILE_SHARE_READ | FILE_SHARE_WRITE, IntPtr.Zero, OPEN_EXISTING, 0, IntPtr.Zero))
        {
            if (h.IsInvalid) throw new Win32Exception(Marshal.GetLastWin32Error(), "CreateFile failed");
            IntPtr winusb;
            if (!WinUsb_Initialize(h, out winusb)) throw new Win32Exception(Marshal.GetLastWin32Error(), "WinUsb_Initialize failed");
            try
            {
                byte[] buffer = new byte[18];
                int transferred;
                if (!WinUsb_ReadPipe(winusb, PIPE_ID, buffer, buffer.Length, out transferred, IntPtr.Zero))
                {
                    throw new Win32Exception(Marshal.GetLastWin32Error(), "WinUsb_ReadPipe failed");
                }
                int ambient = transferred >= 6 ? BitConverter.ToInt32(buffer, 2) : -1;
                return "Path=" + path + Environment.NewLine +
                    "Transferred=" + transferred + Environment.NewLine +
                    "Raw=" + BitConverter.ToString(buffer) + Environment.NewLine +
                    "Ambient=" + ambient;
            }
            finally
            {
                WinUsb_Free(winusb);
            }
        }
    }
}
"@

if (-not ("StudioXdrAmbientProbe" -as [type])) {
    Add-Type -TypeDefinition $source -ReferencedAssemblies "System.dll"
}

[StudioXdrAmbientProbe]::ReadOnce()
