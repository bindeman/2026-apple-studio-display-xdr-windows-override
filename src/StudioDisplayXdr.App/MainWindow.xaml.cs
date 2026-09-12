using System.Diagnostics;
using System.Collections.ObjectModel;
using System.ComponentModel;
using System.IO;
using System.Runtime.CompilerServices;
using System.Text.Json;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Threading;
using Forms = System.Windows.Forms;
using Drawing = System.Drawing;

namespace StudioDisplayXdr.App;

public partial class MainWindow : Window
{
    private readonly ObservableCollection<DisplayBrightnessViewModel> _displays = [];
    private readonly Dictionary<DisplayBrightnessViewModel, DispatcherTimer> _writeTimers = [];
    private readonly DispatcherTimer _autoBrightnessTimer;
    private readonly AppSettings _settings;
    private Forms.NotifyIcon? _notifyIcon;
    private AmbientLightController? _ambientLightController;
    private bool _isExitRequested;
    private bool _isUpdatingStartup;
    private bool _isLoadingSettings;
    private bool _isLoadingDisplays;
    private bool _isAutoBrightnessTickRunning;
    private bool _isUpdatingAutoToggle;
    private bool _isUpdatingHdrToggle;
    private bool _isDisplayActionRunning;
    private bool _isColorActionRunning;
    private bool _isColorCheckRunning;
    private bool _isDiagnosticActionRunning;
    private bool _isReadinessCheckRunning;
    private bool _isAmbientCheckRunning;

    public MainWindow()
    {
        _settings = AppSettings.Load();

        _isLoadingSettings = true;
        InitializeComponent();
        _isLoadingSettings = false;
        DisplayList.ItemsSource = _displays;
        InitializeTrayIcon();

        _autoBrightnessTimer = new DispatcherTimer
        {
            Interval = TimeSpan.FromSeconds(2)
        };
        _autoBrightnessTimer.Tick += AutoBrightnessTimer_OnTick;

        Loaded += (_, _) =>
        {
            RefreshStudioDisplays();
            RefreshDisplayState();
            RefreshColorProfileState();
            _ = RefreshAmbientStateAsync();
            RefreshStartupState();
            RefreshAutoBrightnessSettings();
            RefreshPackageInfo();
            ApplyStartupWindowState();
        };
    }

    private void ApplyStartupWindowState()
    {
        if (!App.StartMinimized)
        {
            return;
        }

        Dispatcher.BeginInvoke(() =>
        {
            HideToTray("Studio Display XDR is running in the notification area.");
        }, DispatcherPriority.Send);
    }

    private void InitializeTrayIcon()
    {
        var menu = new Forms.ContextMenuStrip();
        menu.Items.Add("Open Control Panel", null, (_, _) => Dispatcher.Invoke(ShowFromTray));
        menu.Items.Add("Refresh Displays", null, (_, _) => Dispatcher.Invoke(() =>
        {
            RefreshStudioDisplays();
            RefreshDisplayState();
            RefreshColorProfileState();
            _ = RefreshAmbientStateAsync();
        }));
        menu.Items.Add(new Forms.ToolStripSeparator());
        menu.Items.Add("Exit", null, (_, _) => Dispatcher.Invoke(() =>
        {
            _isExitRequested = true;
            Close();
        }));

        _notifyIcon = new Forms.NotifyIcon
        {
            Icon = LoadNotifyIcon(),
            Text = "Studio Display XDR",
            ContextMenuStrip = menu,
            Visible = true
        };
        _notifyIcon.DoubleClick += (_, _) => Dispatcher.Invoke(ShowFromTray);
    }

    private static Drawing.Icon LoadNotifyIcon()
    {
        try
        {
            var executable = Environment.ProcessPath;
            if (!string.IsNullOrWhiteSpace(executable))
            {
                var icon = Drawing.Icon.ExtractAssociatedIcon(executable);
                if (icon is not null)
                {
                    return icon;
                }
            }
        }
        catch
        {
            // Fall back to a stock icon if the executable icon cannot be extracted.
        }

        return Drawing.SystemIcons.Application;
    }

    private void HideToTray(string? status = null)
    {
        if (!string.IsNullOrWhiteSpace(status))
        {
            StartupText.Text = status;
        }

        ShowInTaskbar = false;
        Hide();
    }

    private void ShowFromTray()
    {
        ShowInTaskbar = true;
        Show();
        WindowState = WindowState.Normal;
        Activate();
    }

    internal void ShowFromExternalLaunch()
    {
        ShowFromTray();
        StartupText.Text = "Studio Display XDR is already running.";
    }

    protected override void OnStateChanged(EventArgs e)
    {
        base.OnStateChanged(e);

        if (WindowState == WindowState.Minimized && StartupToggle?.IsChecked == true)
        {
            Dispatcher.BeginInvoke(() => HideToTray("Studio Display XDR is running in the notification area."), DispatcherPriority.ApplicationIdle);
        }
    }

    protected override void OnClosing(CancelEventArgs e)
    {
        if (!_isExitRequested && StartupToggle?.IsChecked == true)
        {
            e.Cancel = true;
            HideToTray("Studio Display XDR is running in the notification area.");
            return;
        }

        _isExitRequested = true;
        base.OnClosing(e);
    }

    protected override void OnClosed(EventArgs e)
    {
        _notifyIcon?.Dispose();
        _notifyIcon = null;
        _ = DisposeAmbientControllerAsync();
        base.OnClosed(e);

        if (_isExitRequested)
        {
            System.Windows.Application.Current.Shutdown();
        }
    }

