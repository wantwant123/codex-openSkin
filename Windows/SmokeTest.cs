using System;
using System.IO;
using System.Linq;
using System.Windows.Controls;
using System.Windows;
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

        static void CheckPlayback(Application app, IntPtr target)
        {
            string failure = null;
            using (var session = new Playback(false, () => {}, message => failure = message)) {
                session.Update(target, true);
                var film = app.Windows.Cast<Window>().Single(w => w.Content is Grid);
                var player = ((Grid)film.Content).Children.OfType<MediaElement>().Single();
                Check(film.IsVisible, "Playback overlay shown");
                for (int i = 0; i < 100 && failure == null && player.Position.TotalMilliseconds < 160; i++) Pump(100);
                Check(failure == null, failure);
                Check(player.NaturalVideoWidth > 0 && player.Position.TotalMilliseconds >= 160, "Intro playback did not advance");
                session.Update(target, false);
                Pump(150);
                var paused = player.Position;
                Pump(250);
                Check(!film.IsVisible && Math.Abs((player.Position-paused).TotalMilliseconds) < 100, "Playback hides and pauses");
                session.Update(target, true);
                for (int i = 0; i < 25 && player.Position <= paused; i++) Pump(100);
                Check(film.IsVisible && player.Position > paused, "Playback resumes");
            }
        }

        internal static int Run(string report)
        {
            try {
                var app = new Application { ShutdownMode = ShutdownMode.OnExplicitShutdown };
                foreach (var name in new[] { "intro.mp4", "loop.mp4", "full_preview.mp4", "poster.jpg" })
                    Check(new FileInfo(Playback.Asset(name)).Length > 0, "Missing " + name);
                var fixture = new Window { Width = 480, Height = 360, ShowInTaskbar = false, WindowStyle = WindowStyle.None };
                fixture.Show();
                var handle = new WindowInteropHelper(fixture).Handle;
                var probe = new Window { WindowStyle = WindowStyle.None, ShowActivated = false, AllowsTransparency = true };
                var overlay = DesktopWindow.Configure(probe, true);
                probe.Show();
                Check(DesktopWindow.ProcessId(handle) == System.Diagnostics.Process.GetCurrentProcess().Id, "Owner PID");
                Check(!DesktopWindow.IsCodex(handle, DesktopWindow.ProcessId(handle)), "Reject unrelated window");
                Check((DesktopWindow.GetWindowLong(overlay,-20) & DesktopWindow.ClickThroughStyle) ==
                    DesktopWindow.ClickThroughStyle, "Nonactivating click-through style");
                foreach (var x in new[] { 50, 160 }) {
                    var bounds = new DesktopWindow.Rect { Left=x, Top=x, Right=x+500, Bottom=x+330 };
                    Check(DesktopWindow.Place(handle, bounds), "Fixture move");
                    Check(DesktopWindow.TryBounds(handle, out var target), "Read target bounds");
                    Check(DesktopWindow.Place(overlay, target), "Move overlay");
                    Check(DesktopWindow.TryBounds(overlay, out var actual) && actual.Equals(target), "Follow bounds");
                }
                fixture.WindowState = WindowState.Minimized;
                Check(DesktopWindow.IsIconic(handle), "Detect minimized window");
                probe.Close();
                fixture.WindowState = WindowState.Normal;
                CheckPlayback(app, handle);
                fixture.Close();
                Check(!DesktopWindow.IsWindow(handle), "Detect closed window");
                File.WriteAllText(report, "PASS: packaged media, PID, target filtering, click-through, native move/resize, minimize, close, playback overlay hide/restore and film progression.");
                return 0;
            } catch (Exception error) { File.WriteAllText(report, error.ToString()); return 1; }
        }
    }
}
