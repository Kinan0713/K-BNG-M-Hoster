using System;
using System.Diagnostics;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.IO;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Threading;
using System.Windows.Forms;
using Microsoft.Win32;

[assembly: AssemblyTitle("K BNG M Hoster Uninstaller")]
[assembly: AssemblyDescription("Uninstaller for K BNG M Hoster")]
[assembly: AssemblyCompany("Kinan (@kinan_sx240) - UI/UX by @bomberrie")]
[assembly: AssemblyProduct("K-BNG-M-Hoster")]
[assembly: AssemblyCopyright("Copyright (c) 2026 Kinan - UI/UX by @bomberrie")]
[assembly: AssemblyVersion("0.7.2.5")]
[assembly: AssemblyFileVersion("0.7.2.5")]

namespace KBnGMHoster.Packaging
{
    public class UninstallerForm : Form
    {
        [DllImport("user32.dll")]
        public static extern bool ReleaseCapture();
        [DllImport("user32.dll")]
        public static extern IntPtr SendMessage(IntPtr hWnd, int Msg, IntPtr wParam, IntPtr lParam);
        [DllImport("user32.dll")]
        public static extern bool SetProcessDPIAware();

        private const int WM_NCLBUTTONDOWN = 0xA1;
        private const int HT_CAPTION = 0x2;

        private Panel pnlHeader;
        private Panel pnlContent;
        private Panel pnlFooter;
        private Label lblTitle;
        private Label lblSubtitle;
        private CheckBox chkKeepData;
        private ProgressBar prgProgress;
        private Label lblStatus;
        private Button btnAction;
        private Button btnCancel;
        private Button btnClose;

        private readonly Color colBg = Color.FromArgb(12, 12, 16);
        private readonly Color colSurface = Color.FromArgb(20, 20, 27);
        private readonly Color colSurfaceBorder = Color.FromArgb(39, 39, 51);
        private readonly Color colText = Color.FromArgb(244, 244, 245);
        private readonly Color colMuted = Color.FromArgb(161, 161, 170);
        private readonly Color colDanger = Color.FromArgb(244, 63, 94);
        private readonly Color colSuccess = Color.FromArgb(16, 185, 129);

        private readonly string installDir;
        private bool isSilent = false;

        public UninstallerForm(string[] args)
        {
            try { SetProcessDPIAware(); } catch { }

            foreach (string a in args)
            {
                if (a.Equals("/quiet", StringComparison.OrdinalIgnoreCase) || a.Equals("/silent", StringComparison.OrdinalIgnoreCase))
                {
                    isSilent = true;
                }
            }

            installDir = AppDomain.CurrentDomain.BaseDirectory.TrimEnd('\\', '/');

            InitializeComponent();
        }

