using System;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.Text.RegularExpressions;
using System.Windows.Forms;
using Microsoft.Win32;

[assembly: System.Reflection.AssemblyTitle("RobotTrajectoryLab")]
[assembly: System.Reflection.AssemblyVersion("1.0.1.0")]
[assembly: System.Reflection.AssemblyFileVersion("1.0.1.0")]

internal sealed class StartupWindow : Form
{
    private readonly string mode;
    private readonly string dataRoot;
    private readonly Label status;
    private readonly Timer timer;
    private Process application;
    private DateTime launchTime;
    private bool interfaceReady;
    internal int Outcome;

    internal StartupWindow(string[] args)
    {
        mode = args.Length > 0 ? args[0] : "--gui";
        if (mode != "--gui" && mode != "--launcher-check" && mode != "--startup-check" && mode != "--gui-smoke" && mode != "--selftest")
            throw new ArgumentException("Unsupported launch mode");
        string baseFolder = AppDomain.CurrentDomain.BaseDirectory;
        dataRoot = args.Length > 1 ? Path.GetFullPath(args[1]) : Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), "RobotTrajectoryLab_Data");
        Text = "RobotTrajectoryLab 1.0.1";
        ClientSize = new Size(460, 205);
        StartPosition = FormStartPosition.CenterScreen;
        FormBorderStyle = FormBorderStyle.FixedDialog;
        MaximizeBox = false;
        Font = new Font("Microsoft YaHei UI", 10);
        BackColor = Color.FromArgb(245, 247, 250);
        var title = new Label { Text = "机器人运动轨迹规划", AutoSize = true,
            Location = new Point(25, 24), Font = new Font(Font.FontFamily, 17, FontStyle.Bold),
            ForeColor = Color.FromArgb(24, 50, 78) };
        status = new Label { Text = "正在打开软件，请稍候……", AutoSize = false,
            Location = new Point(27, 78), Size = new Size(410, 48) };
        var progress = new ProgressBar { Style = ProgressBarStyle.Marquee,
            MarqueeAnimationSpeed = 30, Location = new Point(27, 139), Size = new Size(405, 15) };
        Controls.AddRange(new Control[] { title, status, progress });
        timer = new Timer { Interval = 300 };
        timer.Tick += InspectStartup;
        Shown += StartApplication;
        FormClosed += delegate { timer.Dispose(); if (application != null) application.Dispose(); };
    }

    private static string FindRuntime()
    {
        foreach (RegistryView view in new RegistryView[] { RegistryView.Registry64, RegistryView.Registry32 })
        {
            using (RegistryKey machine = RegistryKey.OpenBaseKey(RegistryHive.LocalMachine, view))
            using (RegistryKey key = machine.OpenSubKey(@"SOFTWARE\MathWorks\MATLAB Runtime\25.1"))
            {
                if (key == null) continue;
                string root = key.GetValue("MATLABROOT") as string;
                if (!String.IsNullOrEmpty(root) && File.Exists(Path.Combine(root, @"runtime\win64\mclmcrrt25_1.dll")))
                    return root;
            }
        }
        return null;
    }

    private void StartApplication(object sender, EventArgs e)
    {
        try
        {
            string runtime = FindRuntime();
            if (runtime == null)
                throw new InvalidOperationException("未找到 MATLAB Runtime R2025a。请先运行安装器文件夹内的 MATLAB_Runtime_Setup.exe。");
            string baseFolder = AppDomain.CurrentDomain.BaseDirectory;
            string executable = Path.Combine(baseFolder, @"app\RobotTrajectoryLab.exe");
            if (!File.Exists(executable))
                throw new FileNotFoundException("程序文件不完整，请完整解压压缩包后再启动。", executable);
            try { Directory.CreateDirectory(dataRoot); }
            catch (UnauthorizedAccessException)
            {
                throw new IOException("当前目录不能写入，请把整个程序文件夹移到可写位置后启动。");
            }
            launchTime = DateTime.UtcNow;
            string coreMode = mode == "--launcher-check" ? "--startup-check" : mode;
            var start = new ProcessStartInfo(executable, coreMode + " \"" + dataRoot + "\"");
            start.WorkingDirectory = baseFolder;
            start.UseShellExecute = false;
            start.CreateNoWindow = true;
            string paths = Path.Combine(runtime, @"runtime\win64") + ";" + Path.Combine(runtime, @"bin\win64") + ";" + Path.Combine(runtime, @"sys\os\win64");
            start.EnvironmentVariables["PATH"] = paths + ";" + start.EnvironmentVariables["PATH"];
            start.EnvironmentVariables["MCR_CACHE_ROOT"] = Path.Combine(dataRoot, "RuntimeCache");
            application = Process.Start(start);
            status.Text = "正在初始化 MATLAB 运行库和图形界面。\n首次启动可能需要一分钟左右，请稍候。";
            timer.Start();
        }
        catch (Exception exception) { Fail(exception.Message); }
    }

    private void InspectStartup(object sender, EventArgs e)
    {
        try
        {
            string report = Path.Combine(dataRoot, "startup_report.json");
            if (!interfaceReady && (mode == "--gui" || mode == "--launcher-check") && File.Exists(report) && File.GetLastWriteTimeUtc(report) >= launchTime.AddSeconds(-1))
            {
                string contents = File.ReadAllText(report);
                if (Regex.IsMatch(contents, "\"phase\"\\s*:\\s*\"ready\""))
                {
                    interfaceReady = true; Hide(); return;
                }
                if (Regex.IsMatch(contents, "\"phase\"\\s*:\\s*\"failed\""))
                {
                    Fail("软件初始化失败，请查看诊断文件：\n" + report); return;
                }
            }
            if (application.HasExited)
            {
                int code = application.ExitCode;
                if (code == 0 && (mode != "--gui" || interfaceReady)) { timer.Stop(); Close(); }
                else Fail("程序启动结束，退出码为 " + code + "。\n诊断目录：" + dataRoot);
            }
        }
        catch (IOException) { }
        catch (Exception exception) { Fail(exception.Message); }
    }

    private void Fail(string message)
    {
        timer.Stop(); Outcome = 1;
        MessageBox.Show(message, "RobotTrajectoryLab 启动提示", MessageBoxButtons.OK, MessageBoxIcon.Error);
        Close();
    }
}

internal static class Program
{
    [STAThread]
    private static int Main(string[] args)
    {
        Application.EnableVisualStyles();
        Application.SetCompatibleTextRenderingDefault(false);
        using (var window = new StartupWindow(args))
        {
            Application.Run(window);
            return window.Outcome;
        }
    }
}
