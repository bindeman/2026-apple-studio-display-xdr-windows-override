$ErrorActionPreference = "Stop"

function Find-LibUsbDotNet {
    $repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
    $candidates = @(
        (Join-Path $repoRoot "tools\LibUsbDotNet.LibUsbDotNet.net45.dll"),
        (Join-Path $env:USERPROFILE ".nuget\packages\libusbdotnet\2.2.29\lib\net45\LibUsbDotNet.LibUsbDotNet.dll"),
        (Join-Path $repoRoot "dist\StudioDisplayXdr.App\LibUsbDotNet.LibUsbDotNet.dll")
    )

    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath $candidate) {
            try {
                Add-Type -Path $candidate -ErrorAction Stop
                return (Resolve-Path -LiteralPath $candidate).Path
            }
            catch {
                continue
            }
        }
    }

    return $null
}

$libraryPath = Find-LibUsbDotNet
if (-not $libraryPath) {
    Write-Host "LibUsbDotNet probe unavailable: no loadable LibUsbDotNet .NET Framework assembly was found."
    return
}

$source = @"
using System;
using LibUsbDotNet;
using LibUsbDotNet.Main;

public static class StudioXdrLibUsbAmbientProbe
{
    const int VendorId = 0x05ac;
    const int ProductId = 0x1116;
    const byte Configuration = 1;
    const int InterfaceNumber = 8;
    const int PacketLength = 18;
    const int ReadTimeoutMs = 750;

    public static string ReadOnce()
    {
        UsbDevice device = null;
        UsbEndpointReader reader = null;
        bool claimedInterface = false;

        try
        {
            var finder = new UsbDeviceFinder(VendorId, ProductId);
            device = UsbDevice.OpenUsbDevice(finder);
            if (device == null || !device.IsOpen)
            {
                return "No Studio Display XDR libusb device opened. Install an exact libusb-win32 filter for USB\\VID_05AC&PID_1116&MI_08 first.";
            }

            var wholeDevice = device as IUsbDevice;
            if (wholeDevice != null)
            {
                wholeDevice.SetConfiguration(Configuration);
                wholeDevice.ClaimInterface(InterfaceNumber);
                claimedInterface = true;
            }

            reader = device.OpenEndpointReader(ReadEndpointID.Ep09, PacketLength, EndpointType.Interrupt);
            byte[] buffer = new byte[PacketLength];
            int transferred;
            ErrorCode errorCode = reader.Read(buffer, ReadTimeoutMs, out transferred);

            if (errorCode != ErrorCode.None)
            {
                return "LibUSB device opened, but EP09 read failed: " + errorCode + ". Transferred=" + transferred;
            }

            int ambient = transferred >= 6 ? BitConverter.ToInt32(buffer, 2) : -1;
            return "LibUSB path opened." + Environment.NewLine +
                   "Transferred=" + transferred + Environment.NewLine +
                   "Raw=" + BitConverter.ToString(buffer) + Environment.NewLine +
                   "Ambient=" + ambient;
        }
        catch (Exception ex)
        {
            return "LibUSB ambient probe failed: " + ex.GetType().Name + ": " + ex.Message;
        }
        finally
        {
            if (reader != null)
            {
                try { reader.Dispose(); } catch { }
            }

            if (device != null)
            {
                try
                {
                    var wholeDevice = device as IUsbDevice;
                    if (claimedInterface && wholeDevice != null)
                    {
                        wholeDevice.ReleaseInterface(InterfaceNumber);
                    }
                    device.Close();
                }
                catch { }
            }

            UsbDevice.Exit();
        }
    }
}
"@

if (-not ("StudioXdrLibUsbAmbientProbe" -as [type])) {
    Add-Type -TypeDefinition $source -ReferencedAssemblies "System.dll", $libraryPath
}

Write-Host "LibUsbDotNet: $libraryPath"
[StudioXdrLibUsbAmbientProbe]::ReadOnce()
