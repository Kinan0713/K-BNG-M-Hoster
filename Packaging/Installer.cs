using System;
using System.Diagnostics;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.IO;
using System.IO.Compression;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Threading;
using System.Windows.Forms;
using Microsoft.Win32;

[assembly: AssemblyTitle("K BNG M Hoster Setup")]
[assembly: AssemblyDescription("All-in-One Automated BeamMP Dedicated Server Console & Network Bridge Installer")]
[assembly: AssemblyCompany("Kinan (@kinan_sx240) - UI/UX by @bomberrie")]
[assembly: AssemblyProduct("K-BNG-M-Hoster")]
[assembly: AssemblyCopyright("Copyright (c) 2026 Kinan - UI/UX by @bomberrie")]
[assembly: AssemblyVersion("0.7.2.5")]
[assembly: AssemblyFileVersion("0.7.2.5")]

namespace KBnGMHoster.Packaging
{
    public class InstallerForm : Form
    {
        [DllImport("user32.dll")]
        public static extern bool ReleaseCapture();
        [DllImport("user32.dll")]
        public static extern IntPtr SendMessage(IntPtr hWnd, int Msg, IntPtr wParam, IntPtr lParam);
        [DllImport("user32.dll")]
        public static extern bool SetProcessDPIAware();
        [DllImport("shell32.dll", SetLastError = true)]
        public static extern int SetCurrentProcessExplicitAppUserModelID([MarshalAs(UnmanagedType.LPWStr)] string AppID);

        private const int WM_NCLBUTTONDOWN = 0xA1;
        private const int HT_CAPTION = 0x2;

        // Theme Palette
        private readonly Color colBg = Color.FromArgb(12, 12, 16);
        private readonly Color colSurface = Color.FromArgb(20, 20, 27);
        private readonly Color colSurfaceBorder = Color.FromArgb(39, 39, 51);
        private readonly Color colText = Color.FromArgb(244, 244, 245);
        private readonly Color colMuted = Color.FromArgb(161, 161, 170);
        private readonly Color colSubtle = Color.FromArgb(113, 113, 122);
        private readonly Color colAccent = Color.FromArgb(249, 115, 22); // BeamMP Orange
        private readonly Color colAccentHover = Color.FromArgb(251, 146, 60);
        private readonly Color colSuccess = Color.FromArgb(16, 185, 129); // Emerald

        // Layout panels
        private Panel pnlHeader;
        private Panel pnlFooter;
        private Panel pnlStep1;
        private Panel pnlStep2;
        private Panel pnlStep3;

        // Step 1 controls
        private TextBox txtInstallPath;
        private CheckBox chkDesktopShortcut;
        private CheckBox chkStartMenuShortcut;
        private CheckBox chkLaunchAfter;
        private Label lblDiskSpace;

        // Step 2 controls
        private Label lblStep2Title;
        private Label lblStep2Status;
        private ProgressBar prgInstall;
        private Label lblStep2Percent;

        // Step 3 controls
        private Label lblStep3Title;
        private Label lblStep3Desc;
        private Label lblStep3Path;

        // Footer buttons
        private Button btnPrimary;
        private Button btnSecondary;
        private Button btnClose;

        private bool isSilent = false;
        private string chosenPath = "";

        public InstallerForm(string[] args)
        {
            try { SetProcessDPIAware(); } catch { }
            try { SetCurrentProcessExplicitAppUserModelID("Kinan.KBNGMHoster.Installer"); } catch { }

            foreach (string a in args)
            {
                if (a.Equals("/quiet", StringComparison.OrdinalIgnoreCase) || a.Equals("/silent", StringComparison.OrdinalIgnoreCase))
                {
                    isSilent = true;
                }
            }

            string defaultDir = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Programs", "K-BNG-M-Hoster");
            chosenPath = defaultDir;

            InitializeUI();
        }

