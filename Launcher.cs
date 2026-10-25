using System;
using System.Diagnostics;
using System.IO;
using System.Reflection;
using System.Windows.Forms;

[assembly: AssemblyTitle("K BNG M Hoster")]
[assembly: AssemblyDescription("All-in-One Automated BeamMP Dedicated Server Console & Network Bridge")]
[assembly: AssemblyConfiguration("")]
[assembly: AssemblyCompany("Kinan (@kinan_sx240) - UI/UX by @bomberrie")]
[assembly: AssemblyProduct("K-BNG-M-Hoster")]
[assembly: AssemblyCopyright("Copyright (c) 2026 Kinan - UI/UX by @bomberrie")]
[assembly: AssemblyTrademark("")]
[assembly: AssemblyCulture("")]
[assembly: AssemblyVersion("0.7.2.3")]
[assembly: AssemblyFileVersion("0.7.2.3")]

namespace KBnGMHoster
{
    static class Launcher
    {
        [STAThread]
        static void Main(string[] args)
        {
            string appDir = AppDomain.CurrentDomain.BaseDirectory;
            string scriptPath = Path.Combine(appDir, "Server", "Play_BeamMP.ps1");

            if (!File.Exists(scriptPath))
            {
                MessageBox.Show(
                    "Server\\Play_BeamMP.ps1 was not found.\n\n" +
                    "Did you launch this from inside a zip archive?\n" +
                    "Please extract all files from the zip first, then run K-BNG-M-Hoster.exe again.",
                    "K BNG M Hoster - Missing Files",
                    MessageBoxButtons.OK,
                    MessageBoxIcon.Warning
                );
                return;
            }

            string psExe = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.System), "WindowsPowerShell", "v1.0", "powershell.exe");
            if (!File.Exists(psExe))
            {
                psExe = "powershell.exe";
            }

            string passArgs = "";
            if (args != null && args.Length > 0)
            {
                passArgs = " " + string.Join(" ", args);
            }

            ProcessStartInfo psi = new ProcessStartInfo();
            psi.FileName = psExe;
            psi.Arguments = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File \"" + scriptPath + "\"" + passArgs;
            psi.WorkingDirectory = appDir;
            psi.UseShellExecute = true;
            psi.WindowStyle = ProcessWindowStyle.Hidden;

            try
            {
                Process.Start(psi);
            }
            catch (Exception ex)
            {
                MessageBox.Show(
                    "Failed to launch K BNG M Hoster:\n" + ex.Message,
                    "K BNG M Hoster - Error",
                    MessageBoxButtons.OK,
                    MessageBoxIcon.Error
                );
            }
        }
    }
}
