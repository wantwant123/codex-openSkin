using System;
using System.Drawing;
using System.Windows.Forms;

class WindowsFixture
{
    [STAThread] static void Main()
    {
        Application.Run(new Form { Text = "Window tracking fixture", FormBorderStyle = FormBorderStyle.None,
            BackColor = Color.Magenta, StartPosition = FormStartPosition.Manual, Bounds = new Rectangle(60, 70, 540, 310) });
    }
}