        private void InitializeComponent()
        {
            this.Size = new Size(540, 360);
            this.FormBorderStyle = FormBorderStyle.None;
            this.StartPosition = FormStartPosition.CenterScreen;
            this.BackColor = colBg;
            this.DoubleBuffered = true;

            // Load Icon if exists
            string icoPath = Path.Combine(installDir, "app.ico");
            if (File.Exists(icoPath))
            {
                try { this.Icon = new Icon(icoPath); } catch { }
            }

            // Header
            pnlHeader = new Panel
            {
                Dock = DockStyle.Top,
                Height = 44,
                BackColor = colSurface
            };
            pnlHeader.MouseDown += (s, e) =>
            {
                if (e.Button == MouseButtons.Left)
                {
                    ReleaseCapture();
                    SendMessage(this.Handle, WM_NCLBUTTONDOWN, (IntPtr)HT_CAPTION, IntPtr.Zero);
                }
            };

            Label hdrTitle = new Label
            {
                Text = "K BNG M Hoster - Uninstall",
                Font = new Font("Segoe UI Semibold", 9.5f),
                ForeColor = colText,
                Location = new Point(16, 12),
                AutoSize = true
            };
            hdrTitle.MouseDown += (s, e) =>
            {
                if (e.Button == MouseButtons.Left)
                {
                    ReleaseCapture();
                    SendMessage(this.Handle, WM_NCLBUTTONDOWN, (IntPtr)HT_CAPTION, IntPtr.Zero);
                }
            };

            btnClose = new Button
            {
                Text = "x",
                Font = new Font("Segoe UI", 10f),
                ForeColor = colMuted,
                BackColor = Color.Transparent,
                FlatStyle = FlatStyle.Flat,
                Size = new Size(36, 28),
                Location = new Point(pnlHeader.Width - 44, 8),
                Anchor = AnchorStyles.Top | AnchorStyles.Right,
                Cursor = Cursors.Hand
            };
            btnClose.FlatAppearance.BorderSize = 0;
            btnClose.FlatAppearance.MouseOverBackColor = Color.FromArgb(40, 244, 63, 94);
            btnClose.Click += (s, e) => this.Close();

            pnlHeader.Controls.Add(hdrTitle);
            pnlHeader.Controls.Add(btnClose);

            // Content Panel
            pnlContent = new Panel
            {
                Dock = DockStyle.Fill,
                Padding = new Padding(28, 20, 28, 16),
                BackColor = colBg
            };

            lblTitle = new Label
            {
                Text = "Uninstall K BNG M Hoster",
                Font = new Font("Segoe UI", 16f, FontStyle.Bold),
                ForeColor = colText,
                Location = new Point(28, 20),
                AutoSize = true
            };

            lblSubtitle = new Label
            {
                Text = "Are you sure you want to remove K BNG M Hoster from this computer?",
                Font = new Font("Segoe UI", 9.5f),
                ForeColor = colMuted,
                Location = new Point(28, 56),
                Size = new Size(480, 40)
            };

            Panel pnlCard = new Panel
            {
                Location = new Point(28, 105),
                Size = new Size(484, 86),
                BackColor = colSurface
            };
            pnlCard.Paint += (s, e) =>
            {
                using (Pen p = new Pen(colSurfaceBorder, 1))
                {
                    e.Graphics.DrawRectangle(p, 0, 0, pnlCard.Width - 1, pnlCard.Height - 1);
                }
            };

            Label lblLoc = new Label
            {
                Text = "Installed Location:",
                Font = new Font("Segoe UI Semibold", 8.5f),
                ForeColor = colMuted,
                Location = new Point(14, 12),
                AutoSize = true
            };

            Label lblPathVal = new Label
            {
                Text = installDir,
                Font = new Font("Consolas", 8.5f),
                ForeColor = colText,
                Location = new Point(14, 32),
                Size = new Size(456, 18),
                AutoEllipsis = true
            };

            chkKeepData = new CheckBox
            {
                Text = "Keep server configuration (ServerConfig.toml) and custom mods",
                Font = new Font("Segoe UI", 9f),
                ForeColor = colText,
                Location = new Point(14, 56),
                Size = new Size(456, 22),
                Checked = true,
                Cursor = Cursors.Hand
            };

            pnlCard.Controls.Add(lblLoc);
            pnlCard.Controls.Add(lblPathVal);
            pnlCard.Controls.Add(chkKeepData);

            prgProgress = new ProgressBar
            {
                Location = new Point(28, 130),
                Size = new Size(484, 16),
                Visible = false,
                Style = ProgressBarStyle.Marquee,
                MarqueeAnimationSpeed = 30
            };

            lblStatus = new Label
            {
                Text = "",
                Font = new Font("Segoe UI", 9f),
                ForeColor = colMuted,
                Location = new Point(28, 154),
                Size = new Size(484, 24),
                Visible = false
            };

            pnlContent.Controls.Add(lblTitle);
            pnlContent.Controls.Add(lblSubtitle);
            pnlContent.Controls.Add(pnlCard);
            pnlContent.Controls.Add(prgProgress);
            pnlContent.Controls.Add(lblStatus);

            // Footer
            pnlFooter = new Panel
            {
                Dock = DockStyle.Bottom,
                Height = 64,
                BackColor = colSurface
            };
            pnlFooter.Paint += (s, e) =>
            {
                using (Pen p = new Pen(colSurfaceBorder, 1))
                {
                    e.Graphics.DrawLine(p, 0, 0, pnlFooter.Width, 0);
                }
            };

            btnAction = new Button
            {
                Text = "Uninstall",
                Font = new Font("Segoe UI Semibold", 9.5f),
                ForeColor = Color.White,
                BackColor = colDanger,
                FlatStyle = FlatStyle.Flat,
                Size = new Size(110, 36),
                Location = new Point(pnlFooter.Width - 138, 14),
                Anchor = AnchorStyles.Top | AnchorStyles.Right,
                Cursor = Cursors.Hand
            };
            btnAction.FlatAppearance.BorderSize = 0;
            btnAction.Click += (s, e) => StartUninstall();

            btnCancel = new Button
            {
                Text = "Cancel",
                Font = new Font("Segoe UI", 9.5f),
                ForeColor = colText,
                BackColor = Color.FromArgb(28, 28, 36),
                FlatStyle = FlatStyle.Flat,
                Size = new Size(90, 36),
                Location = new Point(pnlFooter.Width - 238, 14),
                Anchor = AnchorStyles.Top | AnchorStyles.Right,
                Cursor = Cursors.Hand
            };
            btnCancel.FlatAppearance.BorderColor = colSurfaceBorder;
            btnCancel.Click += (s, e) => this.Close();

            pnlFooter.Controls.Add(btnCancel);
            pnlFooter.Controls.Add(btnAction);

            this.Controls.Add(pnlContent);
            this.Controls.Add(pnlFooter);
            this.Controls.Add(pnlHeader);

            // Paint border around window
            this.Paint += (s, e) =>
            {
                using (Pen p = new Pen(colSurfaceBorder, 1))
                {
                    e.Graphics.DrawRectangle(p, 0, 0, this.Width - 1, this.Height - 1);
                }
            };
        }

