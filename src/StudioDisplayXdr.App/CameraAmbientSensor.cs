using System.Runtime.InteropServices.WindowsRuntime;
using Windows.Devices.Enumeration;
using Windows.Graphics.Imaging;
using Windows.Media.Capture;
using Windows.Media.MediaProperties;
using Windows.Storage.Streams;

namespace StudioDisplayXdr.App;

internal sealed class CameraAmbientSensor : IAsyncDisposable
{
    private readonly MediaCapture _capture;
    private readonly string _cameraName;

    private CameraAmbientSensor(MediaCapture capture, string cameraName)
    {
        _capture = capture;
        _cameraName = cameraName;
    }

    public static async Task<CameraAmbientSensor?> CreateAsync(CancellationToken cancellationToken = default)
    {
        var devices = await FindCamerasAsync(cancellationToken);
        var device = devices.FirstOrDefault(d => d.Name.Contains("Studio", StringComparison.OrdinalIgnoreCase))
            ?? devices.FirstOrDefault();

        if (device is null)
        {
            return null;
        }

        var capture = new MediaCapture();
        await capture.InitializeAsync(new MediaCaptureInitializationSettings
        {
            VideoDeviceId = device.Id,
            StreamingCaptureMode = StreamingCaptureMode.Video,
            MemoryPreference = MediaCaptureMemoryPreference.Cpu
        }).AsTask(cancellationToken);

        return new CameraAmbientSensor(capture, device.Name);
    }

    public async Task<AmbientLightReading?> ReadAsync(CancellationToken cancellationToken = default)
    {
        var brightness = await CaptureBrightnessAsync(cancellationToken);
        if (brightness < 0.015)
        {
            await Task.Delay(700, cancellationToken);
            brightness = Math.Max(brightness, await CaptureBrightnessAsync(cancellationToken));
        }

        var raw = Math.Clamp((int)Math.Round(Math.Pow(brightness, 0.72) * 1_000_000), 0, 1_000_000);
        var isReliable = brightness >= 0.025;

        return new AmbientLightReading(
            raw,
            _cameraName,
            $"{brightness:P0} frame brightness",
            isReliable,
            MinimumBrightnessPercent: 25);
    }

    public ValueTask DisposeAsync()
    {
        _capture.Dispose();
        return ValueTask.CompletedTask;
    }

    private async Task<double> CaptureBrightnessAsync(CancellationToken cancellationToken)
    {
        using var stream = new InMemoryRandomAccessStream();
        var encoding = ImageEncodingProperties.CreateJpeg();
        await _capture.CapturePhotoToStreamAsync(encoding, stream).AsTask(cancellationToken);

        stream.Seek(0);
        var decoder = await BitmapDecoder.CreateAsync(stream).AsTask(cancellationToken);
        using var bitmap = await decoder.GetSoftwareBitmapAsync(BitmapPixelFormat.Bgra8, BitmapAlphaMode.Ignore).AsTask(cancellationToken);
        return SampleBrightness(bitmap);
    }

    private static double SampleBrightness(SoftwareBitmap bitmap)
    {
        var width = bitmap.PixelWidth;
        var height = bitmap.PixelHeight;
        var pixels = new byte[width * height * 4];
        bitmap.CopyToBuffer(pixels.AsBuffer());

        var xStep = Math.Max(1, width / 36);
        var yStep = Math.Max(1, height / 20);
        double total = 0;
        var count = 0;

        for (var y = 0; y < height; y += yStep)
        {
            for (var x = 0; x < width; x += xStep)
            {
                var index = ((y * width) + x) * 4;
                if (index + 2 >= pixels.Length)
                {
                    continue;
                }

                var blue = pixels[index];
                var green = pixels[index + 1];
                var red = pixels[index + 2];
                total += (0.2126 * red) + (0.7152 * green) + (0.0722 * blue);
                count++;
            }
        }

        if (count == 0)
        {
            return 0;
        }

        return Math.Clamp(total / count / 255.0, 0, 1);
    }

    public static async Task<IReadOnlyList<DeviceInformation>> FindCamerasAsync(CancellationToken cancellationToken = default)
    {
        var devices = await DeviceInformation.FindAllAsync(DeviceClass.VideoCapture).AsTask(cancellationToken);
        return devices.ToList();
    }
}
