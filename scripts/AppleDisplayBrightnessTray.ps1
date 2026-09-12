$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "AppleDisplayBrightnessCore.ps1")

Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName WindowsBase

function Get-StudioDisplayDevice {
    @(Get-AppleDisplayBrightnessDevice | Where-Object { $_.ProductId -eq "1116" } | Select-Object -First 1)
}

function Test-StudioUsb4Present {
    $device = Get-PnpDevice -PresentOnly -ErrorAction SilentlyContinue |
        Where-Object { $_.InstanceId -match "USB4\\VID_8087&PID_5786" -or $_.FriendlyName -eq "USB4 Router (2.0), Apple - Studio Display XDR" } |
        Select-Object -First 1
    return [bool]$device
}

function Test-StudioSensorPresent {
    $sensor = Get-PnpDevice -Class Sensor -PresentOnly -ErrorAction SilentlyContinue |
        Where-Object { $_.InstanceId -match "VID_05AC&PID_1116" -and $_.FriendlyName -match "Ambient Light" -and $_.Status -eq "OK" } |
        Select-Object -First 1
    return [bool]$sensor
}

$xaml = @"
<Window
    xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
    xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
    Title="Studio Display XDR"
    Width="560"
    Height="430"
    ResizeMode="NoResize"
    WindowStartupLocation="CenterScreen"
    Background="#F5F5F7"
    FontFamily="Segoe UI">
    <Window.Resources>
        <Style TargetType="TextBlock">
            <Setter Property="Foreground" Value="#1D1D1F"/>
        </Style>
        <Style x:Key="MutedText" TargetType="TextBlock">
            <Setter Property="Foreground" Value="#6E6E73"/>
            <Setter Property="FontSize" Value="13"/>
        </Style>
        <Style x:Key="SectionTitle" TargetType="TextBlock">
            <Setter Property="Foreground" Value="#1D1D1F"/>
            <Setter Property="FontSize" Value="14"/>
            <Setter Property="FontWeight" Value="SemiBold"/>
        </Style>
        <Style TargetType="Slider">
            <Setter Property="IsSnapToTickEnabled" Value="True"/>
            <Setter Property="TickFrequency" Value="1"/>
            <Setter Property="Height" Value="32"/>
        </Style>
    </Window.Resources>

    <Grid Margin="28">
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="20"/>
            <RowDefinition Height="116"/>
            <RowDefinition Height="20"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="18"/>
            <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>

        <Grid Grid.Row="0">
            <Grid.ColumnDefinitions>
                <ColumnDefinition Width="*"/>
                <ColumnDefinition Width="Auto"/>
            </Grid.ColumnDefinitions>
            <StackPanel>
                <TextBlock Text="Studio Display XDR" FontSize="27" FontWeight="SemiBold"/>
                <TextBlock x:Name="SubtitleText" Text="Checking display connection..." Style="{StaticResource MutedText}" Margin="0,4,0,0"/>
            </StackPanel>
            <Border Grid.Column="1" x:Name="ConnectionPill" Background="#E8F5E9" CornerRadius="8" Padding="12,7" VerticalAlignment="Top">
                <StackPanel Orientation="Horizontal">
                    <Ellipse x:Name="ConnectionDot" Width="8" Height="8" Fill="#34C759" Margin="0,0,7,0"/>
                    <TextBlock x:Name="ConnectionText" Text="Connected" FontSize="12" FontWeight="SemiBold" Foreground="#1D1D1F"/>
                </StackPanel>
            </Border>
        </Grid>

        <Border Grid.Row="2" Background="#FFFFFF" CornerRadius="8" BorderBrush="#D9D9DE" BorderThickness="1" Padding="18">
            <Grid>
                <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="138"/>
                    <ColumnDefinition Width="*"/>
                </Grid.ColumnDefinitions>

                <Grid Width="112" Height="76" VerticalAlignment="Center" HorizontalAlignment="Center">
                    <Border Width="104" Height="58" CornerRadius="7" Background="#111114" BorderBrush="#3A3A40" BorderThickness="2" VerticalAlignment="Top"/>
                    <Border Width="74" Height="42" CornerRadius="3" Background="#303038" VerticalAlignment="Top" Margin="0,8,0,0"/>
                    <Rectangle Width="12" Height="16" Fill="#8E8E93" VerticalAlignment="Bottom" Margin="0,0,0,10"/>
                    <Border Width="54" Height="6" CornerRadius="3" Background="#8E8E93" VerticalAlignment="Bottom"/>
                </Grid>

                <StackPanel Grid.Column="1" VerticalAlignment="Center">
                    <TextBlock Text="Apple Studio Display XDR" FontSize="17" FontWeight="SemiBold"/>
                    <TextBlock x:Name="DetailsText" Text="USB product 05AC:1116" Style="{StaticResource MutedText}" Margin="0,5,0,0"/>
                    <TextBlock x:Name="ModeText" Text="Brightness control over Apple USB HID" Style="{StaticResource MutedText}" Margin="0,2,0,0"/>
                </StackPanel>
            </Grid>
        </Border>

        <Border Grid.Row="4" Background="#FFFFFF" CornerRadius="8" BorderBrush="#D9D9DE" BorderThickness="1" Padding="20,18">
            <StackPanel>
                <Grid>
                    <Grid.ColumnDefinitions>
                        <ColumnDefinition Width="*"/>
                        <ColumnDefinition Width="Auto"/>
                    </Grid.ColumnDefinitions>
                    <TextBlock Text="Brightness" Style="{StaticResource SectionTitle}"/>
                    <TextBlock Grid.Column="1" x:Name="BrightnessValueText" Text="--%" FontSize="14" FontWeight="SemiBold"/>
                </Grid>
                <Slider x:Name="BrightnessSlider" Minimum="0" Maximum="100" Margin="0,14,0,2"/>
                <TextBlock x:Name="BrightnessHelpText" Text="Drag to adjust the Studio Display XDR panel brightness." Style="{StaticResource MutedText}"/>
            </StackPanel>
        </Border>

        <Border Grid.Row="6" Background="#FFFFFF" CornerRadius="8" BorderBrush="#D9D9DE" BorderThickness="1" Padding="20,16">
            <Grid>
                <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="*"/>
                    <ColumnDefinition Width="Auto"/>
                </Grid.ColumnDefinitions>
                <StackPanel>
                    <TextBlock Text="Automatically adjust brightness" Style="{StaticResource SectionTitle}"/>
                    <TextBlock x:Name="AutoBrightnessText" Text="Studio Display XDR does not expose a working ambient light sensor to Windows yet." Style="{StaticResource MutedText}" Margin="0,5,0,0" TextWrapping="Wrap"/>
                </StackPanel>
                <CheckBox Grid.Column="1" x:Name="AutoBrightnessToggle" IsEnabled="False" VerticalAlignment="Center"/>
            </Grid>
        </Border>
    </Grid>