    private void RefreshStudioDisplays()
    {
        _isLoadingDisplays = true;
        _displays.Clear();

        try
        {
            var devices = StudioBrightnessDevice.FindAll();
            var displayNumber = 1;
            foreach (var device in devices)
            {
                _displays.Add(new DisplayBrightnessViewModel(
                    device,
                    devices.Count == 1 ? "Apple Studio Display XDR" : $"Apple Studio Display XDR {displayNumber++}"));
            }

            SetConnectedState(_displays.Count > 0);
        }
        catch (Exception ex)
        {
            SetConnectedState(false);
            _displays.Add(DisplayBrightnessViewModel.Error(ex.Message));
        }
        finally
        {
            NoDisplayPanel.Visibility = _displays.Count == 0 ? Visibility.Visible : Visibility.Collapsed;
            _isLoadingDisplays = false;
            Dispatcher.BeginInvoke(() =>
            {
                foreach (var display in _displays)
                {
                    display.AcceptWrites = true;
                }
            }, DispatcherPriority.Loaded);
        }
    }

    private void RefreshDisplayState()
    {
        _isUpdatingHdrToggle = true;
        try
        {
            var status = StudioDisplayController.GetStatus();
            if (status is null)
            {
                SignalText.Text = "No active Studio Display XDR signal found.";
                RefreshRateText.Text = "Connect the display over Thunderbolt or USB4.";
                HdrText.Text = "HDR state is unavailable.";
                HdrToggle.IsChecked = false;
                SetDisplayControlsEnabled(false);
                return;
            }

            var sourceWidth = status.SourceWidth > 0 ? status.SourceWidth : status.TargetActiveWidth;
            var sourceHeight = status.SourceHeight > 0 ? status.SourceHeight : status.TargetActiveHeight;
            var resolution = sourceWidth > 0 && sourceHeight > 0
                ? $"{sourceWidth} x {sourceHeight}"
                : "Unknown resolution";
            var refresh = status.TargetRefreshHz > 0
                ? $"{status.TargetRefreshHz:0.###} Hz"
                : "unknown refresh";

            SignalText.Text = $"{resolution} @ {refresh}";
            RefreshRateText.Text = status.PixelClockMHz > 0
                ? $"Active signal: {refresh}, pixel clock {status.PixelClockMHz:0.###} MHz."
                : $"Active signal: {refresh}.";

            HdrToggle.IsEnabled = status.AdvancedColorSupported && !_isDisplayActionRunning;
            HdrToggle.IsChecked = status.AdvancedColorEnabled;
            HdrText.Text = status.AdvancedColorSupported
                ? $"{(status.AdvancedColorEnabled ? "On" : "Off")}; {status.BitsPerColorChannel} bits per channel reported by Windows."
                : "Not supported by the active Studio Display XDR signal.";

            SetDisplayControlsEnabled(true);
        }
        catch (Exception ex)
        {
            SignalText.Text = "Could not read display signal.";
            RefreshRateText.Text = ex.Message;
            HdrText.Text = "HDR state is unavailable.";
            HdrToggle.IsChecked = false;
            SetDisplayControlsEnabled(false);
        }
        finally
        {
            _isUpdatingHdrToggle = false;
        }
    }

    private async void RefreshSignalButton_OnClick(object sender, RoutedEventArgs e)
    {
        await Task.Run(() => { });
        RefreshDisplayState();
    }

    private async void OptimizeSignalButton_OnClick(object sender, RoutedEventArgs e)
    {
        if (_isDisplayActionRunning)
        {
            return;
        }

        _isDisplayActionRunning = true;
        SetDisplayControlsEnabled(false);
        SignalText.Text = "Optimizing display signal...";
        RefreshRateText.Text = "Switching to 5120 x 2880 @ 120 Hz...";
        HdrText.Text = "Preparing HDR / Advanced Color...";

        try
        {
            var result = await Task.Run(StudioDisplayController.Optimize);
            RefreshRateText.Text = result;
            await Task.Delay(1200);
        }
        catch (Exception ex)
        {
            RefreshRateText.Text = $"Could not optimize display: {ex.Message}";
        }
        finally
        {
            _isDisplayActionRunning = false;
            RefreshDisplayState();
        }
    }

    private async void Refresh60Button_OnClick(object sender, RoutedEventArgs e)
    {
        await SetRefreshRateAsync(60);
    }

    private async void Refresh120Button_OnClick(object sender, RoutedEventArgs e)
    {
        await SetRefreshRateAsync(120);
    }

    private async Task SetRefreshRateAsync(int refreshRate)
    {
        if (_isDisplayActionRunning)
        {
            return;
        }

        _isDisplayActionRunning = true;
        SetDisplayControlsEnabled(false);
        RefreshRateText.Text = $"Switching to {refreshRate} Hz...";

        try
        {
            var result = await Task.Run(() => StudioDisplayController.SetRefreshRate(refreshRate));
            RefreshRateText.Text = result;
            await Task.Delay(1200);
        }
        catch (Exception ex)
        {
            RefreshRateText.Text = $"Could not switch refresh rate: {ex.Message}";
        }
        finally
        {
            _isDisplayActionRunning = false;
            RefreshDisplayState();
        }
    }

    private async void HdrToggle_OnChanged(object sender, RoutedEventArgs e)
    {
        if (_isUpdatingHdrToggle || _isDisplayActionRunning)
        {
            return;
        }

        _isDisplayActionRunning = true;
        SetDisplayControlsEnabled(false);
        var enable = HdrToggle.IsChecked == true;
        HdrText.Text = enable ? "Turning HDR on..." : "Turning HDR off...";

        try
        {
            var result = await Task.Run(() => StudioDisplayController.SetAdvancedColor(enable));
            HdrText.Text = result;
            await Task.Delay(900);
        }
        catch (Exception ex)
        {
            HdrText.Text = $"Could not change HDR state: {ex.Message}";
        }
        finally
        {
            _isDisplayActionRunning = false;
            RefreshDisplayState();
        }
    }

