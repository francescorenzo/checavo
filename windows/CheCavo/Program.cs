using System.Windows;

namespace CheCavo.App;

static class Program
{
    [STAThread]
    static void Main()
    {
        // Fluent theme that follows Windows' light or dark setting, like the Mac app follows macOS.
        var app = new Application { ThemeMode = ThemeMode.System };
        app.Run(new MainWindow());
    }
}
