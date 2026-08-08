using System.Windows;
using System.Windows.Threading;

namespace VoiceKey.App;

public partial class App : Application
{
    private AppController? _controller;

    protected override void OnStartup(StartupEventArgs e)
    {
        base.OnStartup(e);
        DispatcherUnhandledException += OnUnhandledException;
        _controller = new AppController();
        _controller.Start();
    }

    /// <summary>
    /// A failure in one dictation must not take the tray icon with it — and for a
    /// background app the log is the only place it can be reported.
    /// </summary>
    private static void OnUnhandledException(object sender, DispatcherUnhandledExceptionEventArgs e)
    {
        Log.Line($"unhandled: {e.Exception}");
        e.Handled = true;
    }

    protected override void OnExit(ExitEventArgs e)
    {
        _controller?.Dispose();
        base.OnExit(e);
    }
}