        protected override void OnShown(EventArgs e)
        {
            base.OnShown(e);
            if (isSilent)
            {
                StartUninstall();
            }
        }

        private void StartUninstall()
        {
            btnAction.Enabled = false;
            btnCancel.Enabled = false;
            chkKeepData.Visible = false;
            prgProgress.Visible = true;
            lblStatus.Visible = true;
            lblSubtitle.Text = "Removing files and shortcuts...";

            bool keepConfig = chkKeepData.Checked;

            Thread t = new Thread(() =>
            {
                try
                {
                    SetStatus("Closing running server processes...");
                    KillProcess("BeamMP-Server");
                    KillProcess("K-BNG-M-Hoster");

                    Thread.Sleep(500);

                    SetStatus("Removing shortcuts...");
                    RemoveShortcuts();

                    SetStatus("Removing Windows uninstall entries...");
                    RemoveRegistry();

                    SetStatus("Removing application files...");
                    CleanFiles(keepConfig);

                    this.Invoke((MethodInvoker)delegate
                    {
                        prgProgress.Visible = false;
                        lblTitle.Text = "Uninstall Complete";
                        lblTitle.ForeColor = colSuccess;
                        lblSubtitle.Text = "K BNG M Hoster has been removed from your computer.";
                        lblStatus.Text = keepConfig ? "Server configuration and custom mods were preserved." : "All files were removed.";
                        btnAction.Text = "Close";
                        btnAction.BackColor = colSurface;
                        btnAction.ForeColor = colText;
                        btnAction.Enabled = true;
                        btnAction.Click -= (s, e) => StartUninstall();
                        btnAction.Click += (s, e) =>
                        {
                            SelfDeleteAndExit();
                        };
                        btnCancel.Visible = false;

                        if (isSilent)
                        {
                            SelfDeleteAndExit();
                        }
                    });
                }
                catch (Exception ex)
                {
                    this.Invoke((MethodInvoker)delegate
                    {
                        prgProgress.Visible = false;
                        lblStatus.Text = "Error during uninstall: " + ex.Message;
                        btnAction.Text = "Close";
                        btnAction.Enabled = true;
                        btnAction.Click += (s, e) => this.Close();
                    });
                }
            });
            t.IsBackground = true;
            t.Start();
        }