</Window>
"@

$reader = [System.Xml.XmlReader]::Create([System.IO.StringReader]::new($xaml))
$window = [Windows.Markup.XamlReader]::Load($reader)

$subtitleText = $window.FindName("SubtitleText")
$connectionPill = $window.FindName("ConnectionPill")
$connectionDot = $window.FindName("ConnectionDot")
$connectionText = $window.FindName("ConnectionText")
$detailsText = $window.FindName("DetailsText")
$modeText = $window.FindName("ModeText")
$brightnessValueText = $window.FindName("BrightnessValueText")
$brightnessSlider = $window.FindName("BrightnessSlider")
$brightnessHelpText = $window.FindName("BrightnessHelpText")
$autoBrightnessText = $window.FindName("AutoBrightnessText")
$autoBrightnessToggle = $window.FindName("AutoBrightnessToggle")

$script:device = $null
$script:updating = $false

$writeTimer = [System.Windows.Threading.DispatcherTimer]::new()
$writeTimer.Interval = [TimeSpan]::FromMilliseconds(140)
$writeTimer.Add_Tick({
    $writeTimer.Stop()
    if (-not $script:device -or $script:updating) { return }

    try {
        [AppleDisplayBrightness]::SetPercent($script:device.Path, [int][Math]::Round($brightnessSlider.Value))
        $brightnessHelpText.Text = "Brightness updated."
    } catch {
        $brightnessHelpText.Text = "Could not write brightness: $($_.Exception.Message)"
    }
})

function Set-ConnectedState([bool]$connected) {
    if ($connected) {
        $connectionPill.Background = [Windows.Media.SolidColorBrush][Windows.Media.ColorConverter]::ConvertFromString("#E8F5E9")
        $connectionDot.Fill = [Windows.Media.SolidColorBrush][Windows.Media.ColorConverter]::ConvertFromString("#34C759")
        $connectionText.Text = "Connected"
        $subtitleText.Text = "Connected over Thunderbolt / USB4"
    } else {
        $connectionPill.Background = [Windows.Media.SolidColorBrush][Windows.Media.ColorConverter]::ConvertFromString("#FFF3E0")
        $connectionDot.Fill = [Windows.Media.SolidColorBrush][Windows.Media.ColorConverter]::ConvertFromString("#FF9500")
        $connectionText.Text = "Not found"
        $subtitleText.Text = "Connect Studio Display XDR over Thunderbolt / USB4"
    }
}

function Refresh-StudioDisplay {
    $script:updating = $true
    try {
        $script:device = Get-StudioDisplayDevice
        $usb4Present = Test-StudioUsb4Present
        $sensorPresent = Test-StudioSensorPresent

        if ($script:device) {
            Set-ConnectedState $true
            $detailsText.Text = "USB product 05AC:$($script:device.ProductId)  |  Brightness HID ready"
            $modeText.Text = if ($usb4Present) { "Thunderbolt / USB4 control path active" } else { "USB HID control path active" }
            $brightnessSlider.IsEnabled = $true
            $brightnessSlider.Value = [Math]::Max(0, [Math]::Min(100, $script:device.Percent))
            $brightnessValueText.Text = "{0}%" -f $script:device.Percent
            $brightnessHelpText.Text = "Drag to adjust the Studio Display XDR panel brightness."
        } else {
            Set-ConnectedState $false
            $detailsText.Text = "USB product 05AC:1116"
            $modeText.Text = "Brightness HID not detected"
            $brightnessSlider.IsEnabled = $false
            $brightnessSlider.Value = 0
            $brightnessValueText.Text = "--%"
            $brightnessHelpText.Text = "The display must expose its Apple USB HID interface."
        }

        if ($sensorPresent) {
            $autoBrightnessToggle.IsEnabled = $true
            $autoBrightnessText.Text = "A compatible ambient light sensor is available. Automatic mode can be enabled in a future build."
        } else {
            $autoBrightnessToggle.IsEnabled = $false
            $autoBrightnessText.Text = "Studio Display XDR does not expose a working ambient light sensor to Windows yet."
        }
    } finally {
        $script:updating = $false
    }
}

$brightnessSlider.Add_ValueChanged({
    if ($script:updating) { return }
    $percent = [int][Math]::Round($brightnessSlider.Value)
    $brightnessValueText.Text = "{0}%" -f $percent
    $brightnessHelpText.Text = "Release to apply."
    $writeTimer.Stop()
    $writeTimer.Start()
})

$window.Add_Loaded({ Refresh-StudioDisplay })

[void]$window.ShowDialog()
