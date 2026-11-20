using System;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Text;
using System.Windows;
using System.Windows.Interop;

namespace OpenSkin
{
    internal static class DesktopWindow
    {
        [StructLayout(LayoutKind.Sequential)]
        internal struct Rect { public int Left, Top, Right, Bottom; }

        [DllImport("user32.dll")] internal static extern IntPtr GetForegroundWindow();
        [DllImport("user32.dll")] internal static extern bool IsWindow(IntPtr handle);
        [DllImport("user32.dll")] internal static extern bool IsWindowVisible(IntPtr handle);
        [DllImport("user32.dll")] internal static extern bool IsIconic(IntPtr handle);
        [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr handle, out int pid);
        [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern int GetClassName(IntPtr handle, StringBuilder name, int length);
        [DllImport("user32.dll")] static extern bool GetWindowRect(IntPtr handle, out Rect rect);
        [DllImport("dwmapi.dll")] static extern int DwmGetWindowAttribute(IntPtr handle, int attribute, out Rect rect, int size);
        [DllImport("user32.dll", EntryPoint="GetWindowLongW")] internal static extern int GetWindowLong(IntPtr handle, int index);
        [DllImport("user32.dll", EntryPoint="SetWindowLongW")] static extern int SetWindowLong(IntPtr handle, int index, int value);
        [DllImport("user32.dll")] static extern bool SetWindowPos(IntPtr handle, IntPtr after, int x, int y, int width, int height, uint flags);
        [DllImport("user32.dll")] internal static extern uint GetDpiForWindow(IntPtr handle);

        internal static int ProcessId(IntPtr window)
        {
            GetWindowThreadProcessId(window, out int pid);
            return pid;
        }

        internal static bool TryBounds(IntPtr handle, out Rect rect)
        {
            if (DwmGetWindowAttribute(handle, 9, out rect, Marshal.SizeOf(typeof(Rect))) != 0 &&
                !GetWindowRect(handle, out rect)) return false;
            return rect.Right > rect.Left && rect.Bottom > rect.Top;
        }

        internal static bool IsCodex(IntPtr handle, int pid)
        {
            if (pid == 0 || !IsWindowVisible(handle) || IsIconic(handle) ||
                (GetWindowLong(handle, -20) & 0x80) != 0) return false;
            var name = new StringBuilder(256);
            GetClassName(handle, name, name.Capacity);
            if (!name.ToString().StartsWith("Chrome_WidgetWin_", StringComparison.Ordinal)) return false;
            try
            {
                using (var proc = Process.GetProcessById(pid))
                    return proc.ProcessName.Equals("Codex", StringComparison.OrdinalIgnoreCase);
            }
            catch (ArgumentException) { return false; }
            catch (InvalidOperationException) { return false; }
            catch (System.ComponentModel.Win32Exception) { return false; }
        }

        internal const int ClickThroughStyle = 0x08000000 | 0x00000080 | 0x00080000 | 0x20;
        internal static IntPtr Configure(Window window, bool clickThrough)
        {
            var handle = new WindowInteropHelper(window).EnsureHandle();
            int extra = clickThrough ? ClickThroughStyle : 0x08000080;
            SetWindowLong(handle, -20, GetWindowLong(handle, -20) | extra);
            return handle;
        }

        internal static bool Place(IntPtr window, Rect rect)
        {
            // Physical pixels in the same per-monitor DPI context as the DWM bounds.
            return SetWindowPos(window, new IntPtr(-1), rect.Left, rect.Top,
                rect.Right - rect.Left, rect.Bottom - rect.Top, 0x0010 | 0x0200);
        }
    }
}
