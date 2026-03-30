// Module: Text injection — pastes text into active window via clipboard + Ctrl+V simulation
using System.Runtime.InteropServices;
using System.Windows;

namespace Verbalize.Services;

public static class TextInjector
{
    // Win32 SendInput for simulating Ctrl+V
    [DllImport("user32.dll", SetLastError = true)]
    private static extern uint SendInput(uint nInputs, INPUT[] pInputs, int cbSize);

    [DllImport("user32.dll")]
    private static extern IntPtr GetForegroundWindow();

    [DllImport("user32.dll")]
    private static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint processId);

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    private static extern int GetWindowText(IntPtr hWnd, System.Text.StringBuilder lpString, int nMaxCount);

    [StructLayout(LayoutKind.Sequential)]
    private struct INPUT
    {
        public uint type;
        public INPUTUNION u;
    }

    [StructLayout(LayoutKind.Explicit)]
    private struct INPUTUNION
    {
        [FieldOffset(0)] public KEYBDINPUT ki;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct KEYBDINPUT
    {
        public ushort wVk;
        public ushort wScan;
        public uint dwFlags;
        public uint time;
        public IntPtr dwExtraInfo;
    }

    private const uint INPUT_KEYBOARD = 1;
    private const uint KEYEVENTF_KEYUP = 0x0002;
    private const ushort VK_CONTROL = 0x11;
    private const ushort VK_V = 0x56;

    // Track whether we recently injected text (to add space between consecutive injections)
    private static DateTime _lastInjectionTime = DateTime.MinValue;

    public static async Task InjectTextAsync(string text)
    {
        if (string.IsNullOrEmpty(text)) return;

        // Prepend space if we recently injected text (within 30 seconds)
        // This prevents consecutive transcriptions from running together
        var textToInject = text;
        if ((DateTime.UtcNow - _lastInjectionTime).TotalSeconds < 30)
        {
            textToInject = " " + textToInject;
        }

        // Save current clipboard
        string? previousClipboard = null;
        try
        {
            if (Clipboard.ContainsText())
                previousClipboard = Clipboard.GetText();
        }
        catch { /* clipboard may be locked */ }

        // Set our text to clipboard
        Clipboard.SetText(textToInject);
        await Task.Delay(50);

        // Simulate Ctrl+V
        var inputs = new INPUT[]
        {
            // Ctrl down
            new() { type = INPUT_KEYBOARD, u = new INPUTUNION { ki = new KEYBDINPUT { wVk = VK_CONTROL } } },
            // V down
            new() { type = INPUT_KEYBOARD, u = new INPUTUNION { ki = new KEYBDINPUT { wVk = VK_V } } },
            // V up
            new() { type = INPUT_KEYBOARD, u = new INPUTUNION { ki = new KEYBDINPUT { wVk = VK_V, dwFlags = KEYEVENTF_KEYUP } } },
            // Ctrl up
            new() { type = INPUT_KEYBOARD, u = new INPUTUNION { ki = new KEYBDINPUT { wVk = VK_CONTROL, dwFlags = KEYEVENTF_KEYUP } } },
        };

        SendInput((uint)inputs.Length, inputs, Marshal.SizeOf<INPUT>());
        _lastInjectionTime = DateTime.UtcNow;

        // Restore clipboard after delay
        await Task.Delay(500);
        try
        {
            if (previousClipboard != null)
                Clipboard.SetText(previousClipboard);
        }
        catch { /* ignore restore failures */ }
    }

    public static string? GetActiveWindowTitle()
    {
        var hwnd = GetForegroundWindow();
        if (hwnd == IntPtr.Zero) return null;

        var sb = new System.Text.StringBuilder(256);
        GetWindowText(hwnd, sb, sb.Capacity);
        return sb.ToString();
    }

    public static string? GetActiveProcessName()
    {
        var hwnd = GetForegroundWindow();
        if (hwnd == IntPtr.Zero) return null;

        GetWindowThreadProcessId(hwnd, out uint processId);
        try
        {
            var process = System.Diagnostics.Process.GetProcessById((int)processId);
            return process.ProcessName;
        }
        catch
        {
            return null;
        }
    }
}