    private void SetDisplayControlsEnabled(bool enabled)
    {
        var effective = enabled && !_isDisplayActionRunning;
        OptimizeSignalButton.IsEnabled = effective;
        RefreshSignalButton.IsEnabled = effective;
        Refresh60Button.IsEnabled = effective;
        Refresh120Button.IsEnabled = effective;
        HdrToggle.IsEnabled = effective && HdrToggle.IsEnabled;
    }

    private void RefreshColorProfileState()
    {
        try
        {
            var status = StudioColorProfileController.GetStatus();
            InstallColorProfileButton.IsEnabled = status.BundledProfileExists && !_isColorActionRunning;
            CheckColorProfileButton.IsEnabled = !_isColorCheckRunning;
            InstallColorProfileButton.Content = status.InstalledProfileExists ? "Reinstall" : "Install";
            ColorProfileText.Text = status.InstalledProfileExists
                ? "Generated Display P3 profile is installed. This is not an Apple reference mode."
                : status.BundledProfileExists
                    ? "Generated Display P3 profile is available. Install it for Windows color-managed apps."
                    : "Generated Display P3 profile was not found in the package.";
        }
        catch (Exception ex)
        {
            InstallColorProfileButton.IsEnabled = false;
            CheckColorProfileButton.IsEnabled = false;
            ColorProfileText.Text = $"Could not check color profile: {ex.Message}";
        }
    }

    private async void InstallColorProfileButton_OnClick(object sender, RoutedEventArgs e)
    {
        if (_isColorActionRunning)
        {
            return;
        }

        _isColorActionRunning = true;
        InstallColorProfileButton.IsEnabled = false;
        ColorProfileText.Text = "Installing generated Display P3 profile...";

        try
        {
            var result = await Task.Run(StudioColorProfileController.InstallBundledProfile);
            ColorProfileText.Text = result;
        }
        catch (Exception ex)
        {
            ColorProfileText.Text = $"Could not install color profile: {ex.Message}";
        }
        finally
        {
            _isColorActionRunning = false;
            RefreshColorProfileState();
        }
    }

    private async void CheckColorProfileButton_OnClick(object sender, RoutedEventArgs e)
    {
        if (_isColorCheckRunning)
        {
            return;
        }

        _isColorCheckRunning = true;
        CheckColorProfileButton.IsEnabled = false;
        ColorProfileText.Text = "Checking local color profiles...";

        try
        {
            var json = await Task.Run(RunColorProfileDiscovery);
            ColorProfileText.Text = SummarizeColorProfileDiscovery(json);
        }
        catch (Exception ex)
        {
            ColorProfileText.Text = $"Could not check color profiles: {ex.Message}";
        }
        finally
        {
            _isColorCheckRunning = false;
            CheckColorProfileButton.IsEnabled = true;
        }
    }

    private static string RunColorProfileDiscovery()
    {
        var root = FindPackageRoot();
        var script = Path.Combine(root, "scripts", "Find-StudioXdrColorProfiles.ps1");
        if (!File.Exists(script))
        {
            throw new FileNotFoundException("Color profile discovery script was not found.", script);
        }

        var startInfo = new ProcessStartInfo
        {
            FileName = "powershell.exe",
            Arguments = $"-NoProfile -ExecutionPolicy Bypass -File {QuoteArg(script)} -IncludeUserFolders -Json",
            WorkingDirectory = root,
            UseShellExecute = false,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            CreateNoWindow = true
        };

        using var process = Process.Start(startInfo) ?? throw new InvalidOperationException("Could not start PowerShell.");
        var output = process.StandardOutput.ReadToEnd();
        var error = process.StandardError.ReadToEnd();
        process.WaitForExit();

        if (process.ExitCode != 0)
        {
            var detail = string.IsNullOrWhiteSpace(error) ? output : error;
            throw new InvalidOperationException(string.IsNullOrWhiteSpace(detail) ? "Color profile discovery command failed." : detail.Trim());
        }

        return output;
    }

    private static string SummarizeColorProfileDiscovery(string json)
    {
        using var document = JsonDocument.Parse(string.IsNullOrWhiteSpace(json) ? "[]" : json);
        var elements = document.RootElement.ValueKind == JsonValueKind.Array
            ? document.RootElement.EnumerateArray().ToArray()
            : [document.RootElement];

        var validProfiles = elements.Length;
        var bundled = elements.Count(profile => HasRelevance(profile, "Bundled"));
        var appleCandidates = elements
            .Where(profile => !HasRelevance(profile, "Bundled") && !HasRelevance(profile, "Generated") && (HasRelevance(profile, "Apple") || HasRelevance(profile, "ProDisplay")))
            .ToArray();
        var wideColorCandidates = elements
            .Where(profile => !HasRelevance(profile, "Bundled") && !HasRelevance(profile, "Generated") && (HasRelevance(profile, "P3") || HasRelevance(profile, "Adobe") || HasRelevance(profile, "HDR")))
            .ToArray();

        if (appleCandidates.Length > 0)
        {
            var first = ProfileLabel(appleCandidates[0]);
            return $"Color check found {appleCandidates.Length} Apple/Pro Display candidate profile(s). First: {first}. Validate before installing.";
        }

        if (wideColorCandidates.Length > 0)
        {
            var first = ProfileLabel(wideColorCandidates[0]);
            return $"Color check found {wideColorCandidates.Length} non-bundled wide-color/HDR candidate profile(s). First: {first}. Validate before installing.";
        }

        if (bundled > 0)
        {
            return $"Color check found no Apple-authored Studio/Pro Display profile. Bundled generated Display P3 baseline is available; {validProfiles} valid profile(s) scanned.";
        }

        return $"Color check found {validProfiles} valid profile(s), but no Studio Display XDR candidate.";
    }