        private void InitializeUI()
        {
            this.Size = new Size(640, 470);
            this.FormBorderStyle = FormBorderStyle.None;
            this.StartPosition = FormStartPosition.CenterScreen;
            this.BackColor = colBg;
            this.DoubleBuffered = true;

            // Load Icon from stream or assembly
            try
            {
                using (Stream icoStream = Assembly.GetExecutingAssembly().GetManifestResourceStream("app.ico"))
                {
                    if (icoStream != null) this.Icon = new Icon(icoStream);
                }
            }
            catch { }

            // -------------------------------------------------------------
            // TOP TITLEBAR & HEADER
            // -------------------------------------------------------------
            pnlHeader = new Panel
            {
                Dock = DockStyle.Top,
                Height = 84,
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

            // Window close button
            btnClose = new Button
            {
                Text = "x",
                Font = new Font("Segoe UI", 10.5f),
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

            // Window minimize button
            Button btnMin = new Button
            {
                Text = "-",
                Font = new Font("Segoe UI", 11f),
                ForeColor = colMuted,
                BackColor = Color.Transparent,
                FlatStyle = FlatStyle.Flat,
                Size = new Size(36, 28),
                Location = new Point(pnlHeader.Width - 80, 8),
                Anchor = AnchorStyles.Top | AnchorStyles.Right,
                Cursor = Cursors.Hand
            };
            btnMin.FlatAppearance.BorderSize = 0;
            btnMin.FlatAppearance.MouseOverBackColor = Color.FromArgb(20, 255, 255, 255);
            btnMin.Click += (s, e) => this.WindowState = FormWindowState.Minimized;

            // Header Branding Icon + Titles
            PictureBox picIcon = new PictureBox
            {
                Size = new Size(44, 44),
                Location = new Point(22, 18),
                SizeMode = PictureBoxSizeMode.Zoom,
                BackColor = Color.Transparent
            };
            if (this.Icon != null) picIcon.Image = this.Icon.ToBitmap();

            Label lblApp = new Label
            {
                Text = "K BNG M Hoster",
                Font = new Font("Segoe UI", 14f, FontStyle.Bold),
                ForeColor = colText,
                Location = new Point(76, 17),
                AutoSize = true
            };

            Label lblVer = new Label
            {
                Text = "v0.7.2.5",
                Font = new Font("Segoe UI Semibold", 8f),
                ForeColor = colAccent,
                BackColor = Color.FromArgb(35, 249, 115, 22),
                Location = new Point(238, 22),
                Padding = new Padding(4, 2, 4, 2),
                AutoSize = true
            };

            Label lblTag = new Label
            {
                Text = "Automated BeamMP Dedicated Server Console & Network Bridge",
                Font = new Font("Segoe UI", 9f),
                ForeColor = colMuted,
                Location = new Point(77, 44),
                AutoSize = true
            };

            pnlHeader.Controls.Add(btnClose);
            pnlHeader.Controls.Add(btnMin);
            pnlHeader.Controls.Add(picIcon);
            pnlHeader.Controls.Add(lblApp);
            pnlHeader.Controls.Add(lblVer);
            pnlHeader.Controls.Add(lblTag);

            // -------------------------------------------------------------
            // FOOTER BAR
            // -------------------------------------------------------------
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

            btnPrimary = new Button
            {
                Text = "Install Now",
                Font = new Font("Segoe UI Semibold", 10f),
                ForeColor = Color.White,
                BackColor = colAccent,
                FlatStyle = FlatStyle.Flat,
                Size = new Size(130, 38),
                Location = new Point(pnlFooter.Width - 156, 13),
                Anchor = AnchorStyles.Top | AnchorStyles.Right,
                Cursor = Cursors.Hand
            };
            btnPrimary.FlatAppearance.BorderSize = 0;
            btnPrimary.FlatAppearance.MouseOverBackColor = colAccentHover;
            btnPrimary.Click += (s, e) => OnPrimaryClicked();

            btnSecondary = new Button
            {
                Text = "Cancel",
                Font = new Font("Segoe UI", 9.5f),
                ForeColor = colText,
                BackColor = Color.FromArgb(28, 28, 36),
                FlatStyle = FlatStyle.Flat,
                Size = new Size(96, 38),
                Location = new Point(pnlFooter.Width - 262, 13),
                Anchor = AnchorStyles.Top | AnchorStyles.Right,
                Cursor = Cursors.Hand
            };
            btnSecondary.FlatAppearance.BorderColor = colSurfaceBorder;
            btnSecondary.Click += (s, e) => this.Close();

            pnlFooter.Controls.Add(btnSecondary);
            pnlFooter.Controls.Add(btnPrimary);

            // -------------------------------------------------------------
            // STEP 1 PANEL: CONFIGURATION & OPTIONS
            // -------------------------------------------------------------
            pnlStep1 = new Panel
            {
                Dock = DockStyle.Fill,
                BackColor = colBg,
                Padding = new Padding(26, 18, 26, 14)
            };

            // Path Selection Card
            Panel cardPath = new Panel
            {
                Location = new Point(26, 16),
                Size = new Size(588, 108),
                BackColor = colSurface
            };
            cardPath.Paint += (s, e) =>
            {
                using (Pen p = new Pen(colSurfaceBorder, 1))
                {
                    e.Graphics.DrawRectangle(p, 0, 0, cardPath.Width - 1, cardPath.Height - 1);
                }
            };

            Label lblPathHead = new Label
            {
                Text = "Installation Directory",
                Font = new Font("Segoe UI Semibold", 9.5f),
                ForeColor = colText,
                Location = new Point(14, 12),
                AutoSize = true
            };

            txtInstallPath = new TextBox
            {
                Text = chosenPath,
                Font = new Font("Segoe UI", 9.5f),
                ForeColor = colText,
                BackColor = Color.FromArgb(14, 14, 18),
                BorderStyle = BorderStyle.FixedSingle,
                Location = new Point(16, 38),
                Size = new Size(460, 26)
            };
            txtInstallPath.TextChanged += (s, e) =>
            {
                chosenPath = txtInstallPath.Text;
                UpdateDiskSpace();
            };

            Button btnBrowse = new Button
            {
                Text = "Browse...",
                Font = new Font("Segoe UI", 9f),
                ForeColor = colText,
                BackColor = Color.FromArgb(28, 28, 36),
                FlatStyle = FlatStyle.Flat,
                Size = new Size(86, 26),
                Location = new Point(484, 38),
                Cursor = Cursors.Hand
            };
            btnBrowse.FlatAppearance.BorderColor = colSurfaceBorder;
            btnBrowse.Click += (s, e) =>
            {
                using (FolderBrowserDialog fbd = new FolderBrowserDialog())
                {
                    fbd.Description = "Select Destination Folder for K BNG M Hoster";
                    fbd.SelectedPath = chosenPath;
                    if (fbd.ShowDialog() == DialogResult.OK)
                    {
                        txtInstallPath.Text = fbd.SelectedPath;
                    }
                }
            };

            lblDiskSpace = new Label
            {
                Text = "Space required: ~35 MB",
                Font = new Font("Segoe UI", 8.5f),
                ForeColor = colSubtle,
                Location = new Point(16, 74),
                AutoSize = true
            };

            cardPath.Controls.Add(lblPathHead);
            cardPath.Controls.Add(txtInstallPath);
            cardPath.Controls.Add(btnBrowse);
            cardPath.Controls.Add(lblDiskSpace);

            // Shortcuts & Options Card
            Panel cardOptions = new Panel
            {
                Location = new Point(26, 138),
                Size = new Size(588, 140),
                BackColor = colSurface
            };
            cardOptions.Paint += (s, e) =>
            {
                using (Pen p = new Pen(colSurfaceBorder, 1))
                {
                    e.Graphics.DrawRectangle(p, 0, 0, cardOptions.Width - 1, cardOptions.Height - 1);
                }
            };

            Label lblOptHead = new Label
            {
                Text = "Setup Preferences",
                Font = new Font("Segoe UI Semibold", 9.5f),
                ForeColor = colText,
                Location = new Point(14, 12),
                AutoSize = true
            };

            chkDesktopShortcut = new CheckBox
            {
                Text = "Create a Desktop shortcut",
                Font = new Font("Segoe UI", 9f),
                ForeColor = colText,
                Location = new Point(18, 40),
                Size = new Size(500, 24),
                Checked = true,
                Cursor = Cursors.Hand
            };

            chkStartMenuShortcut = new CheckBox
            {
                Text = "Create a Start Menu shortcut",
                Font = new Font("Segoe UI", 9f),
                ForeColor = colText,
                Location = new Point(18, 68),
                Size = new Size(500, 24),
                Checked = true,
                Cursor = Cursors.Hand
            };

            chkLaunchAfter = new CheckBox
            {
                Text = "Launch K-BNG-M-Hoster immediately when finished",
                Font = new Font("Segoe UI", 9f),
                ForeColor = colText,
                Location = new Point(18, 96),
                Size = new Size(500, 24),
                Checked = true,
                Cursor = Cursors.Hand
            };

            cardOptions.Controls.Add(lblOptHead);
            cardOptions.Controls.Add(chkDesktopShortcut);
            cardOptions.Controls.Add(chkStartMenuShortcut);
            cardOptions.Controls.Add(chkLaunchAfter);

            pnlStep1.Controls.Add(cardPath);
            pnlStep1.Controls.Add(cardOptions);

            // -------------------------------------------------------------
            // STEP 2 PANEL: INSTALLING PROGRESS
            // -------------------------------------------------------------
            pnlStep2 = new Panel
            {
                Dock = DockStyle.Fill,
                BackColor = colBg,
                Padding = new Padding(26, 28, 26, 14),
                Visible = false
            };

            lblStep2Title = new Label
            {
                Text = "Installing K BNG M Hoster...",
                Font = new Font("Segoe UI", 15f, FontStyle.Bold),
                ForeColor = colText,
                Location = new Point(26, 40),
                AutoSize = true
            };

            Label lblStep2Sub = new Label
            {
                Text = "Please wait while application files and shortcuts are being extracted.",
                Font = new Font("Segoe UI", 9.5f),
                ForeColor = colMuted,
                Location = new Point(28, 76),
                AutoSize = true
            };

            prgInstall = new ProgressBar
            {
                Location = new Point(28, 136),
                Size = new Size(584, 22),
                Minimum = 0,
                Maximum = 100,
                Value = 0
            };

            lblStep2Percent = new Label
            {
                Text = "0%",
                Font = new Font("Segoe UI Semibold", 9.5f),
                ForeColor = colAccent,
                Location = new Point(570, 114),
                Size = new Size(44, 20),
                TextAlign = ContentAlignment.TopRight
            };

            lblStep2Status = new Label
            {
                Text = "Preparing installation...",
                Font = new Font("Consolas", 8.5f),
                ForeColor = colMuted,
                Location = new Point(28, 168),
                Size = new Size(584, 40),
                AutoEllipsis = true
            };

            pnlStep2.Controls.Add(lblStep2Title);
            pnlStep2.Controls.Add(lblStep2Sub);
            pnlStep2.Controls.Add(prgInstall);
            pnlStep2.Controls.Add(lblStep2Percent);
            pnlStep2.Controls.Add(lblStep2Status);

            // -------------------------------------------------------------
            // STEP 3 PANEL: COMPLETED
            // -------------------------------------------------------------
            pnlStep3 = new Panel
            {
                Dock = DockStyle.Fill,
                BackColor = colBg,
                Padding = new Padding(26, 28, 26, 14),
                Visible = false
            };

            lblStep3Title = new Label
            {
                Text = "Installation Complete!",
                Font = new Font("Segoe UI", 16f, FontStyle.Bold),
                ForeColor = colSuccess,
                Location = new Point(26, 32),
                AutoSize = true
            };

            lblStep3Desc = new Label
            {
                Text = "K BNG M Hoster is ready to host your BeamNG multiplayer sessions.",
                Font = new Font("Segoe UI", 10f),
                ForeColor = colText,
                Location = new Point(28, 70),
                AutoSize = true
            };

            Panel cardDone = new Panel
            {
                Location = new Point(26, 115),
                Size = new Size(588, 120),
                BackColor = colSurface
            };
            cardDone.Paint += (s, e) =>
            {
                using (Pen p = new Pen(colSurfaceBorder, 1))
                {
                    e.Graphics.DrawRectangle(p, 0, 0, cardDone.Width - 1, cardDone.Height - 1);
                }
            };

            Label lblDoneHead = new Label
            {
                Text = "Installed Location:",
                Font = new Font("Segoe UI Semibold", 8.5f),
                ForeColor = colMuted,
                Location = new Point(14, 12),
                AutoSize = true
            };

            lblStep3Path = new Label
            {
                Text = "",
                Font = new Font("Consolas", 9f),
                ForeColor = colText,
                Location = new Point(14, 34),
                Size = new Size(556, 20),
                AutoEllipsis = true
            };

            Label lblDoneTips = new Label
            {
                Text = "* Start Menu and Desktop shortcuts have been registered.\n* Uninstaller is configured in Windows 'Installed Apps' / 'Programs and Features'.",
                Font = new Font("Segoe UI", 8.5f),
                ForeColor = colSubtle,
                Location = new Point(14, 62),
                Size = new Size(556, 42)
            };

            cardDone.Controls.Add(lblDoneHead);
            cardDone.Controls.Add(lblStep3Path);
            cardDone.Controls.Add(lblDoneTips);

            pnlStep3.Controls.Add(lblStep3Title);
            pnlStep3.Controls.Add(lblStep3Desc);
            pnlStep3.Controls.Add(cardDone);

            // Add all panels
            this.Controls.Add(pnlStep1);
            this.Controls.Add(pnlStep2);
            this.Controls.Add(pnlStep3);
            this.Controls.Add(pnlFooter);
            this.Controls.Add(pnlHeader);

            // Window border
            this.Paint += (s, e) =>
            {
                using (Pen p = new Pen(colSurfaceBorder, 1))
                {
                    e.Graphics.DrawRectangle(p, 0, 0, this.Width - 1, this.Height - 1);
                }
            };

            UpdateDiskSpace();
        }

        private void UpdateDiskSpace()
        {
            try
            {
                string root = Path.GetPathRoot(chosenPath);
                if (!string.IsNullOrEmpty(root) && Directory.Exists(root))
                {
                    DriveInfo drive = new DriveInfo(root);
                    double freeGb = (double)drive.AvailableFreeSpace / (1024 * 1024 * 1024);
                    lblDiskSpace.Text = string.Format("Space required: ~35 MB  *  Available on drive {0}: {1:F1} GB", root.TrimEnd('\\'), freeGb);
                }
            }
            catch { }
        }

        protected override void OnShown(EventArgs e)
        {
            base.OnShown(e);
            if (isSilent)
            {
                StartInstall();
            }
        }

        private void OnPrimaryClicked()
        {
            if (pnlStep1.Visible)
            {
                StartInstall();
            }
            else if (pnlStep3.Visible)
            {
                LaunchAndExit();
            }
        }

        private void StartInstall()
        {
            pnlStep1.Visible = false;
            pnlStep2.Visible = true;
            btnPrimary.Enabled = false;
            btnSecondary.Enabled = false;

            string targetDir = chosenPath.Trim();
            bool makeDesktop = chkDesktopShortcut.Checked;
            bool makeStartMenu = chkStartMenuShortcut.Checked;
            bool launchWhenDone = chkLaunchAfter.Checked;

            Thread t = new Thread(() =>
            {
                try
                {
                    PerformExtraction(targetDir);

                    SetStatus("Creating shortcuts...");
                    string exePath = Path.Combine(targetDir, "K-BNG-M-Hoster.exe");
                    string icoPath = Path.Combine(targetDir, "app.ico");

                    if (makeDesktop)
                    {
                        string deskLnk = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.DesktopDirectory), "K-BNG-M-Hoster.lnk");
                        CreateShortcut(deskLnk, exePath, targetDir, icoPath, "K BNG M Hoster - BeamNG Dedicated Server");
                    }

                    if (makeStartMenu)
                    {
                        string startDir = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.StartMenu), "Programs");
                        if (!Directory.Exists(startDir)) Directory.CreateDirectory(startDir);
                        string startLnk = Path.Combine(startDir, "K-BNG-M-Hoster.lnk");
                        CreateShortcut(startLnk, exePath, targetDir, icoPath, "K BNG M Hoster - BeamNG Dedicated Server");
                    }

                    SetStatus("Registering Windows uninstall entries...");
                    RegisterUninstall(targetDir);

                    SetProgress(100);

                    this.Invoke((MethodInvoker)delegate
                    {
                        pnlStep2.Visible = false;
                        pnlStep3.Visible = true;
                        lblStep3Path.Text = targetDir;

                        btnPrimary.Text = launchWhenDone ? "Launch Now" : "Finish";
                        btnPrimary.Enabled = true;
                        btnPrimary.BackColor = colSuccess;
                        btnSecondary.Visible = false;

                        if (isSilent)
                        {
                            if (launchWhenDone) LaunchAndExit();
                            else Application.Exit();
                        }
                    });
                }
                catch (Exception ex)
                {
                    this.Invoke((MethodInvoker)delegate
                    {
                        lblStep2Title.Text = "Installation Failed";
                        lblStep2Title.ForeColor = Color.FromArgb(244, 63, 94);
                        lblStep2Status.Text = "Error: " + ex.Message;
                        btnPrimary.Text = "Close";
                        btnPrimary.Enabled = true;
                        btnPrimary.Click -= (s, ev) => OnPrimaryClicked();
                        btnPrimary.Click += (s, ev) => this.Close();
                    });
                }
            });
            t.IsBackground = true;
            t.Start();
        }

        private void PerformExtraction(string targetDir)
        {
            if (!Directory.Exists(targetDir))
            {
                Directory.CreateDirectory(targetDir);
            }

            Assembly asm = Assembly.GetExecutingAssembly();
            using (Stream s = asm.GetManifestResourceStream("payload.zip"))
            {
                if (s == null)
                {
                    throw new InvalidOperationException("Embedded installation payload not found inside installer binary.");
                }

                using (ZipArchive zip = new ZipArchive(s, ZipArchiveMode.Read))
                {
                    int total = zip.Entries.Count;
                    int count = 0;

                    foreach (ZipArchiveEntry entry in zip.Entries)
                    {
                        count++;
                        int pct = (int)(((double)count / total) * 90);
                        SetProgress(pct);
                        SetStatus("Extracting: " + entry.FullName);

                        string fullPath = Path.Combine(targetDir, entry.FullName);
                        string dir = Path.GetDirectoryName(fullPath);
                        if (!string.IsNullOrEmpty(dir) && !Directory.Exists(dir))
                        {
                            Directory.CreateDirectory(dir);
                        }

                        if (!string.IsNullOrEmpty(entry.Name))
                        {
                            entry.ExtractToFile(fullPath, true);
                        }
                    }
                }
            }
        }

        private void SetStatus(string msg)
        {
            if (this.InvokeRequired)
            {
                this.Invoke((MethodInvoker)(() => SetStatus(msg)));
                return;
            }
            lblStep2Status.Text = msg;
        }

        private void SetProgress(int value)
        {
            if (this.InvokeRequired)
            {
                this.Invoke((MethodInvoker)(() => SetProgress(value)));
                return;
            }
            prgInstall.Value = Math.Min(100, Math.Max(0, value));
            lblStep2Percent.Text = prgInstall.Value + "%";
        }

        private void CreateShortcut(string shortcutPath, string targetExe, string workDir, string iconPath, string description)
        {
            try
            {
                Type shellType = Type.GetTypeFromProgID("WScript.Shell");
                if (shellType == null) return;
                object shell = Activator.CreateInstance(shellType);
                object shortcut = shellType.InvokeMember("CreateShortcut", BindingFlags.InvokeMethod, null, shell, new object[] { shortcutPath });
                Type scType = shortcut.GetType();
                scType.InvokeMember("TargetPath", BindingFlags.SetProperty, null, shortcut, new object[] { targetExe });
                scType.InvokeMember("WorkingDirectory", BindingFlags.SetProperty, null, shortcut, new object[] { workDir });
                if (File.Exists(iconPath))
                {
                    scType.InvokeMember("IconLocation", BindingFlags.SetProperty, null, shortcut, new object[] { iconPath + ",0" });
                }
                scType.InvokeMember("Description", BindingFlags.SetProperty, null, shortcut, new object[] { description });
                scType.InvokeMember("Save", BindingFlags.InvokeMethod, null, shortcut, null);
            }
            catch { }
        }

        private void RegisterUninstall(string installDir)
        {
            try
            {
                string keyPath = @"Software\Microsoft\Windows\CurrentVersion\Uninstall\K-BNG-M-Hoster";
                using (RegistryKey key = Registry.CurrentUser.CreateSubKey(keyPath))
                {
                    if (key == null) return;
                    string exePath = Path.Combine(installDir, "K-BNG-M-Hoster.exe");
                    string uninstallerPath = Path.Combine(installDir, "Uninstall.exe");
                    string iconPath = Path.Combine(installDir, "app.ico");

                    key.SetValue("DisplayName", "K BNG M Hoster", RegistryValueKind.String);
                    key.SetValue("DisplayVersion", "0.7.2.5", RegistryValueKind.String);
                    key.SetValue("Publisher", "Kinan (@kinan_sx240) - UI/UX by @bomberrie", RegistryValueKind.String);
                    key.SetValue("InstallLocation", installDir, RegistryValueKind.String);
                    key.SetValue("DisplayIcon", File.Exists(iconPath) ? iconPath : exePath, RegistryValueKind.String);
                    key.SetValue("UninstallString", "\"" + uninstallerPath + "\"", RegistryValueKind.String);
                    key.SetValue("QuietUninstallString", "\"" + uninstallerPath + "\" /quiet", RegistryValueKind.String);
                    key.SetValue("URLInfoAbout", "https://github.com/bomberrie/K-BNG-M-Hoster", RegistryValueKind.String);
                    key.SetValue("EstimatedSize", 35000, RegistryValueKind.DWord);
                    key.SetValue("NoModify", 1, RegistryValueKind.DWord);
                    key.SetValue("NoRepair", 1, RegistryValueKind.DWord);
                }
            }
            catch { }
        }

        private void LaunchAndExit()
        {
            try
            {
                string exePath = Path.Combine(chosenPath, "K-BNG-M-Hoster.exe");
                if (File.Exists(exePath))
                {
                    ProcessStartInfo psi = new ProcessStartInfo
                    {
                        FileName = exePath,
                        WorkingDirectory = chosenPath,
                        UseShellExecute = true
                    };
                    Process.Start(psi);
                }
            }
            catch { }

            Application.Exit();
        }

        [STAThread]
        public static void Main(string[] args)
        {
            Application.EnableVisualStyles();
            Application.SetCompatibleTextRenderingDefault(false);
            Application.Run(new InstallerForm(args));
        }
    }
}
