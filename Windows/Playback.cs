using System;
using System.IO;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Media.Imaging;

namespace OpenSkin
{
    internal sealed class Playback : IDisposable
    {
        internal static string Asset(string name) =>
            Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "EmeraldAwakening", name);

        readonly Window film, controls;
        readonly MediaElement player;
        readonly Image poster;
        readonly IntPtr filmHandle, controlsHandle;
        readonly bool ambient;
        readonly Action finish;
        readonly Action<string> failed;
        bool visible, looping, disposed;
        DesktopWindow.Rect? lastBounds;

        internal Playback(bool ambient, Action finish, Action<string> failed)
        {
            this.ambient = ambient;
            this.finish = finish;
            this.failed = failed;
            var scene = new Grid();
            poster = new Image { Source = new BitmapImage(new Uri(Asset("poster.jpg"))), Stretch = Stretch.UniformToFill };
            player = new MediaElement { LoadedBehavior = MediaState.Manual, UnloadedBehavior = MediaState.Manual,
                Stretch = Stretch.Uniform, IsHitTestVisible = false };
            scene.Children.Add(player);
            scene.Children.Add(poster);
            film = Panel(scene);
            film.AllowsTransparency = true;
            filmHandle = DesktopWindow.Configure(film, true);
            var skip = new Button { Content = "跳过  ›", Focusable = false, FontSize = 14,
                Foreground = Brushes.White, Background = new SolidColorBrush(Color.FromRgb(28,49,44)),
                BorderThickness = new Thickness(0) };
            skip.Click += (s,e) => finish();
            controls = Panel(skip);
            controlsHandle = DesktopWindow.Configure(controls, false);
            player.MediaOpened += (s,e) => { poster.Visibility = Visibility.Collapsed; if (visible) player.Play(); };
            player.MediaFailed += (s,e) => { if (!disposed) failed("无法播放影片：" + e.ErrorException.Message); };
            player.MediaEnded += (s,e) => {
                if (disposed) return;
                if (!ambient) { finish(); return; }
                if (!looping) {
                    looping = true; controls.Hide(); film.Opacity = 0.12;
                    player.IsMuted = true; player.Source = new Uri(Asset("loop.mp4"));
                } else player.Position = TimeSpan.Zero;
                if (visible) player.Play();
            };
            player.Source = new Uri(Asset("intro.mp4"));
        }

        static Window Panel(UIElement content) => new Window { WindowStyle = WindowStyle.None,
            ResizeMode = ResizeMode.NoResize, ShowActivated = false, ShowInTaskbar = false,
            Topmost = true, Background = Brushes.Black, Content = content, Width = 1, Height = 1 };

        internal void Update(IntPtr target, bool foreground)
        {
            if (!foreground || DesktopWindow.IsIconic(target) || !DesktopWindow.IsWindowVisible(target) ||
                !DesktopWindow.TryBounds(target, out var bounds)) {
                if (visible) { visible = false; player.Pause(); controls.Hide(); film.Hide(); lastBounds = null; }
                return;
            }
            if (!visible) {
                visible = true; film.Show();
                if (!looping) controls.Show();
                player.Play();
            }
            if (lastBounds.HasValue && lastBounds.Value.Equals(bounds)) return;
            lastBounds = bounds;
            DesktopWindow.Place(filmHandle, bounds);
            if (!looping) {
                double scale = Math.Max(96u, DesktopWindow.GetDpiForWindow(target)) / 96.0;
                int right = bounds.Right - (int)(18*scale), top = bounds.Top + (int)(18*scale);
                DesktopWindow.Place(controlsHandle, new DesktopWindow.Rect {
                    Left = right - (int)(78*scale), Right = right, Top = top, Bottom = top + (int)(32*scale) });
            }
        }

        public void Dispose()
        {
            if (disposed) return;
            disposed = true; player.Close(); controls.Close(); film.Close();
        }
    }
}
