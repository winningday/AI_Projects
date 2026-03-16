using System.Windows;
using System.Windows.Media;
using System.Windows.Shapes;
using System.Windows.Threading;
using Verbalize.Services;

namespace Verbalize.Views;

public partial class RecordingOverlay : Window
{
    private readonly AppState _appState = AppState.Instance;
    private readonly DispatcherTimer _updateTimer;
    private int _dotCount;

    public RecordingOverlay()
    {
        InitializeComponent();

        // Position at top-center of primary screen
        var screen = SystemParameters.WorkArea;
        Left = (screen.Width - Width) / 2;
        Top = 40;

        _updateTimer = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(50) };
        _updateTimer.Tick += UpdateUI;

        IsVisibleChanged += (_, e) =>
        {
            if ((bool)e.NewValue)
                _updateTimer.Start();
            else
                _updateTimer.Stop();
        };
    }

    private void UpdateUI(object? sender, EventArgs e)
    {
        // Duration
        DurationText.Text = $"{_appState.AudioRecorder.Duration:F1}s";

        // Animated dots
        _dotCount = (_dotCount + 1) % 60;
        DotsText.Text = new string('.', (_dotCount / 15) + 1);

        // Waveform
        RenderWaveform();
    }

    private void RenderWaveform()
    {
        WaveformCanvas.Children.Clear();

        var levels = _appState.AudioRecorder.LevelHistory;
        if (levels.Length == 0) return;

        double canvasWidth = WaveformCanvas.ActualWidth;
        if (canvasWidth <= 0) canvasWidth = 280;
        double canvasHeight = 36;
        int barCount = 30;
        double barWidth = canvasWidth / barCount - 2;

        for (int i = 0; i < barCount; i++)
        {
            int levelIdx = levels.Length > barCount
                ? levels.Length - barCount + i
                : i;

            float level = levelIdx >= 0 && levelIdx < levels.Length ? levels[levelIdx] : 0;
            double barHeight = Math.Max(3, level * canvasHeight);

            var bar = new Rectangle
            {
                Width = Math.Max(barWidth, 2),
                Height = barHeight,
                RadiusX = 1.5,
                RadiusY = 1.5,
                Fill = GetBarBrush(level)
            };

            Canvas.SetLeft(bar, i * (barWidth + 2));
            Canvas.SetTop(bar, canvasHeight - barHeight);
            WaveformCanvas.Children.Add(bar);
        }
    }

    private static Brush GetBarBrush(float level)
    {
        if (level > 0.8f) return new SolidColorBrush(Color.FromRgb(239, 68, 68));   // Red
        if (level > 0.6f) return new SolidColorBrush(Color.FromRgb(249, 115, 22));  // Orange
        if (level > 0.4f) return new SolidColorBrush(Color.FromRgb(245, 158, 11));  // Yellow
        return new SolidColorBrush(Color.FromRgb(34, 197, 94));                      // Green
    }

    protected override void OnKeyDown(System.Windows.Input.KeyEventArgs e)
    {
        if (e.Key == System.Windows.Input.Key.Escape)
        {
            _appState.CancelRecording();
        }
        base.OnKeyDown(e);
    }
}
