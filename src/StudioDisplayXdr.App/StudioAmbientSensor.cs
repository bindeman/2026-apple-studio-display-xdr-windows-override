using System.ComponentModel;
using System.Runtime.InteropServices;
using Microsoft.Win32.SafeHandles;

namespace StudioDisplayXdr.App;

internal sealed class StudioAmbientSensor : IDisposable
{
    private const uint DigcfPresent = 0x00000002;
    private const uint DigcfDeviceInterface = 0x00000010;
    private const uint GenericRead = 0x80000000;
    private const uint GenericWrite = 0x40000000;
    private const uint FileShareRead = 0x00000001;
    private const uint FileShareWrite = 0x00000002;
    private const uint OpenExisting = 3;
    private const int AmbientPacketLength = 18;
    private const byte AmbientPipeId = 0x89;
    private const uint PipeTransferTimeout = 0x03;

    // Registered by the experimental WinUSB driver INF for USB\VID_05AC&PID_1116&MI_08.
    private static readonly Guid StudioAmbientWinUsbGuid = new("6F94F6F0-7B76-4DFB-AD85-905E20C82D9D");

    // Some libwdi/Zadig bindings expose only the generic USB device interface.
    private static readonly Guid UsbDeviceInterfaceGuid = new("A5DCBF10-6530-11D2-901F-00C04FB951ED");

    private readonly SafeFileHandle _deviceHandle;
    private readonly SafeWinUsbHandle _winUsbHandle;

    private StudioAmbientSensor(SafeFileHandle deviceHandle, SafeWinUsbHandle winUsbHandle)
    {
        _deviceHandle = deviceHandle;
        _winUsbHandle = winUsbHandle;
    }

    public static bool IsWinUsbConnectorInstalled()
    {
        return FindDevicePath() is not null;
    }

    public static StudioAmbientSensor? Open()
    {
        var path = FindDevicePath();
        if (path is null)
        {
            return null;
        }

        var deviceHandle = CreateFile(path, GenericRead | GenericWrite, FileShareRead | FileShareWrite, IntPtr.Zero, OpenExisting, 0, IntPtr.Zero);
        if (deviceHandle.IsInvalid)
        {
            throw new Win32Exception(Marshal.GetLastWin32Error(), "Could not open Studio Display XDR ambient interface");
        }

        if (!WinUsb_Initialize(deviceHandle, out var winUsbHandle))
        {
            var error = Marshal.GetLastWin32Error();
            deviceHandle.Dispose();
            throw new Win32Exception(error, "WinUsb_Initialize failed for Studio Display XDR ambient interface");
        }

        var timeout = 450u;
        WinUsb_SetPipePolicy(winUsbHandle, AmbientPipeId, PipeTransferTimeout, sizeof(uint), ref timeout);

        return new StudioAmbientSensor(deviceHandle, winUsbHandle);
    }

    public int? ReadAmbientLight(CancellationToken cancellationToken = default)
    {
        var buffer = new byte[AmbientPacketLength];
        if (!WinUsb_ReadPipe(_winUsbHandle, AmbientPipeId, buffer, buffer.Length, out var transferred, IntPtr.Zero))
        {
            var error = Marshal.GetLastWin32Error();
            if (error == 121 || error == 995 || cancellationToken.IsCancellationRequested)
            {
                return null;
            }

            throw new Win32Exception(error, "Could not read Studio Display XDR ambient light packet");
        }

        if (transferred != AmbientPacketLength)
        {
            return null;
        }

        var value = BitConverter.ToInt32(buffer, 2);
        return Math.Max(0, Math.Min(1_000_000, value));
    }

    public void Dispose()
    {
        _winUsbHandle.Dispose();
        _deviceHandle.Dispose();
    }

    private static string? FindDevicePath()
    {
        return FindDevicePath(StudioAmbientWinUsbGuid, requireStudioAmbientPath: false)
            ?? FindDevicePath(UsbDeviceInterfaceGuid, requireStudioAmbientPath: true);
    }

    private static string? FindDevicePath(Guid interfaceGuid, bool requireStudioAmbientPath)
    {
        var set = SetupDiGetClassDevs(ref interfaceGuid, IntPtr.Zero, IntPtr.Zero, DigcfPresent | DigcfDeviceInterface);
        if (set == new IntPtr(-1))
        {
            return null;
        }

        try
        {
            for (uint i = 0; ; i++)
            {
                var interfaceData = new SpDeviceInterfaceData
                {
                    CbSize = Marshal.SizeOf<SpDeviceInterfaceData>()
                };

                if (!SetupDiEnumDeviceInterfaces(set, IntPtr.Zero, ref interfaceGuid, i, ref interfaceData))
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
                    if (!string.IsNullOrWhiteSpace(path))
                    {
                        if (!requireStudioAmbientPath || IsStudioAmbientPath(path))
                        {
                            return path;
                        }
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

        return null;
    }

    private static bool IsStudioAmbientPath(string path)
    {
        return path.Contains("vid_05ac&pid_1116&mi_08", StringComparison.OrdinalIgnoreCase);
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct SpDeviceInterfaceData
    {
        public int CbSize;
        public Guid InterfaceClassGuid;
        public int Flags;
        public IntPtr Reserved;
    }

    private sealed class SafeWinUsbHandle : SafeHandle
    {
        public SafeWinUsbHandle()
            : base(IntPtr.Zero, true)
        {
        }

        public override bool IsInvalid => handle == IntPtr.Zero;

        protected override bool ReleaseHandle()
        {
            return WinUsb_Free(handle);
        }
    }

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

    [DllImport("winusb.dll", SetLastError = true)]
    private static extern bool WinUsb_Initialize(SafeFileHandle deviceHandle, out SafeWinUsbHandle interfaceHandle);

    [DllImport("winusb.dll", SetLastError = true)]
    private static extern bool WinUsb_ReadPipe(SafeWinUsbHandle interfaceHandle, byte pipeId, [Out] byte[] buffer, int bufferLength, out int lengthTransferred, IntPtr overlapped);

    [DllImport("winusb.dll", SetLastError = true)]
    private static extern bool WinUsb_SetPipePolicy(SafeWinUsbHandle interfaceHandle, byte pipeId, uint policyType, int valueLength, ref uint value);

    [DllImport("winusb.dll", SetLastError = true)]
    private static extern bool WinUsb_Free(IntPtr interfaceHandle);
}