    private static bool HasRelevance(JsonElement profile, string value)
    {
        if (!profile.TryGetProperty("Relevance", out var relevanceElement))
        {
            return false;
        }

        var relevance = relevanceElement.GetString() ?? "";
        return relevance.Split(',', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries)
            .Any(item => item.Equals(value, StringComparison.OrdinalIgnoreCase));
    }

    private static string ProfileLabel(JsonElement profile)
    {
        var description = GetJsonString(profile, "Description");
        if (!string.IsNullOrWhiteSpace(description))
        {
            return description;
        }

        var name = GetJsonString(profile, "Name");
        return string.IsNullOrWhiteSpace(name) ? "unknown profile" : name;
    }

    private static string GetJsonString(JsonElement profile, string propertyName)
    {
        return profile.TryGetProperty(propertyName, out var value) ? value.GetString() ?? "" : "";
    }

    private async void CheckReadinessButton_OnClick(object sender, RoutedEventArgs e)
    {
        if (_isReadinessCheckRunning || _isDiagnosticActionRunning)
        {
            return;
        }

        _isReadinessCheckRunning = true;
        SetDiagnosticsControlsEnabled(false);
        DiagnosticsText.Text = "Running readiness check...";

        try
        {
            var json = await Task.Run(RunReadinessCheck);
            DiagnosticsText.Text = SummarizeReadinessCheck(json);
        }
        catch (Exception ex)
        {
            DiagnosticsText.Text = $"Could not run readiness check: {ex.Message}";
        }
        finally
        {
            _isReadinessCheckRunning = false;
            SetDiagnosticsControlsEnabled(true);
        }
    }

    private static string RunReadinessCheck()
    {
        var root = FindPackageRoot();
        var script = Path.Combine(root, "scripts", "Test-StudioXdrReadiness.ps1");
        if (!File.Exists(script))
        {
            throw new FileNotFoundException("Readiness check script was not found.", script);
        }

        var startInfo = new ProcessStartInfo
        {
            FileName = "powershell.exe",
            Arguments = $"-NoProfile -ExecutionPolicy Bypass -File {QuoteArg(script)} -Json",
            WorkingDirectory = root,
            UseShellExecute = false,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            CreateNoWindow = true
        };

        using var process = Process.Start(startInfo) ?? throw new InvalidOperationException("Could not start PowerShell.");
        var output = process.StandardOutput.ReadToEnd();
        var error = process.StandardError.ReadToEnd();
        process.WaitForExit();

        if (process.ExitCode != 0)
        {
            var detail = string.IsNullOrWhiteSpace(error) ? output : error;
            throw new InvalidOperationException(string.IsNullOrWhiteSpace(detail) ? "Readiness check command failed." : detail.Trim());
        }

        return output;
    }

    private static string SummarizeReadinessCheck(string json)
    {
        using var document = JsonDocument.Parse(string.IsNullOrWhiteSpace(json) ? "{}" : json);
        var root = document.RootElement;
        if (!root.TryGetProperty("Summary", out var summary))
        {
            return "Readiness check completed.";
        }

        var pass = GetJsonInt(summary, "Pass");
        var warn = GetJsonInt(summary, "Warn");
        var fail = GetJsonInt(summary, "Fail");
        var info = GetJsonInt(summary, "Info");
        var result = GetJsonString(summary, "Result");
        var firstIssue = FirstReadinessIssue(root);

        var counts = $"{pass} pass, {warn} warning, {fail} fail, {info} info";
        if (!string.IsNullOrWhiteSpace(firstIssue))
        {
            return $"Readiness check: {result}; {counts}. First issue: {firstIssue}";
        }

        return $"Readiness check: {result}; {counts}.";
    }

    private static string FirstReadinessIssue(JsonElement root)
    {
        if (!root.TryGetProperty("Checks", out var checks) || checks.ValueKind != JsonValueKind.Array)
        {
            return "";
        }

        foreach (var desiredStatus in new[] { "Fail", "Warn" })
        {
            foreach (var check in checks.EnumerateArray())
            {
                var status = GetJsonString(check, "Status");
                if (!status.Equals(desiredStatus, StringComparison.OrdinalIgnoreCase))
                {
                    continue;
                }

                var area = GetJsonString(check, "Area");
                var detail = GetJsonString(check, "Detail");
                return string.IsNullOrWhiteSpace(detail) ? area : $"{area}: {detail}";
            }
        }

        return "";
    }

    private static int GetJsonInt(JsonElement element, string propertyName)
    {
        return element.TryGetProperty(propertyName, out var value) && value.TryGetInt32(out var result)
            ? result
            : 0;
    }

    private async void GenerateReportButton_OnClick(object sender, RoutedEventArgs e)
    {
        if (_isDiagnosticActionRunning || _isReadinessCheckRunning)
        {
            return;
        }

        _isDiagnosticActionRunning = true;
        SetDiagnosticsControlsEnabled(false);
        DiagnosticsText.Text = "Generating support report...";

        try
        {
            var reportPath = await Task.Run(GenerateSupportReport);
            DiagnosticsText.Text = $"Report saved: {reportPath}";
        }
        catch (Exception ex)
        {
            DiagnosticsText.Text = $"Could not generate report: {ex.Message}";
        }
        finally
        {
            _isDiagnosticActionRunning = false;
            SetDiagnosticsControlsEnabled(true);
        }
    }

    private void SetDiagnosticsControlsEnabled(bool enabled)
    {
        var effective = enabled && !_isDiagnosticActionRunning && !_isReadinessCheckRunning;
        CheckReadinessButton.IsEnabled = effective;
        GenerateReportButton.IsEnabled = effective;
    }

