// Module: Audio recording using NAudio — captures microphone input, monitors levels, saves to WAV
using NAudio.Wave;
using System.ComponentModel;
using System.Runtime.CompilerServices;

namespace Verbalize.Services;

public class AudioRecorder : INotifyPropertyChanged, IDisposable
{
    private WaveInEvent? _waveIn;
    private WaveFileWriter? _writer;
    private string? _tempFilePath;
    private DateTime _recordingStartTime;
    private System.Timers.Timer? _durationTimer;
    private readonly List<float> _levelHistory = new(50);
    private readonly object _lock = new();

    private float _audioLevel;
    public float AudioLevel
    {
        get => _audioLevel;
        private set { _audioLevel = value; OnPropertyChanged(); }
    }

    private double _duration;
    public double Duration
    {
        get => _duration;
        private set { _duration = value; OnPropertyChanged(); }
    }

    private bool _isRecording;
    public bool IsRecording
    {
        get => _isRecording;
        private set { _isRecording = value; OnPropertyChanged(); }
    }

    public float[] LevelHistory
    {
        get
        {
            lock (_lock)
            {
                return _levelHistory.ToArray();
            }
        }
    }

    public event PropertyChangedEventHandler? PropertyChanged;

    public void StartRecording()
    {
        if (IsRecording) return;

        _tempFilePath = Path.Combine(Path.GetTempPath(), $"verbalize_{Guid.NewGuid()}.wav");

        // 16kHz mono — Whisper-compatible format
        var waveFormat = new WaveFormat(16000, 16, 1);

        _waveIn = new WaveInEvent
        {
            WaveFormat = waveFormat,
            BufferMilliseconds = 50
        };

        _writer = new WaveFileWriter(_tempFilePath, waveFormat);

        _waveIn.DataAvailable += OnDataAvailable;
        _waveIn.RecordingStopped += OnRecordingStopped;

        _recordingStartTime = DateTime.UtcNow;
        Duration = 0;

        _durationTimer = new System.Timers.Timer(50);
        _durationTimer.Elapsed += (_, _) =>
        {
            Duration = (DateTime.UtcNow - _recordingStartTime).TotalSeconds;
        };
        _durationTimer.Start();

        _waveIn.StartRecording();
        IsRecording = true;

        lock (_lock)
        {
            _levelHistory.Clear();
        }
    }

    public (string filePath, double duration) StopRecording()
    {
        if (!IsRecording || _waveIn == null)
            return (string.Empty, 0);

        _durationTimer?.Stop();
        _durationTimer?.Dispose();
        _durationTimer = null;

        _waveIn.StopRecording();
        IsRecording = false;

        var duration = (DateTime.UtcNow - _recordingStartTime).TotalSeconds;
        var filePath = _tempFilePath ?? string.Empty;

        return (filePath, duration);
    }

    private void OnDataAvailable(object? sender, WaveInEventArgs e)
    {
        _writer?.Write(e.Buffer, 0, e.BytesRecorded);

        // Calculate RMS audio level
        float max = 0;
        for (int i = 0; i < e.BytesRecorded; i += 2)
        {
            short sample = (short)(e.Buffer[i] | (e.Buffer[i + 1] << 8));
            float sampleFloat = Math.Abs(sample / 32768f);
            if (sampleFloat > max) max = sampleFloat;
        }

        // Normalize to 0-1 range with some smoothing
        float level = Math.Min(1.0f, max * 2.0f);
        AudioLevel = AudioLevel * 0.3f + level * 0.7f;

        lock (_lock)
        {
            _levelHistory.Add(AudioLevel);
            if (_levelHistory.Count > 50)
                _levelHistory.RemoveAt(0);
        }
    }

    private void OnRecordingStopped(object? sender, StoppedEventArgs e)
    {
        _writer?.Dispose();
        _writer = null;

        _waveIn?.Dispose();
        _waveIn = null;
    }

    public void CleanupTempFile(string filePath)
    {
        try
        {
            if (File.Exists(filePath))
                File.Delete(filePath);
        }
        catch { /* ignore cleanup failures */ }
    }

    public void Dispose()
    {
        _durationTimer?.Dispose();
        _writer?.Dispose();
        _waveIn?.Dispose();
    }

    private void OnPropertyChanged([CallerMemberName] string? name = null)
        => PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(name));
}
