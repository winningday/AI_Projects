using System.Windows;
using Verbalize.Services;
using Verbalize.Views;

namespace Verbalize;

public partial class App : Application
{
    private AppState? _appState;
    private SystemTrayManager? _trayManager;

    protected override void OnStartup(StartupEventArgs e)
    {
        base.OnStartup(e);
        _appState = AppState.Instance;
        _trayManager = new SystemTrayManager();
    }

    protected override void OnExit(ExitEventArgs e)
    {
        _trayManager?.Dispose();
        _appState?.Dispose();
        base.OnExit(e);
    }
}
