$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "AppleDisplayBrightnessCore.ps1")

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$nativeSource = @"
using System;
using System.Runtime.InteropServices;
public static class AppleBrightnessNative
{
    [DllImport("user32.dll", SetLastError=true)]
    public static extern bool RegisterHotKey(IntPtr hWnd, int id, uint fsModifiers, uint vk);
    [DllImport("user32.dll", SetLastError=true)]
    public static extern bool UnregisterHotKey(IntPtr hWnd, int id);
}
"@
if (-not ("AppleBrightnessNative" -as [type])) {
    Add-Type -TypeDefinition $nativeSource
}

$HOTKEY_DOWN = 1001
$HOTKEY_UP = 1002
$VK_F1 = 0x70
$VK_F2 = 0x71
$MOD_NONE = 0x0000

$form = [AppleBrightnessHotkeyWindow]::new()
$form.ShowInTaskbar = $false
$form.WindowState = [System.Windows.Forms.FormWindowState]::Minimized
$form.Size = [System.Drawing.Size]::new(1, 1)
$form.Text = "Apple Display Brightness"

$notify = [System.Windows.Forms.NotifyIcon]::new()
$notify.Text = "Apple Display Brightness"
$notify.Icon = [System.Drawing.SystemIcons]::Application
$notify.Visible = $true

$menu = [System.Windows.Forms.ContextMenuStrip]::new()
$openSliderItem = [System.Windows.Forms.ToolStripMenuItem]::new("Open brightness slider")
$devicesMenu = [System.Windows.Forms.ToolStripMenuItem]::new("Displays")
$refreshItem = [System.Windows.Forms.ToolStripMenuItem]::new("Refresh displays")
$upItem = [System.Windows.Forms.ToolStripMenuItem]::new("Brightness up 5%")
$downItem = [System.Windows.Forms.ToolStripMenuItem]::new("Brightness down 5%")
$statusItem = [System.Windows.Forms.ToolStripMenuItem]::new("Status")
$hotkeyItem = [System.Windows.Forms.ToolStripMenuItem]::new("F1/F2 hotkeys")
$hotkeyItem.CheckOnClick = $true
$hotkeyItem.Checked = $true
$exitItem = [System.Windows.Forms.ToolStripMenuItem]::new("Exit")

[void]$menu.Items.Add($openSliderItem)
[void]$menu.Items.Add([System.Windows.Forms.ToolStripSeparator]::new())
[void]$menu.Items.Add($devicesMenu)
[void]$menu.Items.Add($refreshItem)
[void]$menu.Items.Add([System.Windows.Forms.ToolStripSeparator]::new())
[void]$menu.Items.Add($upItem)
[void]$menu.Items.Add($downItem)
[void]$menu.Items.Add($statusItem)
[void]$menu.Items.Add([System.Windows.Forms.ToolStripSeparator]::new())
[void]$menu.Items.Add($hotkeyItem)
[void]$menu.Items.Add($exitItem)
$notify.ContextMenuStrip = $menu

$script:devices = @()
$script:selectedPath = $null
$script:sliderForm = $null
$script:displayCombo = $null
$script:trackBar = $null
$script:percentLabel = $null
$script:sliderUpdating = $false

function Get-UsableAppleDisplays {
    @(Get-AppleDisplayBrightnessDevice)
}

function Refresh-Devices {
    $script:devices = Get-UsableAppleDisplays
    $devicesMenu.DropDownItems.Clear()

    if ($script:devices.Count -eq 0) {
        $item = [System.Windows.Forms.ToolStripMenuItem]::new("No Apple displays found")
        $item.Enabled = $false
        [void]$devicesMenu.DropDownItems.Add($item)
        $script:selectedPath = $null
        $notify.Text = "Apple Display Brightness - no display"
        return
    }

    if (-not $script:selectedPath -or -not ($script:devices | Where-Object { $_.Path -eq $script:selectedPath })) {
        $script:selectedPath = $script:devices[0].Path
    }

    foreach ($device in $script:devices) {
        $label = "{0} ({1}%)" -f $device.DisplayName, $device.Percent
        $item = [System.Windows.Forms.ToolStripMenuItem]::new($label)
        $item.Checked = $device.Path -eq $script:selectedPath
        $item.Tag = $device.Path
        $item.Add_Click({
            $script:selectedPath = $this.Tag
            Refresh-Devices
            Update-SliderUi
        })
        [void]$devicesMenu.DropDownItems.Add($item)
    }

    $selected = $script:devices | Where-Object { $_.Path -eq $script:selectedPath } | Select-Object -First 1
    if ($selected) {
        $notify.Text = "Apple Display Brightness - {0} {1}%" -f $selected.DisplayName, $selected.Percent
    }
}

