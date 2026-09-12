using System.IO;
using System.Text.Json;

namespace StudioDisplayXdr.App;

internal sealed class AppSettings
{
    public int AutoMinimumBrightnessPercent { get; set; } = 25;
    public int AutoMaximumBrightnessPercent { get; set; } = 100;
    public int AutoResponsePercent { get; set; } = 100;
    public bool AutoBrightnessEnabled { get; set; }

    public static AppSettings Load()
    {
        var path = GetPath();
        if (!File.Exists(path))
        {
            return new AppSettings();
        }

        try
        {
            var settings = JsonSerializer.Deserialize<AppSettings>(File.ReadAllText(path));
            settings ??= new AppSettings();
            settings.Normalize();
            return settings;
        }
        catch
        {
            return new AppSettings();
        }
    }

    public void Save()
    {
        Normalize();
        var path = GetPath();
        Directory.CreateDirectory(Path.GetDirectoryName(path)!);
        var json = JsonSerializer.Serialize(this, new JsonSerializerOptions { WriteIndented = true });
        File.WriteAllText(path, json);
    }

    public void Normalize()
    {
        AutoMinimumBrightnessPercent = Math.Clamp(AutoMinimumBrightnessPercent, 5, 90);
        AutoMaximumBrightnessPercent = Math.Clamp(AutoMaximumBrightnessPercent, AutoMinimumBrightnessPercent + 5, 100);
        AutoResponsePercent = Math.Clamp(AutoResponsePercent, 50, 160);
    }

    private static string GetPath()
    {
        var root = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
        return Path.Combine(root, "StudioDisplayXdr", "settings.json");
    }
}