    private static string GenerateSupportReport()
    {
        var root = FindPackageRoot();
        var script = Path.Combine(root, "scripts", "Get-StudioXdrSupportReport.ps1");
        if (!File.Exists(script))
        {
            throw new FileNotFoundException("Support report script was not found.", script);
        }

        var reports = Path.Combine(root, "reports");
        Directory.CreateDirectory(reports);
        var reportPath = Path.Combine(reports, $"studio-xdr-support-{DateTime.Now:yyyyMMdd-HHmmss}.txt");

        var startInfo = new ProcessStartInfo
        {
            FileName = "powershell.exe",
            Arguments = $"-NoProfile -ExecutionPolicy Bypass -File {QuoteArg(script)} -OutputPath {QuoteArg(reportPath)}",
            WorkingDirectory = root,
            UseShellExecute = false,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            CreateNoWindow = true
        };

        using var process = Process.Start(startInfo) ?? throw new InvalidOperationException("Could not start PowerShell.");
        var output = process.StandardOutput.ReadToEnd();
        var error = process.StandardError.ReadToEnd();
        process.WaitForExit();

        if (process.ExitCode != 0 || !File.Exists(reportPath))
        {
            var detail = string.IsNullOrWhiteSpace(error) ? output : error;
            throw new InvalidOperationException(string.IsNullOrWhiteSpace(detail) ? "Support report command failed." : detail.Trim());
        }

        return Path.GetRelativePath(root, reportPath);
    }

    private async void AmbientCheckButton_OnClick(object sender, RoutedEventArgs e)
    {
        if (_isAmbientCheckRunning)
        {
            return;
        }

        _isAmbientCheckRunning = true;
        AmbientCheckButton.IsEnabled = false;
        AutoBrightnessText.Text = "Checking ambient brightness sources...";

        try
        {
            AutoBrightnessText.Text = await Task.Run(RunAmbientCheck);
        }
        catch (Exception ex)
        {
            AutoBrightnessText.Text = $"Could not run ambient check: {ex.Message}";
        }
        finally
        {
            _isAmbientCheckRunning = false;
            AmbientCheckButton.IsEnabled = true;
        }
    }

    private static string RunAmbientCheck()
    {
        var preflight = RunAmbientPreflight();
        var text = SummarizeAmbientPreflight(preflight);
        var signing = RunAmbientDriverPackageSigningCheck();
        var signingSummary = SummarizeAmbientDriverPackageSigning(signing);
        return string.IsNullOrWhiteSpace(signingSummary)
            ? text
            : $"{text} {signingSummary}";
    }

    private static string RunAmbientPreflight()
    {
        var root = FindPackageRoot();
        var script = Path.Combine(root, "scripts", "Test-StudioXdrAmbientPreflight.ps1");
        if (!File.Exists(script))
        {
            throw new FileNotFoundException("Ambient preflight script was not found.", script);
        }

        var startInfo = new ProcessStartInfo
        {
            FileName = "powershell.exe",
            Arguments = $"-NoProfile -ExecutionPolicy Bypass -File {QuoteArg(script)} -Json",
            WorkingDirectory = root,
            UseShellExecute = false,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            CreateNoWindow = true
        };

        using var process = Process.Start(startInfo) ?? throw new InvalidOperationException("Could not start PowerShell.");
        var output = process.StandardOutput.ReadToEnd();
        var error = process.StandardError.ReadToEnd();
        process.WaitForExit();

        if (process.ExitCode != 0)
        {
            var detail = string.IsNullOrWhiteSpace(error) ? output : error;
            throw new InvalidOperationException(string.IsNullOrWhiteSpace(detail) ? "Ambient preflight command failed." : detail.Trim());
        }

        return output;
    }

    private static string RunAmbientDriverPackageSigningCheck()
    {
        var root = FindPackageRoot();
        var script = Path.Combine(root, "scripts", "New-StudioXdrAmbientDriverPackage.ps1");
        if (!File.Exists(script))
        {
            return "";
        }

        var startInfo = new ProcessStartInfo
        {
            FileName = "powershell.exe",
            Arguments = $"-NoProfile -ExecutionPolicy Bypass -File {QuoteArg(script)} -CheckOnly -Json",
            WorkingDirectory = root,
            UseShellExecute = false,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            CreateNoWindow = true
        };

        using var process = Process.Start(startInfo) ?? throw new InvalidOperationException("Could not start PowerShell.");
        var output = process.StandardOutput.ReadToEnd();
        process.StandardError.ReadToEnd();
        process.WaitForExit();

        return process.ExitCode == 0 ? output : "";
    }

    private static string SummarizeAmbientPreflight(string output)
    {
        using var document = JsonDocument.Parse(string.IsNullOrWhiteSpace(output) ? "{}" : output);
        var root = document.RootElement;
        if (!root.TryGetProperty("Summary", out var summary))
        {
            return "Ambient check completed. See Check-Ambient.cmd for detailed driver state.";
        }

        var verdict = GetJsonString(summary, "Verdict");
        var target = GetJsonString(summary, "ExactFilterTarget");
        if (string.IsNullOrWhiteSpace(verdict))
        {
            return "Ambient check completed. See Check-Ambient.cmd for detailed driver state.";
        }

        var text = $"Ambient check: {verdict}";
        if (!string.IsNullOrWhiteSpace(target) && target.Contains("USB\\VID_05AC", StringComparison.OrdinalIgnoreCase))
        {
            text = $"{text} Target: {target}.";
        }

        var driverTarget = SummarizeAmbientDriverTarget(root);
        if (!string.IsNullOrWhiteSpace(driverTarget))
        {
            text = $"{text} {driverTarget}";
        }

        return text;
    }