function Update-SliderUi {
    if (-not $script:sliderForm -or $script:sliderForm.IsDisposed) { return }
    $script:sliderUpdating = $true
    try {
        Refresh-Devices
        $script:displayCombo.Items.Clear()
        foreach ($device in $script:devices) {
            $label = "{0} ({1})" -f $device.DisplayName, $device.ProductId
            [void]$script:displayCombo.Items.Add($label)
            if ($device.Path -eq $script:selectedPath) {
                $script:displayCombo.SelectedIndex = $script:displayCombo.Items.Count - 1
            }
        }

        $selected = $script:devices | Where-Object { $_.Path -eq $script:selectedPath } | Select-Object -First 1
        if ($selected) {
            $script:trackBar.Enabled = $true
            $script:trackBar.Value = [Math]::Max(0, [Math]::Min(100, $selected.Percent))
            $script:percentLabel.Text = "{0}%" -f $selected.Percent
        } else {
            $script:trackBar.Enabled = $false
            $script:trackBar.Value = 0
            $script:percentLabel.Text = "No display"
        }
    } finally {
        $script:sliderUpdating = $false
    }
}

function Show-Slider {
    if ($script:sliderForm -and -not $script:sliderForm.IsDisposed) {
        Update-SliderUi
        $script:sliderForm.Show()
        $script:sliderForm.Activate()
        return
    }

    $script:sliderForm = [System.Windows.Forms.Form]::new()
    $script:sliderForm.Text = "Apple Display Brightness"
    $script:sliderForm.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog
    $script:sliderForm.MaximizeBox = $false
    $script:sliderForm.MinimizeBox = $false
    $script:sliderForm.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterScreen
    $script:sliderForm.ClientSize = [System.Drawing.Size]::new(360, 132)

    $displayLabel = [System.Windows.Forms.Label]::new()
    $displayLabel.Text = "Display"
    $displayLabel.Location = [System.Drawing.Point]::new(14, 16)
    $displayLabel.Size = [System.Drawing.Size]::new(56, 22)
    $script:sliderForm.Controls.Add($displayLabel)

    $script:displayCombo = [System.Windows.Forms.ComboBox]::new()
    $script:displayCombo.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
    $script:displayCombo.Location = [System.Drawing.Point]::new(76, 13)
    $script:displayCombo.Size = [System.Drawing.Size]::new(270, 24)
    $script:displayCombo.Add_SelectedIndexChanged({
        if ($script:sliderUpdating) { return }
        if ($script:displayCombo.SelectedIndex -ge 0 -and $script:displayCombo.SelectedIndex -lt $script:devices.Count) {
            $script:selectedPath = $script:devices[$script:displayCombo.SelectedIndex].Path
            Update-SliderUi
        }
    })
    $script:sliderForm.Controls.Add($script:displayCombo)

    $brightnessLabel = [System.Windows.Forms.Label]::new()
    $brightnessLabel.Text = "Brightness"
    $brightnessLabel.Location = [System.Drawing.Point]::new(14, 58)
    $brightnessLabel.Size = [System.Drawing.Size]::new(72, 22)
    $script:sliderForm.Controls.Add($brightnessLabel)

    $script:trackBar = [System.Windows.Forms.TrackBar]::new()
    $script:trackBar.Minimum = 0
    $script:trackBar.Maximum = 100
    $script:trackBar.TickFrequency = 10
    $script:trackBar.SmallChange = 1
    $script:trackBar.LargeChange = 10
    $script:trackBar.Location = [System.Drawing.Point]::new(83, 49)
    $script:trackBar.Size = [System.Drawing.Size]::new(218, 45)
    $script:trackBar.Add_Scroll({
        if ($script:sliderUpdating -or -not $script:selectedPath) { return }
        $value = $script:trackBar.Value
        $script:percentLabel.Text = "{0}%" -f $value
        [AppleDisplayBrightness]::SetPercent($script:selectedPath, $value)
        Refresh-Devices
    })
    $script:sliderForm.Controls.Add($script:trackBar)

    $script:percentLabel = [System.Windows.Forms.Label]::new()
    $script:percentLabel.TextAlign = [System.Drawing.ContentAlignment]::MiddleRight
    $script:percentLabel.Location = [System.Drawing.Point]::new(302, 58)
    $script:percentLabel.Size = [System.Drawing.Size]::new(44, 22)
    $script:sliderForm.Controls.Add($script:percentLabel)

    $closeButton = [System.Windows.Forms.Button]::new()
    $closeButton.Text = "Close"
    $closeButton.Location = [System.Drawing.Point]::new(271, 98)
    $closeButton.Size = [System.Drawing.Size]::new(75, 24)
    $closeButton.Add_Click({ $script:sliderForm.Hide() })
    $script:sliderForm.Controls.Add($closeButton)

    $script:sliderForm.Add_FormClosing({
        if ($_.CloseReason -eq [System.Windows.Forms.CloseReason]::UserClosing) {
            $_.Cancel = $true
            $script:sliderForm.Hide()
        }
    })

    Update-SliderUi
    $script:sliderForm.Show()
    $script:sliderForm.Activate()
}

