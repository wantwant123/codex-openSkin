using System;
using System.Collections.Generic;
using SystemIcons = System.Drawing.SystemIcons;
using System.IO;
using System.Linq;
using System.Threading;
using System.Windows;
using System.Windows.Threading;
using Forms = System.Windows.Forms;

namespace OpenSkin
{
    internal sealed class Program : IDisposable
    {
        readonly Forms.NotifyIcon tray = new Forms.NotifyIcon();
        readonly DispatcherTimer timer = new DispatcherTimer();
        readonly Dictionary<IntPtr,int> seen = new Dictionary<IntPtr,int>();
        readonly string settings = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "CodexOpenSkin", "settings.txt");
        bool auto = true, ambient;
        DateTime replayUntil, pruneAt;
        IntPtr target;
        int targetPid;
        Playback playback;
        bool fullFilmPending;
        internal readonly Forms.ToolStripMenuItem ReplayItem = new Forms.ToolStripMenuItem("在 Codex 上播放开屏");
        internal readonly Forms.ToolStripMenuItem PreviewItem = new Forms.ToolStripMenuItem("在 Codex 上播放完整影片");

        [STAThread] static int Main(string[] args)
        {
            if (args.Length == 3 && args[0] == "--self-test") return SmokeTest.Run(args[1], args[2]);
            using (var mutex = new Mutex(true, @"Local\CodexOpenSkin", out bool first)) {
                if (!first) return 0;
                var app = new Application { ShutdownMode = ShutdownMode.OnExplicitShutdown };
                foreach (var name in new[] { "intro.mp4", "loop.mp4", "full_preview.mp4", "poster.jpg" })
                    if (!File.Exists(Playback.Asset(name))) {
                        MessageBox.Show("请先完整解压下载包。缺少 " + name, "Codex OpenSkin");
                        return 1;
                    }
                using (var host = new Program()) return app.Run();
            }
        }

        internal Program()
        {
            if (File.Exists(settings)) {
                try {
                    var flags = File.ReadAllLines(settings);
                    auto = !flags.Contains("auto=off"); ambient = flags.Contains("ambient=on");
                } catch (IOException) {} catch (UnauthorizedAccessException) {}
            }
            var menu = new Forms.ContextMenuStrip();
            var enabled = new Forms.ToolStripMenuItem("自动播放开屏") { Checked = auto, CheckOnClick = true };
            enabled.Click += (s,e) => { auto = enabled.Checked; if (!auto) Stop(); Save(); };
            var loop = new Forms.ToolStripMenuItem("开屏后保留动态背景") { Checked = ambient, CheckOnClick = true };
            loop.Click += (s,e) => { ambient = loop.Checked; Stop(); Save(); };
            menu.Items.Add(enabled); menu.Items.Add(loop);
            ReplayItem.Click += (s,e) => RequestPlayback(false);
            PreviewItem.Click += (s,e) => RequestPlayback(true);
            menu.Items.Add(ReplayItem); menu.Items.Add(PreviewItem);
            menu.Items.Add("立即关闭动画", null, (s,e) => Stop());
            menu.Items.Add("退出", null, (s,e) => Application.Current.Shutdown());
            tray.ContextMenuStrip = menu; tray.Icon = SystemIcons.Application;
            tray.Text = "Codex · 翡翠觉醒"; tray.Visible = true;
            tray.DoubleClick += (s,e) => ReplayItem.PerformClick();
            timer.Interval = TimeSpan.FromMilliseconds(200);
            timer.Tick += (s,e) => Tick(); timer.Start();
        }

        void Save()
        {
            try {
                Directory.CreateDirectory(Path.GetDirectoryName(settings));
                File.WriteAllLines(settings, new[] { auto ? "auto=on" : "auto=off", ambient ? "ambient=on" : "ambient=off" });
            } catch (Exception e) when (e is IOException || e is UnauthorizedAccessException) { Notify("无法保存设置。"); }
        }

        void Notify(string message) => tray.ShowBalloonTip(3500, "Codex · 翡翠觉醒", message, Forms.ToolTipIcon.Info);

        void Tick()
        {
            var foreground = DesktopWindow.GetForegroundWindow();
            if (DateTime.UtcNow >= pruneAt) {
                foreach (var item in seen.ToArray())
                    if (!DesktopWindow.IsWindow(item.Key) || DesktopWindow.ProcessId(item.Key) != item.Value) seen.Remove(item.Key);
                pruneAt = DateTime.UtcNow.AddSeconds(2);
            }
            if (replayUntil != DateTime.MinValue && DateTime.UtcNow >= replayUntil) {
                Stop(); Notify("未找到前台 Codex 桌面窗口。打开 Codex 后可从托盘重播。");
            }
            if (playback != null) {
                if (!DesktopWindow.IsWindow(target) || DesktopWindow.ProcessId(target) != targetPid) { Stop(); return; }
                if (foreground == target || !DesktopWindow.IsCodex(foreground, DesktopWindow.ProcessId(foreground))) {
                    playback.Update(target, foreground == target);
                    return;
                }
                Stop();
            }
            bool manual = DateTime.UtcNow < replayUntil;
            if ((!auto && !manual) || foreground == IntPtr.Zero) return;
            int pid = DesktopWindow.ProcessId(foreground);
            if ((!manual && seen.TryGetValue(foreground, out var previous) && previous == pid) ||
                !DesktopWindow.IsCodex(foreground, pid)) return;
            seen[foreground] = pid; target = foreground; targetPid = pid;
            replayUntil = DateTime.MinValue;
            playback = new Playback(target, manual && fullFilmPending, ambient, Stop, message => { Stop(); Notify(message); });
            timer.Interval = TimeSpan.FromMilliseconds(33);
            playback.Update(target, true);
        }

        void Stop()
        {
            replayUntil = DateTime.MinValue;
            playback?.Dispose(); playback = null;
            timer.Interval = TimeSpan.FromMilliseconds(200);
        }

        void RequestPlayback(bool fullFilm)
        {
            Stop();
            fullFilmPending = fullFilm;
            replayUntil = DateTime.UtcNow.AddSeconds(15);
            var window = DesktopWindow.FindCodex();
            if (window != IntPtr.Zero) {
                if (DesktopWindow.IsIconic(window)) DesktopWindow.ShowWindowAsync(window, 9);
                DesktopWindow.SetForegroundWindow(window);
            }
            if (window == IntPtr.Zero || DesktopWindow.GetForegroundWindow() != window)
                Notify("请打开或切回 Codex 桌面窗口，动画会在其中播放。");
            Tick();
        }

        public void Dispose()
        {
            timer.Stop(); Stop(); tray.Visible = false; tray.ContextMenuStrip.Dispose(); tray.Dispose();
        }
    }
}