        private void SetStatus(string text)
        {
            if (this.InvokeRequired)
            {
                this.Invoke((MethodInvoker)(() => SetStatus(text)));
                return;
            }
            lblStatus.Text = text;
        }

        private void KillProcess(string name)
        {
            try
            {
                Process[] procs = Process.GetProcessesByName(name);
                foreach (Process p in procs)
                {
                    try { p.Kill(); p.WaitForExit(1000); } catch { }
                }
            }
            catch { }
        }

        private void RemoveShortcuts()
        {
            try
            {
                string desktopLnk = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.DesktopDirectory), "K-BNG-M-Hoster.lnk");
                if (File.Exists(desktopLnk)) File.Delete(desktopLnk);

                string startMenuLnk = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.StartMenu), "Programs", "K-BNG-M-Hoster.lnk");
                if (File.Exists(startMenuLnk)) File.Delete(startMenuLnk);
            }
            catch { }
        }

        private void RemoveRegistry()
        {
            try
            {
                using (RegistryKey key = Registry.CurrentUser.OpenSubKey(@"Software\Microsoft\Windows\CurrentVersion\Uninstall", true))
                {
                    if (key != null)
                    {
                        key.DeleteSubKeyTree("K-BNG-M-Hoster", false);
                    }
                }
            }
            catch { }
        }

        private void CleanFiles(bool keepConfig)
        {
            try
            {
                DirectoryInfo di = new DirectoryInfo(installDir);
                foreach (FileInfo file in di.GetFiles())
                {
                    if (file.Name.Equals("Uninstall.exe", StringComparison.OrdinalIgnoreCase)) continue;
                    try { file.Delete(); } catch { }
                }

                foreach (DirectoryInfo sub in di.GetDirectories())
                {
                    if (keepConfig && sub.Name.Equals("Server", StringComparison.OrdinalIgnoreCase))
                    {
                        CleanServerDir(sub.FullName, true);
                    }
                    else
                    {
                        try { Directory.Delete(sub.FullName, true); } catch { }
                    }
                }
            }
            catch { }
        }

        private void CleanServerDir(string serverDir, bool keepConfig)
        {
            try
            {
                DirectoryInfo sdi = new DirectoryInfo(serverDir);
                foreach (FileInfo f in sdi.GetFiles())
                {
                    if (keepConfig && (f.Name.Equals("ServerConfig.toml", StringComparison.OrdinalIgnoreCase) ||
                                      f.Name.Equals(".env", StringComparison.OrdinalIgnoreCase)))
                    {
                        continue;
                    }
                    try { f.Delete(); } catch { }
                }

                foreach (DirectoryInfo sub in sdi.GetDirectories())
                {
                    if (keepConfig && sub.Name.Equals("Resources", StringComparison.OrdinalIgnoreCase))
                    {
                        continue;
                    }
                    try { Directory.Delete(sub.FullName, true); } catch { }
                }
            }
            catch { }
        }

        private void SelfDeleteAndExit()
        {
            try
            {
                string uninstallerPath = Application.ExecutablePath;
                ProcessStartInfo psi = new ProcessStartInfo
                {
                    FileName = "cmd.exe",
                    Arguments = string.Format("/c timeout /t 1 /nobreak >nul & del /f /q \"{0}\" & rmdir \"{1}\" 2>nul", uninstallerPath, installDir),
                    WindowStyle = ProcessWindowStyle.Hidden,
                    CreateNoWindow = true,
                    UseShellExecute = true
                };
                Process.Start(psi);
            }
            catch { }

            Application.Exit();
        }

        [STAThread]
        public static void Main(string[] args)
        {
            Application.EnableVisualStyles();
            Application.SetCompatibleTextRenderingDefault(false);
            Application.Run(new UninstallerForm(args));
        }
    }
}