    private static string SummarizeAmbientDriverTarget(JsonElement root)
    {
        if (!root.TryGetProperty("Checks", out var checks) || checks.ValueKind != JsonValueKind.Array)
        {
            return "";
        }

        foreach (var check in checks.EnumerateArray())
        {
            if (!GetJsonString(check, "Area").Equals("Ambient WinUSB package target", StringComparison.OrdinalIgnoreCase))
            {
                continue;
            }

            var status = GetJsonString(check, "Status");
            var detail = GetJsonString(check, "Detail");
            if (status.Equals("Ready", StringComparison.OrdinalIgnoreCase))
            {
                return "WinUSB connector is active.";
            }

            if (detail.Contains("matches", StringComparison.OrdinalIgnoreCase) &&
                detail.Contains("not installed or bound", StringComparison.OrdinalIgnoreCase))
            {
                return detail.Contains("Windows matching drivers", StringComparison.OrdinalIgnoreCase)
                    ? "WinUSB package matches MI_08, but Windows is still choosing HidUsb/input.inf."
                    : "WinUSB package matches MI_08; Windows is still using HidUsb.";
            }

            if (status.Equals("Warn", StringComparison.OrdinalIgnoreCase))
            {
                return "WinUSB package target needs review.";
            }

            return "";
        }

        return "";
    }

    private static string SummarizeAmbientDriverPackageSigning(string output)
    {
        if (string.IsNullOrWhiteSpace(output))
        {
            return "";
        }

        using var document = JsonDocument.Parse(output);
        var root = document.RootElement;
        var ready = GetJsonBool(root, "Ready");
        var catalogExists = GetJsonBool(root, "CatalogExists");
        var inf2CatPath = GetJsonString(root, "Inf2CatPath");
        var signToolPath = GetJsonString(root, "SignToolPath");
        var thumbprint = GetJsonString(root, "CertificateThumbprint");

        if (ready && catalogExists)
        {
            return string.IsNullOrWhiteSpace(thumbprint)
                ? "Prepare Ambient: catalog exists."
                : "Prepare Ambient: catalog and test certificate are ready.";
        }

        if (string.IsNullOrWhiteSpace(inf2CatPath) || string.IsNullOrWhiteSpace(signToolPath))
        {
            return "Prepare Ambient: WDK signing tools are missing and the WinUSB catalog has not been generated.";
        }

        if (!catalogExists)
        {
            return "Prepare Ambient: WinUSB catalog has not been generated yet.";
        }

        if (string.IsNullOrWhiteSpace(thumbprint))
        {
            return "Prepare Ambient: catalog exists, but no local test-signing certificate was found.";
        }

        return "Prepare Ambient: catalog/signing state needs review.";
    }

    private static bool GetJsonBool(JsonElement element, string propertyName)
    {
        return element.TryGetProperty(propertyName, out var value) &&
            value.ValueKind is JsonValueKind.True or JsonValueKind.False &&
            value.GetBoolean();
    }

    private static string FindPackageRoot()
    {
        var candidates = new[]
        {
            AppContext.BaseDirectory,
            Path.Combine(AppContext.BaseDirectory, ".."),
            Path.Combine(AppContext.BaseDirectory, "..", ".."),
            Environment.CurrentDirectory,
            Path.Combine(Environment.CurrentDirectory, ".."),
            Path.Combine(Environment.CurrentDirectory, "..", "..")
        };

        foreach (var candidate in candidates)
        {
            var fullPath = Path.GetFullPath(candidate);
            if (File.Exists(Path.Combine(fullPath, "scripts", "Get-StudioXdrSupportReport.ps1")))
            {
                return fullPath;
            }
        }

        return Path.GetFullPath(Path.Combine(AppContext.BaseDirectory, "..", ".."));
    }

