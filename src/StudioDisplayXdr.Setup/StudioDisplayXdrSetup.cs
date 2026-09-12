using System;
using System.Diagnostics;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.IO;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Windows.Forms;

[assembly: AssemblyTitle("Studio Display XDR Support")]
[assembly: AssemblyDescription("Setup launcher for the Studio Display XDR Windows support package")]
[assembly: AssemblyCompany("Studio Display XDR Windows Override")]
[assembly: AssemblyProduct("Studio Display XDR Windows Support")]
[assembly: AssemblyCopyright("MIT License")]
[assembly: AssemblyVersion("0.1.0.0")]
[assembly: AssemblyFileVersion("0.1.0.0")]

namespace StudioDisplayXdr.Setup
{
    internal static class Program
    {
        [STAThread]
        private static void Main()
        {
            TrySetDpiAware();
            Application.EnableVisualStyles();
            Application.SetCompatibleTextRenderingDefault(false);
            Application.Run(new SetupForm());
        }

        [DllImport("user32.dll")]
        private static extern bool SetProcessDPIAware();

        private static void TrySetDpiAware()
        {
            try
            {
                SetProcessDPIAware();
            }
            catch
            {
                // Older Windows builds may not expose this API; layout still works without it.
            }
        }
    }

    internal sealed class SetupForm : Form
    {
        private readonly string _root;
        private readonly Label _statusLabel;

