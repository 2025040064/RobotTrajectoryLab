using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.Text;
using System.Windows.Forms;
using Microsoft.Win32;

[assembly: System.Reflection.AssemblyTitle("RobotTrajectoryLab Uninstaller")]
[assembly: System.Reflection.AssemblyVersion("1.0.1.0")]
[assembly: System.Reflection.AssemblyFileVersion("1.0.1.0")]

internal sealed class UninstallTarget
{
    internal string Name;
    internal string Location;
    internal string Command;

    internal ProcessStartInfo GetStartInfo()
    {
        ProcessStartInfo start = ParseCommand(Command);
        if (!Path.IsPathRooted(start.FileName) || !File.Exists(start.FileName))
            throw new FileNotFoundException("未找到官方卸载器，请使用 Windows 的“已安装的应用”检查安装状态。", start.FileName);
        start.WorkingDirectory = Path.GetDirectoryName(start.FileName);
        start.UseShellExecute = true;
        return start;
    }

    internal static ProcessStartInfo ParseCommand(string command)
    {
        if (String.IsNullOrWhiteSpace(command))
            throw new ArgumentException("安装记录中没有卸载命令。");
        string value = Environment.ExpandEnvironmentVariables(command).Trim();
        string executable;
        string arguments;
        if (value[0] == '"')
        {
            int end = value.IndexOf('"', 1);
            if (end < 0) throw new ArgumentException("卸载命令中的引号不完整。");
            executable = value.Substring(1, end - 1);
            arguments = value.Substring(end + 1).Trim();
        }
        else
        {
            int end = value.IndexOf(".exe", StringComparison.OrdinalIgnoreCase);
            while (end >= 0 && end + 4 < value.Length && !Char.IsWhiteSpace(value[end + 4]))
                end = value.IndexOf(".exe", end + 4, StringComparison.OrdinalIgnoreCase);
            if (end < 0) throw new ArgumentException("无法识别官方卸载器的路径。");
            executable = value.Substring(0, end + 4);
            arguments = value.Substring(end + 4).Trim();
        }
        return new ProcessStartInfo(executable, arguments);
    }
}

internal static class InstalledProducts
{
    internal static List<UninstallTarget> Find()
    {
        var targets = new List<UninstallTarget>();
        var seen = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        foreach (RegistryHive hive in new[] { RegistryHive.CurrentUser, RegistryHive.LocalMachine })
        foreach (RegistryView view in new[] { RegistryView.Registry64, RegistryView.Registry32 })
        {
            try
            {
                using (RegistryKey root = RegistryKey.OpenBaseKey(hive, view))
                using (RegistryKey entries = root.OpenSubKey(@"SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall"))
                {
                    if (entries == null) continue;
                    foreach (string keyName in entries.GetSubKeyNames())
                    {
                        using (RegistryKey entry = entries.OpenSubKey(keyName))
                        {
                            if (entry == null) continue;
                            string name = entry.GetValue("DisplayName") as string;
                            if (!String.Equals(name, "RobotTrajectoryLab", StringComparison.OrdinalIgnoreCase)
                                && !String.Equals(name, "MATLAB Runtime R2025a", StringComparison.OrdinalIgnoreCase)) continue;
                            string command = entry.GetValue("UninstallString") as string;
                            if (!seen.Add(name + "\n" + command)) continue;
                            targets.Add(new UninstallTarget { Name = name, Command = command,
                                Location = entry.GetValue("InstallLocation") as string });
                        }
                    }
                }
            }
            catch (System.Security.SecurityException) { }
            catch (UnauthorizedAccessException) { }
        }
        return targets;
    }
}

internal sealed class UninstallWindow : Form
{
    private readonly Label status;

    internal UninstallWindow(List<UninstallTarget> targets)
    {
        Text = "RobotTrajectoryLab 卸载";
        ClientSize = new Size(640, 410);
        StartPosition = FormStartPosition.CenterScreen;
        FormBorderStyle = FormBorderStyle.FixedDialog;
        MaximizeBox = false;
        AutoScaleMode = AutoScaleMode.Dpi;
        Font = new Font("Microsoft YaHei UI", 10);
        BackColor = Color.FromArgb(245, 247, 250);
        Controls.Add(new Label { Text = "选择要卸载的内容", Location = new Point(24, 20),
            Size = new Size(590, 36), Font = new Font(Font.FontFamily, 17, FontStyle.Bold) });
        AddTarget(targets, "RobotTrajectoryLab", "卸载软件", 76,
            "打开官方卸载向导；本入口不会删除你的实验数据。");
        AddTarget(targets, "MATLAB Runtime R2025a", "卸载运行库", 196,
            "运行库占用主要磁盘空间；其他依赖它的软件也将无法运行。");
        status = new Label { Text = "点击后打开官方向导，按向导完成卸载。", Location = new Point(24, 320),
            Size = new Size(590, 38), ForeColor = Color.FromArgb(60, 70, 80) };
        var settings = new Button { Text = "Windows 已安装的应用", Location = new Point(24, 365), Size = new Size(225, 30) };
        settings.Click += delegate
        {
            try { Process.Start(new ProcessStartInfo("ms-settings:appsfeatures") { UseShellExecute = true }); }
            catch (Exception exception) { ShowError(exception.Message); }
        };
        var close = new Button { Text = "关闭", Location = new Point(516, 365), Size = new Size(100, 30) };
        close.Click += delegate { Close(); };
        Controls.AddRange(new Control[] { status, settings, close });
    }