    private static string QuoteArg(string value)
    {
        return $"\"{value.Replace("\"", "\\\"")}\"";
    }

    private void BrightnessSlider_OnValueChanged(object sender, RoutedPropertyChangedEventArgs<double> e)
    {
        if (_isLoadingDisplays || sender is not FrameworkElement { DataContext: DisplayBrightnessViewModel display } || !display.AcceptWrites)
        {
            return;
        }

        display.Status = "Updating brightness...";

        if (!_writeTimers.TryGetValue(display, out var timer))
        {
            timer = new DispatcherTimer
            {
                Interval = TimeSpan.FromMilliseconds(90)
            };
            timer.Tick += (_, _) => WriteBrightness(display);
            _writeTimers[display] = timer;
        }

        timer.Stop();
        timer.Start();
    }

    private void WriteBrightness(DisplayBrightnessViewModel display)
    {
        if (!_writeTimers.TryGetValue(display, out var timer))
        {
            return;
        }

        timer.Stop();

        try
        {
            StudioBrightnessDevice.SetPercent(display.DevicePath, (int)Math.Round(display.Percent));
            display.Status = "Brightness updated.";
        }
        catch (Exception ex)
        {
            display.Status = $"Could not update brightness: {ex.Message}";
        }
    }

    private void StartupToggle_OnChanged(object sender, RoutedEventArgs e)
    {
        if (_isUpdatingStartup)
        {
            return;
        }

        try
        {
            StartupManager.SetEnabled(StartupToggle.IsChecked == true);
            StartupText.Text = StartupToggle.IsChecked == true
                ? "Studio Display XDR will start in the notification area after Windows starts."
                : "Keep display brightness available after Windows starts.";
        }
        catch (Exception ex)
        {
            StartupText.Text = $"Could not update startup preference: {ex.Message}";
            RefreshStartupState();
        }
    }

    private void RefreshStartupState()
    {
        _isUpdatingStartup = true;
        try
        {
            var enabled = StartupManager.IsEnabled();
            StartupToggle.IsChecked = enabled;
            StartupText.Text = enabled
                ? "Studio Display XDR will start in the notification area after Windows starts."
                : "Keep display brightness available after Windows starts.";
        }
        catch (Exception ex)
        {
            StartupText.Text = $"Could not read startup preference: {ex.Message}";
        }
        finally
        {
            _isUpdatingStartup = false;
        }
    }

    private void RefreshPackageInfo()
    {
        try
        {
            AboutText.Text = GetPackageInfoText();
            CopyAboutButton.IsEnabled = true;
        }
        catch (Exception ex)
        {
            AboutText.Text = $"Package metadata unavailable: {ex.Message}";
            CopyAboutButton.IsEnabled = false;
        }
    }

    private void CopyAboutButton_OnClick(object sender, RoutedEventArgs e)
    {
        try
        {
            System.Windows.Clipboard.SetText(AboutText.Text);
            AboutText.Text = $"{GetPackageInfoText()} Copied.";
        }
        catch (Exception ex)
        {
            AboutText.Text = $"Could not copy package metadata: {ex.Message}";
        }
    }

    private static string GetPackageInfoText()
    {
        var root = FindPackageRoot();
        var packageJson = Path.Combine(root, "PACKAGE.json");
        if (!File.Exists(packageJson))
        {
            return "Development build; PACKAGE.json has not been generated yet.";
        }

        using var document = JsonDocument.Parse(File.ReadAllText(packageJson));
        var package = document.RootElement;
        var builtAt = FormatPackageDate(GetJsonString(package, "builtAt"));
        var branch = GetJsonString(package, "gitBranch");
        var commit = GetJsonString(package, "gitCommit");
        var dirty = package.TryGetProperty("gitDirty", out var dirtyElement) &&
            dirtyElement.ValueKind is JsonValueKind.True or JsonValueKind.False &&
            dirtyElement.GetBoolean();
        var runtime = GetJsonString(package, "appRuntime");
        var version = GetJsonString(package, "version");

        var commitShort = commit.Length > 12 ? commit[..12] : commit;
        var source = string.IsNullOrWhiteSpace(branch) && string.IsNullOrWhiteSpace(commitShort)
            ? "source unavailable"
            : $"{branch} {commitShort}".Trim();
        var state = dirty ? "modified working tree" : "clean source";
        var runtimeText = string.IsNullOrWhiteSpace(runtime) ? "runtime unknown" : runtime;
        var versionText = string.IsNullOrWhiteSpace(version) ? "Package" : $"Package v{version}";

        return $"{versionText} built {builtAt}; {runtimeText}; {source}; {state}.";
    }

    private static string FormatPackageDate(string builtAt)
    {
        if (DateTimeOffset.TryParse(builtAt, out var parsed))
        {
            return parsed.ToLocalTime().ToString("yyyy-MM-dd HH:mm");
        }

        return string.IsNullOrWhiteSpace(builtAt) ? "unknown time" : builtAt;
    }

    private async Task RefreshAmbientStateAsync()
    {
        _isUpdatingAutoToggle = true;
        _autoBrightnessTimer.Stop();
        AutoBrightnessToggle.IsChecked = false;
        AutoBrightnessToggle.IsEnabled = false;
        AutoBrightnessText.Text = "Checking ambient sources...";

        try
        {
            var availability = await AmbientLightController.GetAvailabilityAsync();
            AutoBrightnessToggle.IsEnabled = availability.HasSource;
            AutoBrightnessText.Text = availability.Message;

            if (availability.HasSource && _settings.AutoBrightnessEnabled)
            {
                AutoBrightnessToggle.IsChecked = true;
                AutoBrightnessText.Text = "Starting automatic brightness...";
                _autoBrightnessTimer.Start();
                _ = RunAutoBrightnessTickAsync();
            }
        }
        catch (Exception ex)
        {
            AutoBrightnessToggle.IsEnabled = false;
            AutoBrightnessText.Text = $"Could not check ambient sources: {ex.Message}";
        }
        finally
        {
            _isUpdatingAutoToggle = false;
        }
    }

    private void AutoBrightnessToggle_OnChanged(object sender, RoutedEventArgs e)
    {
        if (_isUpdatingAutoToggle)
        {
            return;
        }

        if (AutoBrightnessToggle.IsChecked == true)
        {
            _settings.AutoBrightnessEnabled = true;
            _settings.Save();
            AutoBrightnessText.Text = "Starting automatic brightness...";
            _autoBrightnessTimer.Start();
            _ = RunAutoBrightnessTickAsync();
            return;
        }

        _autoBrightnessTimer.Stop();
        _settings.AutoBrightnessEnabled = false;
        _settings.Save();
        _ = DisposeAmbientControllerAsync();
        _ = RefreshAmbientStateAsync();
    }

    private void RefreshAutoBrightnessSettings()
    {
        _isLoadingSettings = true;
        try
        {
            _settings.Normalize();
            AutoMinimumSlider.Value = _settings.AutoMinimumBrightnessPercent;
            AutoMaximumSlider.Value = _settings.AutoMaximumBrightnessPercent;
            AutoResponseSlider.Value = _settings.AutoResponsePercent;
            AutoMinimumText.Text = $"{_settings.AutoMinimumBrightnessPercent}%";
            AutoMaximumText.Text = $"{_settings.AutoMaximumBrightnessPercent}%";
            AutoResponseText.Text = $"{_settings.AutoResponsePercent}%";
        }
        finally
        {
            _isLoadingSettings = false;
        }
    }

    private void AutoMinimumSlider_OnValueChanged(object sender, RoutedPropertyChangedEventArgs<double> e)
    {
        if (_isLoadingSettings)
        {
            return;
        }

        _settings.AutoMinimumBrightnessPercent = (int)Math.Round(AutoMinimumSlider.Value);
        _settings.Normalize();
        _settings.Save();
        RefreshAutoBrightnessSettings();
    }

    private void AutoMaximumSlider_OnValueChanged(object sender, RoutedPropertyChangedEventArgs<double> e)
    {
        if (_isLoadingSettings)
        {
            return;
        }

        _settings.AutoMaximumBrightnessPercent = (int)Math.Round(AutoMaximumSlider.Value);
        _settings.Normalize();
        _settings.Save();
        RefreshAutoBrightnessSettings();
    }

    private void AutoResponseSlider_OnValueChanged(object sender, RoutedPropertyChangedEventArgs<double> e)
    {
        if (_isLoadingSettings)
        {
            return;
        }

        _settings.AutoResponsePercent = (int)Math.Round(AutoResponseSlider.Value);
        _settings.Normalize();
        _settings.Save();
        RefreshAutoBrightnessSettings();
    }

    private void AutoBrightnessTimer_OnTick(object? sender, EventArgs e)
    {
        _ = RunAutoBrightnessTickAsync();
    }

    private async Task RunAutoBrightnessTickAsync()
    {
        if (_isAutoBrightnessTickRunning || _displays.Count == 0)
        {
            return;
        }

        _isAutoBrightnessTickRunning = true;
        try
        {
            var reading = await Task.Run(() =>
            {
                _ambientLightController ??= new AmbientLightController();
                return _ambientLightController.ReadAsync().GetAwaiter().GetResult();
            });

            if (reading is null)
            {
                AutoBrightnessText.Text = "Waiting for an ambient source...";
                return;
            }

            if (!reading.IsReliable)
            {
                AutoBrightnessText.Text = $"Automatic brightness paused. {reading.Source}: {reading.Detail}.";
                return;
            }

            var target = AmbientReadingToPercent(reading.Value, reading.MinimumBrightnessPercent);
            foreach (var display in _displays.Where(display => !string.IsNullOrWhiteSpace(display.DevicePath)))
            {
                var current = display.Percent;
                var smoothed = current + Math.Max(-4, Math.Min(4, target - current));
                StudioBrightnessDevice.SetPercent(display.DevicePath, (int)Math.Round(smoothed));
                display.Percent = smoothed;
                display.Status = $"Auto brightness from {reading.Source}.";
            }

            AutoBrightnessText.Text = $"Automatic brightness on. {reading.Source}: {reading.Detail}, target: {target}%.";
        }
        catch (Exception ex)
        {
            _autoBrightnessTimer.Stop();
            _ = DisposeAmbientControllerAsync();
            _isUpdatingAutoToggle = true;
            AutoBrightnessToggle.IsChecked = false;
            _isUpdatingAutoToggle = false;
            _settings.AutoBrightnessEnabled = false;
            _settings.Save();
            AutoBrightnessText.Text = $"Automatic brightness stopped: {ex.Message}";
        }
        finally
        {
            _isAutoBrightnessTickRunning = false;
        }
    }

    private int AmbientReadingToPercent(int reading, int minimumPercent)
    {
        var normalized = Math.Max(0, Math.Min(1, reading / 1_000_000.0));
        var response = Math.Clamp(_settings.AutoResponsePercent / 100.0, 0.5, 1.6);
        var adjusted = Math.Clamp(normalized * response, 0, 1);
        var curved = Math.Pow(adjusted, 0.48);
        var minimum = Math.Max(_settings.AutoMinimumBrightnessPercent, minimumPercent);
        var maximum = Math.Max(minimum + 5, _settings.AutoMaximumBrightnessPercent);
        return Math.Max(minimum, Math.Min(maximum, (int)Math.Round(minimum + ((maximum - minimum) * curved))));
    }

    private async Task DisposeAmbientControllerAsync()
    {
        var controller = _ambientLightController;
        _ambientLightController = null;
        if (controller is not null)
        {
            await controller.DisposeAsync();
        }
    }

    private void SetConnectedState(bool connected)
    {
        if (connected)
        {
            ConnectionPill.Background = BrushFromHex("#E8F5E9");
            ConnectionDot.Fill = BrushFromHex("#34C759");
            ConnectionText.Text = "Connected";
            SubtitleText.Text = "Brightness";
            return;
        }

        ConnectionPill.Background = BrushFromHex("#FFF3E0");
        ConnectionDot.Fill = BrushFromHex("#FF9500");
        ConnectionText.Text = "Not found";
        SubtitleText.Text = "Connect over Thunderbolt or USB4";
    }

    private static SolidColorBrush BrushFromHex(string color)
    {
        return new SolidColorBrush((System.Windows.Media.Color)System.Windows.Media.ColorConverter.ConvertFromString(color));
    }
}

