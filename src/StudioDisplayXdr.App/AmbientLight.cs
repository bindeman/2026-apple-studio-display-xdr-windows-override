using Windows.Devices.Enumeration;
using Windows.Devices.Sensors;

namespace StudioDisplayXdr.App;

internal sealed record AmbientLightReading(
    int Value,
    string Source,
    string Detail,
    bool IsReliable = true,
    int MinimumBrightnessPercent = 8);

internal sealed record AmbientLightAvailability(bool HasSource, string Message);

internal sealed class AmbientLightController : IAsyncDisposable
{
    private WindowsAmbientSensorReader? _windowsSensor;
    private bool _windowsSensorChecked;
    private StudioLibUsbAmbientSensor? _libUsbSensor;
    private bool _libUsbSensorChecked;
    private CameraAmbientSensor? _camera;

    public async Task<AmbientLightReading?> ReadAsync(CancellationToken cancellationToken = default)
    {
        if (!_windowsSensorChecked)
        {
            _windowsSensorChecked = true;
            _windowsSensor = await WindowsAmbientSensorReader.CreateAsync(cancellationToken);
        }

        var native = _windowsSensor?.Read();
        if (native is not null)
        {
            return native;
        }

        var connector = ReadAppleConnector(cancellationToken);
        if (connector is not null)
        {
            return connector;
        }

        var libUsb = ReadLibUsbConnector(cancellationToken);
        if (libUsb is not null)
        {
            return libUsb;
        }

        _camera ??= await CameraAmbientSensor.CreateAsync(cancellationToken);
        if (_camera is null)
        {
            return null;
        }

        return await _camera.ReadAsync(cancellationToken);
    }

    public static async Task<AmbientLightAvailability> GetAvailabilityAsync(CancellationToken cancellationToken = default)
    {
        var windowsSensor = await WindowsAmbientSensorReader.CreateAsync(cancellationToken);
        if (windowsSensor is not null)
        {
            return new AmbientLightAvailability(true, $"Automatic brightness can use {windowsSensor.Name}.");
        }

        if (StudioAmbientSensor.IsWinUsbConnectorInstalled())
        {
            return new AmbientLightAvailability(true, "Automatic brightness can use the experimental Studio Display XDR sensor connector.");
        }

        if (StudioLibUsbAmbientSensor.CanOpen())
        {
            return new AmbientLightAvailability(true, "Automatic brightness can use the experimental Studio Display XDR libusb sensor connector.");
        }

        var cameras = await CameraAmbientSensor.FindCamerasAsync(cancellationToken);
        if (cameras.Any(device => device.Name.Contains("Studio", StringComparison.OrdinalIgnoreCase)))
        {
            return new AmbientLightAvailability(true, "Automatic brightness can use the Studio Display Camera fallback.");
        }

        if (cameras.Count > 0)
        {
            return new AmbientLightAvailability(true, "Automatic brightness can use a camera fallback.");
        }

        return new AmbientLightAvailability(false, "No ambient source is available yet.");
    }

    public async ValueTask DisposeAsync()
    {
        _libUsbSensor?.Dispose();

        if (_camera is not null)
        {
            await _camera.DisposeAsync();
        }
    }

    private static AmbientLightReading? ReadAppleConnector(CancellationToken cancellationToken)
    {
        if (!StudioAmbientSensor.IsWinUsbConnectorInstalled())
        {
            return null;
        }

        using var sensor = StudioAmbientSensor.Open();
        var reading = sensor?.ReadAmbientLight(cancellationToken);
        if (reading is null)
        {
            return null;
        }

        return new AmbientLightReading(reading.Value, "Studio Display XDR light sensor", $"{reading.Value:N0}");
    }

    private AmbientLightReading? ReadLibUsbConnector(CancellationToken cancellationToken)
    {
        if (!_libUsbSensorChecked)
        {
            _libUsbSensorChecked = true;
            _libUsbSensor = StudioLibUsbAmbientSensor.Open();
        }

        return _libUsbSensor?.ReadAmbientLight(cancellationToken);
    }

    private static int LuxToRaw(float lux)
    {
        var normalized = Math.Clamp(lux / 5000.0, 0, 1);
        return Math.Clamp((int)Math.Round(normalized * 1_000_000), 0, 1_000_000);
    }

    private sealed class WindowsAmbientSensorReader
    {
        private readonly LightSensor _sensor;

        private WindowsAmbientSensorReader(LightSensor sensor, string name)
        {
            _sensor = sensor;
            Name = name;
        }

        public string Name { get; }

        public static async Task<WindowsAmbientSensorReader?> CreateAsync(CancellationToken cancellationToken)
        {
            try
            {
                var selector = LightSensor.GetDeviceSelector();
                var devices = await DeviceInformation.FindAllAsync(selector).AsTask(cancellationToken);
                var preferred = devices
                    .OrderByDescending(Score)
                    .FirstOrDefault();

                if (preferred is not null)
                {
                    var sensor = await LightSensor.FromIdAsync(preferred.Id).AsTask(cancellationToken);
                    if (sensor is not null)
                    {
                        return new WindowsAmbientSensorReader(sensor, PreferredName(preferred.Name));
                    }
                }
            }
            catch
            {
                // Fall through to GetDefault. Some systems expose a default sensor but reject enumeration.
            }

            var defaultSensor = LightSensor.GetDefault();
            return defaultSensor is null
                ? null
                : new WindowsAmbientSensorReader(defaultSensor, "the Windows ambient light sensor");
        }

        public AmbientLightReading? Read()
        {
            var reading = _sensor.GetCurrentReading();
            if (reading is null)
            {
                return null;
            }

            var lux = Math.Max(0, reading.IlluminanceInLux);
            var value = LuxToRaw(lux);
            return new AmbientLightReading(value, Name, $"{lux:0} lux");
        }

        private static int Score(DeviceInformation device)
        {
            var text = $"{device.Name} {device.Id}".ToLowerInvariant();
            var score = 0;

            if (text.Contains("apple")) score += 80;
            if (text.Contains("studio")) score += 70;
            if (text.Contains("xdr")) score += 70;
            if (text.Contains("pro display")) score += 70;
            if (text.Contains("display")) score += 30;
            if (text.Contains("ambient")) score += 15;
            if (text.Contains("05ac")) score += 40;

            return score;
        }

        private static string PreferredName(string name)
        {
            return string.IsNullOrWhiteSpace(name)
                ? "the Windows ambient light sensor"
                : $"{name} ambient light sensor";
        }
    }
}