function Get-SelectedDevice {
    Refresh-Devices
    $script:devices | Where-Object { $_.Path -eq $script:selectedPath } | Select-Object -First 1
}

function Step-Brightness([int]$step) {
    $device = Get-SelectedDevice
    if (-not $device) { return }
    [AppleDisplayBrightness]::StepPercent($device.Path, $device.Percent, $step)
    Start-Sleep -Milliseconds 100
    Refresh-Devices
}

function Show-Status {
    $device = Get-SelectedDevice
    if (-not $device) {
        [System.Windows.Forms.MessageBox]::Show("No Apple Studio Display XDR or Pro Display XDR brightness HID device found.", "Apple Display Brightness") | Out-Null
        return
    }

    $message = @"
Display: $($device.DisplayName)
Product ID: $($device.ProductId)
Brightness: $($device.Percent)%
Raw value: $($device.CurrentValue)
"@
    [System.Windows.Forms.MessageBox]::Show($message, "Apple Display Brightness") | Out-Null
}

$refreshItem.Add_Click({ Refresh-Devices })
$openSliderItem.Add_Click({ Show-Slider })
$upItem.Add_Click({ Step-Brightness 5 })
$downItem.Add_Click({ Step-Brightness -5 })
$statusItem.Add_Click({ Show-Status })
$notify.Add_DoubleClick({ Show-Slider })
$exitItem.Add_Click({
    [AppleBrightnessNative]::UnregisterHotKey($form.Handle, $HOTKEY_DOWN) | Out-Null
    [AppleBrightnessNative]::UnregisterHotKey($form.Handle, $HOTKEY_UP) | Out-Null
    $notify.Visible = $false
    $notify.Dispose()
    $form.Close()
})

$hotkeyItem.Add_CheckedChanged({
    if ($hotkeyItem.Checked) {
        [AppleBrightnessNative]::RegisterHotKey($form.Handle, $HOTKEY_DOWN, $MOD_NONE, $VK_F1) | Out-Null
        [AppleBrightnessNative]::RegisterHotKey($form.Handle, $HOTKEY_UP, $MOD_NONE, $VK_F2) | Out-Null
    } else {
        [AppleBrightnessNative]::UnregisterHotKey($form.Handle, $HOTKEY_DOWN) | Out-Null
        [AppleBrightnessNative]::UnregisterHotKey($form.Handle, $HOTKEY_UP) | Out-Null
    }
})

$form.add_HotkeyPressed({
    param([int]$id)
    if (-not $hotkeyItem.Checked) { return }
    if ($id -eq $HOTKEY_DOWN) { Step-Brightness -5 }
    if ($id -eq $HOTKEY_UP) { Step-Brightness 5 }
})

$form.Add_Shown({
    $form.Hide()
    Refresh-Devices
    if ($hotkeyItem.Checked) {
        $downRegistered = [AppleBrightnessNative]::RegisterHotKey($form.Handle, $HOTKEY_DOWN, $MOD_NONE, $VK_F1)
        $upRegistered = [AppleBrightnessNative]::RegisterHotKey($form.Handle, $HOTKEY_UP, $MOD_NONE, $VK_F2)
        if (-not $downRegistered -or -not $upRegistered) {
            $hotkeyItem.Checked = $false
            $notify.ShowBalloonTip(3000, "Apple Display Brightness", "F1/F2 were already reserved by Windows or another app. Tray controls still work.", [System.Windows.Forms.ToolTipIcon]::Info)
        }
    }
})

[System.Windows.Forms.Application]::EnableVisualStyles()
[System.Windows.Forms.Application]::Run($form)