        public SetupForm()
        {
            _root = FindPackageRoot();
            _statusLabel = new Label();

            Text = "Studio Display XDR Support";
            TrySetFormIcon();
            StartPosition = FormStartPosition.CenterScreen;
            MinimumSize = new Size(660, 760);
            Size = new Size(720, 940);
            Font = new Font("Segoe UI", 10);
            BackColor = Color.FromArgb(246, 246, 247);
            AutoScaleMode = AutoScaleMode.Dpi;
            AutoScroll = true;

            var panel = new TableLayoutPanel();
            panel.Dock = DockStyle.Fill;
            panel.Padding = new Padding(28);
            panel.RowCount = 7;
            panel.ColumnCount = 1;
            panel.RowStyles.Add(new RowStyle(SizeType.AutoSize));
            panel.RowStyles.Add(new RowStyle(SizeType.AutoSize));
            panel.RowStyles.Add(new RowStyle(SizeType.Absolute, 16));
            panel.RowStyles.Add(new RowStyle(SizeType.AutoSize));
            panel.RowStyles.Add(new RowStyle(SizeType.AutoSize));
            panel.RowStyles.Add(new RowStyle(SizeType.AutoSize));
            panel.RowStyles.Add(new RowStyle(SizeType.AutoSize));

            var title = new Label();
            title.Text = "Studio Display XDR";
            title.Dock = DockStyle.Fill;
            title.AutoSize = true;
            title.Font = new Font(Font.FontFamily, 18, FontStyle.Regular);
            title.ForeColor = Color.FromArgb(28, 28, 30);

            var subtitle = new Label();
            subtitle.Text = "Windows support package for native resolution, HDR, color, brightness, and automatic brightness experiments.";
            subtitle.Dock = DockStyle.Fill;
            subtitle.AutoSize = true;
            subtitle.MaximumSize = new Size(640, 0);
            subtitle.ForeColor = Color.FromArgb(82, 82, 88);
            subtitle.Padding = new Padding(0, 8, 0, 0);

            var actions = new TableLayoutPanel();
            actions.Dock = DockStyle.Fill;
            actions.AutoSize = true;
            actions.ColumnCount = 2;
            actions.RowCount = 5;
            actions.GrowStyle = TableLayoutPanelGrowStyle.FixedSize;
            actions.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 50));
            actions.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 50));
            actions.RowStyles.Add(new RowStyle(SizeType.AutoSize));
            actions.RowStyles.Add(new RowStyle(SizeType.AutoSize));
            actions.RowStyles.Add(new RowStyle(SizeType.AutoSize));
            actions.RowStyles.Add(new RowStyle(SizeType.AutoSize));
            actions.RowStyles.Add(new RowStyle(SizeType.AutoSize));

            actions.Controls.Add(CreateActionButton("Install / Repair", "EDID, HDR, shortcuts.", delegate
            {
                RunPowerShellScript("scripts\\Install-StudioDisplayXdrSupport.ps1", true);
            }));

            actions.Controls.Add(CreateActionButton("Open Control Panel", "Brightness, HDR, color.", OpenControlPanel));
            actions.Controls.Add(CreateActionButton("Check Status", "Native mode and USB.", CheckStatus));
            actions.Controls.Add(CreateActionButton("Check Ambient", "Sensor and camera check.", CheckAmbient));
            actions.Controls.Add(CreateActionButton("Prepare Ambient", "Catalog/test-signing.", PrepareAmbientDriver));
            actions.Controls.Add(CreateActionButton("Check Color", "HDR and profile scan.", CheckColor));
            actions.Controls.Add(CreateActionButton("Check Gaming", "VRR, HDR, frame pacing.", CheckGaming));
            actions.Controls.Add(CreateActionButton("Support Report", "GitHub issue report.", GenerateSupportReport));

            actions.Controls.Add(CreateActionButton("Uninstall Support", "Shortcuts and profiles.", delegate
            {
                RunPowerShellScript("scripts\\Uninstall-StudioDisplayXdrSupport.ps1", true);
            }));

            actions.Controls.Add(CreateActionButton("Open README", "Setup and recovery.", OpenReadme));

            _statusLabel.Dock = DockStyle.Fill;
            _statusLabel.AutoSize = true;
            _statusLabel.MaximumSize = new Size(640, 0);
            _statusLabel.ForeColor = Color.FromArgb(98, 98, 104);
            _statusLabel.Text = _root == null
                ? "Package root was not found. Extract the ZIP before running setup."
                : BuildStatusText(_root);

            var closeButton = new Button();
            closeButton.Text = "Close";
            closeButton.AutoSize = false;
            closeButton.Width = 110;
            closeButton.Height = 42;
            closeButton.Anchor = AnchorStyles.Right;
            closeButton.FlatStyle = FlatStyle.Flat;
            closeButton.BackColor = Color.White;
            closeButton.ForeColor = Color.FromArgb(28, 28, 30);
            closeButton.FlatAppearance.BorderColor = Color.FromArgb(218, 218, 222);
            closeButton.Click += delegate { Close(); };

            var closePanel = new FlowLayoutPanel();
            closePanel.Dock = DockStyle.Fill;
            closePanel.FlowDirection = FlowDirection.RightToLeft;
            closePanel.AutoSize = true;
            closePanel.Controls.Add(closeButton);

            panel.Controls.Add(title, 0, 0);
            panel.Controls.Add(subtitle, 0, 1);
            panel.Controls.Add(new Panel(), 0, 2);
            panel.Controls.Add(actions, 0, 3);
            panel.Controls.Add(_statusLabel, 0, 5);
            panel.Controls.Add(closePanel, 0, 6);

            Controls.Add(panel);
        }

        private void TrySetFormIcon()
        {
            try
            {
                var icon = Icon.ExtractAssociatedIcon(Application.ExecutablePath);
                if (icon != null)
                {
                    Icon = icon;
                }
            }
            catch
            {
                // The executable still runs if Windows cannot extract the embedded icon.
            }
        }

        private Control CreateActionButton(string title, string description, Action action)
        {
            var card = new ActionCard(title, description);
            card.Enabled = _root != null;
            card.Click += delegate { SafeRun(action); };
            return card;
        }

        private void SafeRun(Action action)
        {
            try
            {
                action();
            }
            catch (Exception ex)
            {
                MessageBox.Show(this, ex.Message, "Studio Display XDR Support", MessageBoxButtons.OK, MessageBoxIcon.Error);
            }
        }

        private void RunPowerShellScript(string relativeScriptPath, bool elevated)
        {
            var root = RequireRoot();
            var script = Path.Combine(root, relativeScriptPath);
            if (!File.Exists(script))
            {
                throw new FileNotFoundException("Script not found.", script);
            }

            var info = new ProcessStartInfo();
            info.FileName = "powershell.exe";
            info.Arguments = "-NoProfile -ExecutionPolicy Bypass -File \"" + script + "\"";
            info.WorkingDirectory = root;
            info.UseShellExecute = true;
            if (elevated)
            {
                info.Verb = "runas";
            }

            Process.Start(info);
            _statusLabel.Text = elevated ? "Waiting for the elevated PowerShell window..." : "Started PowerShell.";
        }

        private void OpenControlPanel()
        {
            var root = RequireRoot();
            var app = IsDevelopmentCheckout(root)
                ? null
                : FindStableInstalledApp();
            if (app == null)
            {
                app = FindExisting(root, "StudioDisplayXdr.App\\StudioDisplayXdr.exe", "dist\\StudioDisplayXdr.App\\StudioDisplayXdr.exe");
            }

            if (app == null)
            {
                throw new FileNotFoundException("Control panel executable was not found.");
            }

            var info = new ProcessStartInfo();
            info.FileName = app;
            info.WorkingDirectory = Path.GetDirectoryName(app) ?? root;
            info.UseShellExecute = true;
            Process.Start(info);
            _statusLabel.Text = IsStableInstalledPath(app) ? "Opened the installed control panel." : "Opened the control panel.";
        }

        private void GenerateSupportReport()
        {
            var root = RequireRoot();
            var support = FindExisting(root, "Support-Report.cmd");
            if (support != null)
            {
                var info = new ProcessStartInfo();
                info.FileName = support;
                info.WorkingDirectory = root;
                info.UseShellExecute = true;
                Process.Start(info);
                _statusLabel.Text = "Started support report generation.";
                return;
            }

            RunPowerShellScript("scripts\\Get-StudioXdrSupportReport.ps1", false);
        }

        private void CheckStatus()
        {
            var root = RequireRoot();
            var status = FindExisting(root, "Check-Status.cmd");
            if (status != null)
            {
                var info = new ProcessStartInfo();
                info.FileName = status;
                info.WorkingDirectory = root;
                info.UseShellExecute = true;
                Process.Start(info);
                _statusLabel.Text = "Started readiness check.";
                return;
            }

            RunPowerShellScript("scripts\\Test-StudioXdrReadiness.ps1", false);
        }

        private void CheckAmbient()
        {
            var root = RequireRoot();
            var ambient = FindExisting(root, "Check-Ambient.cmd");
            if (ambient != null)
            {
                var info = new ProcessStartInfo();
                info.FileName = ambient;
                info.WorkingDirectory = root;
                info.UseShellExecute = true;
                Process.Start(info);
                _statusLabel.Text = "Started automatic-brightness preflight.";
                return;
            }

            RunPowerShellScript("scripts\\Test-StudioXdrAmbientPreflight.ps1", false);
        }

        private void PrepareAmbientDriver()
        {
            var root = RequireRoot();
            var prepare = FindExisting(root, "Prepare-Ambient-Driver.cmd");
            if (prepare != null)
            {
                var info = new ProcessStartInfo();
                info.FileName = prepare;
                info.WorkingDirectory = root;
                info.UseShellExecute = true;
                Process.Start(info);
                _statusLabel.Text = "Started ambient driver package preparation.";
                return;
            }

            RunPowerShellScript("scripts\\New-StudioXdrAmbientDriverPackage.ps1", false);
        }

        private void CheckColor()
        {
            var root = RequireRoot();
            var color = FindExisting(root, "Check-Color.cmd");
            if (color != null)
            {
                var info = new ProcessStartInfo();
                info.FileName = color;
                info.WorkingDirectory = root;
                info.UseShellExecute = true;
                Process.Start(info);
                _statusLabel.Text = "Started color and profile check.";
                return;
            }

            RunPowerShellScript("scripts\\Find-StudioXdrColorProfiles.ps1", false);
        }

        private void CheckGaming()
        {
            var root = RequireRoot();
            var gaming = FindExisting(root, "Check-Gaming.cmd");
            if (gaming != null)
            {
                var info = new ProcessStartInfo();
                info.FileName = gaming;
                info.WorkingDirectory = root;
                info.UseShellExecute = true;
                Process.Start(info);
                _statusLabel.Text = "Started gaming and tearing diagnostic.";
                return;
            }

            RunPowerShellScript("scripts\\Get-StudioXdrGamingStatus.ps1", false);
        }

        private void OpenReadme()
        {
            var root = RequireRoot();
            var readme = Path.Combine(root, "README.md");
            if (!File.Exists(readme))
            {
                throw new FileNotFoundException("README.md was not found.", readme);
            }

            var info = new ProcessStartInfo();
            info.FileName = readme;
            info.WorkingDirectory = root;
            info.UseShellExecute = true;
            Process.Start(info);
            _statusLabel.Text = "Opened README.";
        }

        private string RequireRoot()
        {
            if (_root == null)
            {
                throw new InvalidOperationException("Package root was not found. Extract the ZIP before running setup.");
            }

            return _root;
        }

        private static string FindExisting(string root, params string[] relativePaths)
        {
            foreach (var relativePath in relativePaths)
            {
                var candidate = Path.Combine(root, relativePath);
                if (File.Exists(candidate))
                {
                    return candidate;
                }
            }

            return null;
        }

        private static string FindStableInstalledApp()
        {
            var app = Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
                "StudioDisplayXdr",
                "Support",
                "StudioDisplayXdr.App",
                "StudioDisplayXdr.exe");

            return File.Exists(app) ? app : null;
        }

        private static bool IsStableInstalledPath(string path)
        {
            var stableApp = FindStableInstalledApp();
            return stableApp != null &&
                string.Equals(Path.GetFullPath(stableApp), Path.GetFullPath(path), StringComparison.OrdinalIgnoreCase);
        }

        private static bool IsDevelopmentCheckout(string root)
        {
            return Directory.Exists(Path.Combine(root, ".git"));
        }

        private static string FindPackageRoot()
        {
            var directory = new DirectoryInfo(AppDomain.CurrentDomain.BaseDirectory);
            while (directory != null)
            {
                if (Directory.Exists(Path.Combine(directory.FullName, "scripts")) &&
                    File.Exists(Path.Combine(directory.FullName, "README.md")))
                {
                    return directory.FullName;
                }

                directory = directory.Parent;
            }

            return null;
        }

        private static string BuildStatusText(string root)
        {
            if (IsDevelopmentCheckout(root))
            {
                return "Development checkout";
            }

            var packageType = FindStableInstalledApp() == null
                ? "Extracted package"
                : "Extracted package; installed app copy available";

            return packageType;
        }

        private sealed class ActionCard : Control
        {
            private readonly string _title;
            private readonly string _description;
            private bool _hover;
            private bool _pressed;

            public ActionCard(string title, string description)
            {
                _title = title;
                _description = description;

                SetStyle(
                    ControlStyles.AllPaintingInWmPaint |
                    ControlStyles.OptimizedDoubleBuffer |
                    ControlStyles.ResizeRedraw |
                    ControlStyles.UserPaint,
                    true);

                Width = 300;
                Height = 94;
                Margin = new Padding(0, 0, 10, 10);
                Dock = DockStyle.Fill;
                Cursor = Cursors.Hand;
                TabStop = true;
                AccessibleRole = AccessibleRole.PushButton;
                AccessibleName = title;
                AccessibleDescription = description;
            }

            protected override void OnEnabledChanged(EventArgs e)
            {
                base.OnEnabledChanged(e);
                Cursor = Enabled ? Cursors.Hand : Cursors.Default;
                Invalidate();
            }

            protected override void OnMouseEnter(EventArgs e)
            {
                base.OnMouseEnter(e);
                _hover = true;
                Invalidate();
            }

            protected override void OnMouseLeave(EventArgs e)
            {
                base.OnMouseLeave(e);
                _hover = false;
                _pressed = false;
                Invalidate();
            }

            protected override void OnMouseDown(MouseEventArgs e)
            {
                base.OnMouseDown(e);
                if (Enabled && e.Button == MouseButtons.Left)
                {
                    _pressed = true;
                    Focus();
                    Invalidate();
                }
            }

            protected override void OnMouseUp(MouseEventArgs e)
            {
                base.OnMouseUp(e);
                if (_pressed)
                {
                    _pressed = false;
                    Invalidate();
                }
            }

            protected override void OnKeyDown(KeyEventArgs e)
            {
                base.OnKeyDown(e);
                if (Enabled && (e.KeyCode == Keys.Enter || e.KeyCode == Keys.Space))
                {
                    OnClick(EventArgs.Empty);
                    e.Handled = true;
                }
            }

            protected override void OnGotFocus(EventArgs e)
            {
                base.OnGotFocus(e);
                Invalidate();
            }

            protected override void OnLostFocus(EventArgs e)
            {
                base.OnLostFocus(e);
                Invalidate();
            }

            protected override void OnPaint(PaintEventArgs e)
            {
                base.OnPaint(e);

                e.Graphics.SmoothingMode = SmoothingMode.AntiAlias;
                var bounds = new Rectangle(1, 1, Width - 3, Height - 3);
                var fill = Enabled
                    ? (_pressed ? Color.FromArgb(238, 238, 242) : (_hover ? Color.FromArgb(251, 251, 253) : Color.White))
                    : Color.FromArgb(244, 244, 246);
                var border = Focused
                    ? Color.FromArgb(0, 122, 255)
                    : Color.FromArgb(218, 218, 222);

                using (var path = RoundedRectangle(bounds, 10))
                using (var brush = new SolidBrush(fill))
                using (var pen = new Pen(border))
                {
                    e.Graphics.FillPath(brush, path);
                    e.Graphics.DrawPath(pen, path);
                }

                var titleColor = Enabled ? Color.FromArgb(28, 28, 30) : Color.FromArgb(145, 145, 150);
                var descriptionColor = Enabled ? Color.FromArgb(99, 99, 106) : Color.FromArgb(168, 168, 174);
                var contentWidth = Width - 76;
                var titleTop = 11;
                var arrowRect = new Rectangle(Width - 42, 32, 22, 30);

                using (var titleFont = new Font(Font.FontFamily, 8.1f, FontStyle.Bold))
                using (var descriptionFont = new Font(Font.FontFamily, 7.4f, FontStyle.Regular))
                using (var arrowFont = new Font(Font.FontFamily, 13f, FontStyle.Regular))
                {
                    var titleHeight = TextRenderer.MeasureText(e.Graphics, _title, titleFont, new Size(contentWidth, 0), TextFormatFlags.SingleLine).Height;
                    var titleRect = new Rectangle(18, titleTop, contentWidth, titleHeight + 2);
                    var descriptionTop = titleRect.Bottom + 3;
                    var descriptionRect = new Rectangle(18, descriptionTop, contentWidth, Height - descriptionTop - 12);

                    TextRenderer.DrawText(e.Graphics, _title, titleFont, titleRect, titleColor, TextFormatFlags.Left | TextFormatFlags.EndEllipsis | TextFormatFlags.VerticalCenter);
                    TextRenderer.DrawText(e.Graphics, _description, descriptionFont, descriptionRect, descriptionColor, TextFormatFlags.Left | TextFormatFlags.WordBreak | TextFormatFlags.TextBoxControl);
                    TextRenderer.DrawText(e.Graphics, ">", arrowFont, arrowRect, descriptionColor, TextFormatFlags.HorizontalCenter | TextFormatFlags.VerticalCenter);
                }
            }

            private static GraphicsPath RoundedRectangle(Rectangle bounds, int radius)
            {
                var diameter = radius * 2;
                var path = new GraphicsPath();
                path.AddArc(bounds.Left, bounds.Top, diameter, diameter, 180, 90);
                path.AddArc(bounds.Right - diameter, bounds.Top, diameter, diameter, 270, 90);
                path.AddArc(bounds.Right - diameter, bounds.Bottom - diameter, diameter, diameter, 0, 90);
                path.AddArc(bounds.Left, bounds.Bottom - diameter, diameter, diameter, 90, 90);
                path.CloseFigure();
                return path;
            }
        }

    }
}