internal sealed class DisplayBrightnessViewModel : INotifyPropertyChanged
{
    private double _percent;
    private string _status;

    private DisplayBrightnessViewModel(string devicePath, string title, string detail, double percent, string status)
    {
        DevicePath = devicePath;
        Title = title;
        Detail = detail;
        _percent = percent;
        _status = status;
    }

    public event PropertyChangedEventHandler? PropertyChanged;

    public string DevicePath { get; }
    public string Title { get; }
    public string Detail { get; }
    public bool AcceptWrites { get; set; }

    public double Percent
    {
        get => _percent;
        set
        {
            var clamped = Math.Max(0, Math.Min(100, Math.Round(value)));
            if (Math.Abs(_percent - clamped) < 0.01)
            {
                return;
            }

            _percent = clamped;
            OnPropertyChanged();
            OnPropertyChanged(nameof(PercentLabel));
        }
    }

    public string PercentLabel => $"{(int)Math.Round(Percent)}%";

    public string Status
    {
        get => _status;
        set
        {
            if (_status == value)
            {
                return;
            }

            _status = value;
            OnPropertyChanged();
        }
    }

    public static DisplayBrightnessViewModel Error(string message)
    {
        return new DisplayBrightnessViewModel("", "Brightness unavailable", message, 0, "Connect the display and relaunch.");
    }

    public DisplayBrightnessViewModel(StudioBrightnessDevice device, string title)
        : this(
            device.Path,
            title,
            "USB 05AC:1116 brightness control",
            Math.Max(0, Math.Min(100, device.Percent)),
            "Ready")
    {
    }

    private void OnPropertyChanged([CallerMemberName] string? propertyName = null)
    {
        PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(propertyName));
    }
}
