// Module: System tray integration — provides tray icon with context menu and status
using System.Drawing;
using System.Windows;
using System.Windows.Forms;
using Verbalize.Services;
using Application = System.Windows.Application;
using ContextMenuStrip = System.Windows.Forms.ContextMenuStrip;

namespace Verbalize.Views;

public class SystemTrayManager : IDisposable
{
    private readonly NotifyIcon _notifyIcon;
    private readonly AppState _appState = AppState.Instance;
    private readonly ContextMenuStrip _contextMenu;

    public SystemTrayManager()
    {
        _contextMenu = new ContextMenuStrip();
        BuildContextMenu();

        _notifyIcon = new NotifyIcon
        {
            Text = "Verbalize - Ready",
            Visible = true,
            ContextMenuStrip = _contextMenu
        };

        // Use a simple generated icon since we don't have an .ico file yet
        _notifyIcon.Icon = CreateDefaultIcon();

        _notifyIcon.DoubleClick += (_, _) => ShowMainWindow();

        // Update tray icon state on status changes
        _appState.PropertyChanged += (_, e) =>
        {
            if (e.PropertyName == nameof(AppState.Status))
            {
                Application.Current.Dispatcher.Invoke(UpdateTrayStatus);
            }
        };
    }

    private void BuildContextMenu()
    {
        _contextMenu.Items.Clear();

        var statusItem = new ToolStripMenuItem("Verbalize - Ready") { Enabled = false };
        _contextMenu.Items.Add(statusItem);
        _contextMenu.Items.Add(new ToolStripSeparator());

        var hotkeyItem = new ToolStripMenuItem($"Hotkey: {_appState.HotKeyManager.HotkeyDescription}") { Enabled = false };
        _contextMenu.Items.Add(hotkeyItem);
        _contextMenu.Items.Add(new ToolStripSeparator());

        // Translation toggle
        var translationItem = new ToolStripMenuItem("Translation")
        {
            Checked = _appState.Config.TranslationEnabled
        };
        translationItem.Click += (_, _) =>
        {
            _appState.Config.TranslationEnabled = !_appState.Config.TranslationEnabled;
            translationItem.Checked = _appState.Config.TranslationEnabled;
        };
        _contextMenu.Items.Add(translationItem);
        _contextMenu.Items.Add(new ToolStripSeparator());

        // Last transcript
        if (!string.IsNullOrEmpty(_appState.LastTranscript))
        {
            var lastText = _appState.LastTranscript.Length > 60
                ? _appState.LastTranscript[..60] + "..."
                : _appState.LastTranscript;
            var lastItem = new ToolStripMenuItem($"Last: {lastText}") { Enabled = false };
            _contextMenu.Items.Add(lastItem);
            _contextMenu.Items.Add(new ToolStripSeparator());
        }

        var openItem = new ToolStripMenuItem("Open Verbalize");
        openItem.Click += (_, _) => ShowMainWindow();
        _contextMenu.Items.Add(openItem);

        var quitItem = new ToolStripMenuItem("Quit");
        quitItem.Click += (_, _) =>
        {
            _notifyIcon.Visible = false;
            Application.Current.Shutdown();
        };
        _contextMenu.Items.Add(quitItem);
    }

    private void UpdateTrayStatus()
    {
        _notifyIcon.Text = _appState.Status switch
        {
            AppStatus.Recording => "Verbalize - Recording...",
            AppStatus.Processing => "Verbalize - Processing...",
            AppStatus.Error => "Verbalize - Error",
            _ => "Verbalize - Ready"
        };

        // Rebuild menu to show latest transcript
        BuildContextMenu();
    }

    private void ShowMainWindow()
    {
        var mainWindow = Application.Current.MainWindow;
        if (mainWindow != null)
        {
            mainWindow.Show();
            mainWindow.WindowState = WindowState.Normal;
            mainWindow.Activate();
        }
    }

    private static Icon CreateDefaultIcon()
    {
        // Create a simple 16x16 icon programmatically
        var bitmap = new Bitmap(16, 16);
        using (var g = Graphics.FromImage(bitmap))
        {
            g.Clear(Color.FromArgb(99, 102, 241)); // Primary purple
            g.FillRectangle(new SolidBrush(Color.White), 3, 4, 2, 8);
            g.FillRectangle(new SolidBrush(Color.White), 6, 2, 2, 12);
            g.FillRectangle(new SolidBrush(Color.White), 9, 5, 2, 6);
            g.FillRectangle(new SolidBrush(Color.White), 12, 3, 2, 10);
        }
        return Icon.FromHandle(bitmap.GetHicon());
    }

    public void Dispose()
    {
        _notifyIcon.Visible = false;
        _notifyIcon.Dispose();
        _contextMenu.Dispose();
    }
}
