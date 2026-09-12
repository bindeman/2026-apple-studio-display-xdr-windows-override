using LibUsbDotNet;
using LibUsbDotNet.Main;

namespace StudioDisplayXdr.App;

internal sealed class StudioLibUsbAmbientSensor : IDisposable
{
    private const int VendorId = 0x05ac;
    private const int ProductId = 0x1116;
    private const byte Configuration = 1;
    private const int InterfaceNumber = 8;
    private const int PacketLength = 18;
    private const int ReadTimeoutMs = 450;

    private static readonly UsbDeviceFinder DeviceFinder = new(VendorId, ProductId);

    private readonly UsbDevice _device;
    private readonly UsbEndpointReader _reader;
    private bool _claimedInterface;

    private StudioLibUsbAmbientSensor(UsbDevice device, UsbEndpointReader reader, bool claimedInterface)
    {
        _device = device;
        _reader = reader;
        _claimedInterface = claimedInterface;
    }

    public static StudioLibUsbAmbientSensor? Open()
    {
        UsbDevice? device = null;

        try
        {
            device = UsbDevice.OpenUsbDevice(DeviceFinder);
            if (device is null || !device.IsOpen)
            {
                return null;
            }

            var claimedInterface = false;
            if (device is IUsbDevice wholeDevice)
            {
                wholeDevice.SetConfiguration(Configuration);
                wholeDevice.ClaimInterface(InterfaceNumber);
                claimedInterface = true;
            }

            var reader = device.OpenEndpointReader(ReadEndpointID.Ep09, PacketLength, EndpointType.Interrupt);
            return new StudioLibUsbAmbientSensor(device, reader, claimedInterface);
        }
        catch
        {
            try
            {
                device?.Close();
            }
            catch
            {
                // Best-effort cleanup after a failed experimental USB open.
            }

            UsbDevice.Exit();
            return null;
        }
    }

    public static bool CanOpen()
    {
        using var sensor = Open();
        return sensor is not null;
    }

    public AmbientLightReading? ReadAmbientLight(CancellationToken cancellationToken = default)
    {
        if (cancellationToken.IsCancellationRequested)
        {
            return null;
        }

        var buffer = new byte[PacketLength];
        var error = _reader.Read(buffer, ReadTimeoutMs, out var transferred);
        if (error != ErrorCode.None || transferred != PacketLength)
        {
            return null;
        }

        var value = BitConverter.ToInt32(buffer, 2);
        value = Math.Clamp(value, 0, 1_000_000);
        return new AmbientLightReading(value, "Studio Display XDR light sensor", $"{value:N0}");
    }

    public void Dispose()
    {
        try
        {
            _reader.Dispose();
        }
        catch
        {
            // Best-effort cleanup for optional libusb access.
        }

        try
        {
            if (_claimedInterface && _device is IUsbDevice wholeDevice)
            {
                wholeDevice.ReleaseInterface(InterfaceNumber);
                _claimedInterface = false;
            }

            _device.Close();
        }
        catch
        {
            // Best-effort cleanup for optional libusb access.
        }

        UsbDevice.Exit();
    }
}