    private void AddTarget(List<UninstallTarget> targets, string name, string action, int top, string description)
    {
        UninstallTarget selected = targets.Find(delegate(UninstallTarget target) { return String.Equals(target.Name, name, StringComparison.OrdinalIgnoreCase); });
        string location = selected == null ? "未检测到安装记录" : selected.Location;
        if (selected != null && String.IsNullOrWhiteSpace(location)) location = "已检测到安装记录";
        Controls.Add(new Label { Text = name, Location = new Point(24, top), Size = new Size(435, 25),
            Font = new Font(Font.FontFamily, 11, FontStyle.Bold) });
        Controls.Add(new Label { Text = location, Location = new Point(24, top + 29), Size = new Size(590, 25), AutoEllipsis = true });
        Controls.Add(new Label { Text = description, Location = new Point(24, top + 58), Size = new Size(590, 40) });
        var button = new Button { Text = action, Enabled = selected != null, Location = new Point(496, top - 2), Size = new Size(120, 32) };
        button.Click += delegate
        {
            try
            {
                ProcessStartInfo start = selected.GetStartInfo();
                if (name == "MATLAB Runtime R2025a" && MessageBox.Show(this,
                    "卸载运行库后，RobotTrajectoryLab 及其他依赖 R2025a 运行库的软件将无法运行。\n确定打开运行库卸载向导吗？",
                    "卸载 MATLAB Runtime", MessageBoxButtons.OKCancel, MessageBoxIcon.Question) != DialogResult.OK) return;
                Process.Start(start);
                status.Text = "已打开 " + name + " 官方卸载向导；请在向导内确认结果。";
            }
            catch (Exception exception) { ShowError(exception.Message); }
        };
        Controls.Add(button);
    }

    private void ShowError(string message)
    {
        MessageBox.Show(this, message, "无法打开卸载向导", MessageBoxButtons.OK, MessageBoxIcon.Error);
    }
}

internal static class Program
{
    [STAThread]
    private static int Main(string[] args)
    {
        Application.EnableVisualStyles();
        Application.SetCompatibleTextRenderingDefault(false);
        try
        {
            List<UninstallTarget> targets = InstalledProducts.Find();
            if (args.Length == 3 && args[0] == "--selftest")
            {
                VerifyCommandParsing();
                var report = new StringBuilder("COMMAND_PARSING_OK\r\n");
                foreach (UninstallTarget target in targets)
                {
                    ProcessStartInfo start = target.GetStartInfo();
                    report.AppendLine("FOUND=" + target.Name);
                    report.AppendLine("EXECUTABLE=" + start.FileName);
                    report.AppendLine("ARGUMENTS=" + start.Arguments);
                    report.AppendLine("OFFICIAL_UNINSTALLER_EXISTS=True");
                }
                using (var form = new UninstallWindow(targets))
                {
                    form.Show();
                    Application.DoEvents();
                    using (var bitmap = new Bitmap(form.Width, form.Height))
                    {
                        form.DrawToBitmap(bitmap, new Rectangle(0, 0, form.Width, form.Height));
                        bitmap.Save(Path.GetFullPath(args[2]), System.Drawing.Imaging.ImageFormat.Png);
                    }
                    form.Close();
                }
                report.AppendLine("GUI_RENDER_OK");
                report.AppendLine("NO_UNINSTALLER_LAUNCHED=True");
                File.WriteAllText(Path.GetFullPath(args[1]), report.ToString(), new UTF8Encoding(false));
                return 0;
            }
            if (args.Length != 0) throw new ArgumentException("Unsupported arguments");
            Application.Run(new UninstallWindow(targets));
            return 0;
        }
        catch (Exception exception)
        {
            if (args.Length > 0) return 1;
            MessageBox.Show(exception.Message, "RobotTrajectoryLab 卸载", MessageBoxButtons.OK, MessageBoxIcon.Error);
            return 1;
        }
    }

    private static void VerifyCommandParsing()
    {
        CheckCommand("\"C:\\Program Files\\App\\Uninstall.exe\" /interactive", @"C:\Program Files\App\Uninstall.exe", "/interactive");
        CheckCommand(@"E:\tool\uninstall\bin\win64\Uninstall_Application.exe", @"E:\tool\uninstall\bin\win64\Uninstall_Application.exe", "");
        CheckCommand(@"C:\Program Files\MATLAB\MATLAB Runtime\R2025a\bin\win64\Uninstall_MATLAB_Runtime.exe", @"C:\Program Files\MATLAB\MATLAB Runtime\R2025a\bin\win64\Uninstall_MATLAB_Runtime.exe", "");
        CheckCommand(@"C:\example.exe.folder\remove.exe /test", @"C:\example.exe.folder\remove.exe", "/test");
        bool rejected = false;
        try { UninstallTarget.ParseCommand("\"incomplete.exe"); }
        catch (ArgumentException) { rejected = true; }
        if (!rejected) throw new InvalidOperationException("Malformed command accepted");
    }

    private static void CheckCommand(string command, string executable, string arguments)
    {
        ProcessStartInfo start = UninstallTarget.ParseCommand(command);
        if (start.FileName != executable || start.Arguments != arguments)
            throw new InvalidOperationException("Uninstall command parsing failed");
    }
}
