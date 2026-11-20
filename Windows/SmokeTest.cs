using System;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Interop;
using System.Windows.Threading;

namespace OpenSkin
{
    internal static class SmokeTest
    {
        static void Check(bool ok, string label)
        {
            if (!ok) throw new InvalidOperationException(label);
        }

        static void Pump(int milliseconds)
        {
            var frame = new DispatcherFrame();
            var timer = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(milliseconds) };
            timer.Tick += (s,e) => { timer.Stop(); frame.Continue = false; };
            timer.Start(); Dispatcher.PushFrame(frame);
        }

        static void WaitFor(Func<bool> condition, string label)
        {
            for (int i = 0; i < 80 && !condition(); i++) Pump(100);
            Check(condition(), label);
        }

        static Window Film(Application app) => app.Windows.Cast<Window>().SingleOrDefault(w => w.Content is Grid);

        static void CheckAttached(Application app, IntPtr target)
        {
            var film = Film(app);
            var hwnd = new WindowInteropHelper(film).Handle;
            var skip = app.Windows.Cast<Window>().Single(w => w.Content is Button);
            Check(DesktopWindow.GetWindow(hwnd, 4) == target, "Film HWND must be owned by the external target");
            Check(DesktopWindow.GetWindow(new WindowInteropHelper(skip).Handle, 4) == hwnd, "Skip belongs to film");
            int styles = DesktopWindow.GetWindowLong(hwnd, -20);
            Check((styles & DesktopWindow.ClickThroughStyle) == DesktopWindow.ClickThroughStyle, "Mouse pass-through and no activation");
            Check((styles & (0x8 | 0x40000)) == 0, "No desktop-wide topmost or app window style");
            Check(DesktopWindow.GetForegroundWindow() == target, "Target keeps keyboard focus");
            WaitFor(() => DesktopWindow.TryBounds(target, out var a) && DesktopWindow.TryBounds(hwnd, out var b) &&
                a.Equals(b), "Visible overlay must match the target bounds");
        }

        static void Exercise(Application app, Process fixture)
        {
            WaitFor(() => { fixture.Refresh(); return fixture.MainWindowHandle != IntPtr.Zero; }, "Fixture did not open");
            var target = fixture.MainWindowHandle;
            Check(DesktopWindow.IsCodex(target, fixture.Id), "Detect desktop Codex without a Chromium class");
            var unrelated = new Window { Title = "Codex", Width = 270, Height = 130 };
            unrelated.Show();
            Check(!DesktopWindow.IsCodex(new WindowInteropHelper(unrelated).Handle, Process.GetCurrentProcess().Id),
                "Reject unrelated process even with Codex window title");

            using (var host = new Program()) {
                host.ReplayItem.PerformClick();
                WaitFor(() => Film(app)?.IsVisible == true, "Tray replay did not cover Codex");
                CheckAttached(app, target);
                var movie = ((Grid)Film(app).Content).Children.OfType<MediaElement>().Single();
                WaitFor(() => movie.NaturalVideoWidth > 0 && movie.Position.TotalMilliseconds > 150, "Intro did not play");
                Check(Path.GetFileName(movie.Source.LocalPath) == "intro.mp4", "Replay media");
                Check(DesktopWindow.Place(target, new DesktopWindow.Rect { Left=125, Top=105, Right=805, Bottom=525 }), "Move target");
                Pump(200);
                CheckAttached(app, target);

                unrelated.Activate();
                WaitFor(() => !Film(app).IsVisible, "Overlay must hide when switching away");
                Pump(150); var paused = movie.Position; Pump(250);
                Check(Math.Abs((movie.Position-paused).TotalMilliseconds) < 100, "Playback paused");
                DesktopWindow.SetForegroundWindow(target);
                WaitFor(() => Film(app).IsVisible && movie.Position > paused, "Playback resumes");
                DesktopWindow.ShowWindowAsync(target, 6);
                WaitFor(() => DesktopWindow.IsIconic(target) && !Film(app).IsVisible, "Hide when minimized");
                host.PreviewItem.PerformClick();
                WaitFor(() => Film(app)?.IsVisible == true, "Full film must restore and cover Codex");
                CheckAttached(app, target);
                movie = ((Grid)Film(app).Content).Children.OfType<MediaElement>().Single();
                Check(Path.GetFileName(movie.Source.LocalPath) == "full_preview.mp4", "Full film media");
                Check(app.Windows.Cast<Window>().All(w => w == unrelated || !w.ShowInTaskbar), "No separate player");
                fixture.CloseMainWindow();
                WaitFor(() => fixture.HasExited && Film(app) == null, "Owner exit must clear overlay");
                host.PreviewItem.PerformClick(); Pump(300);
                Check(Film(app) == null && app.Windows.Count == 1, "No target must not open a player");
            }
            unrelated.Close();
        }

        internal static int Run(string report, string fixturePath)
        {
            try {
                var app = new Application { ShutdownMode = ShutdownMode.OnExplicitShutdown };
                foreach (var name in new[] { "intro.mp4", "loop.mp4", "full_preview.mp4", "poster.jpg" })
                    Check(new FileInfo(Playback.Asset(name)).Length > 0, "Missing " + name);
                using (var fixture = Process.Start(fixturePath)) {
                    try { Exercise(app, fixture); }
                    finally { if (!fixture.HasExited) fixture.Kill(); }
                }
                File.WriteAllText(report, "PASS: external process detection, tray replay and full film, native ownership, bounds, focus, click-through styles, move, hide, pause/resume, minimize, owner close, missing target.");
                return 0;
            } catch (Exception error) { File.WriteAllText(report, error.ToString()); return 1; }
        }
    }
}
