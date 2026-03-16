// Module: Global hotkey system — low-level keyboard hook for push-to-talk
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Windows.Input;

namespace Verbalize.Services;

public class HotKeyManager : IDisposable
{
    // Win32 API imports for low-level keyboard hook
    private const int WH_KEYBOARD_LL = 13;
    private const int WM_KEYDOWN = 0x0100;
    private const int WM_KEYUP = 0x0101;
    private const int WM_SYSKEYDOWN = 0x0104;
    private const int WM_SYSKEYUP = 0x0105;

    [DllImport("user32.dll", SetLastError = true)]
    private static extern IntPtr SetWindowsHookEx(int idHook, LowLevelKeyboardProc callback, IntPtr hInstance, uint threadId);

    [DllImport("user32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool UnhookWindowsHookEx(IntPtr hhk);

    [DllImport("user32.dll")]
    private static extern IntPtr CallNextHookEx(IntPtr hhk, int nCode, IntPtr wParam, IntPtr lParam);

    [DllImport("kernel32.dll")]
    private static extern IntPtr GetModuleHandle(string? lpModuleName);

    private delegate IntPtr LowLevelKeyboardProc(int nCode, IntPtr wParam, IntPtr lParam);

    [StructLayout(LayoutKind.Sequential)]
    private struct KBDLLHOOKSTRUCT
    {
        public uint vkCode;
        public uint scanCode;
        public uint flags;
        public uint time;
        public IntPtr dwExtraInfo;
    }

    private IntPtr _hookId = IntPtr.Zero;
    private LowLevelKeyboardProc? _hookProc;
    private bool _isKeyDown;
    private bool _isCapturing;

    // Configurable hotkey — default: F8
    public Key HotKey { get; set; } = Key.F8;
    public ModifierKeys HotKeyModifiers { get; set; } = ModifierKeys.None;

    // Events
    public event Action? OnHotkeyDown;
    public event Action? OnHotkeyUp;
    public event Action<Key, ModifierKeys>? OnHotkeyCaptured;

    public string HotkeyDescription
    {
        get
        {
            var parts = new List<string>();
            if (HotKeyModifiers.HasFlag(ModifierKeys.Control)) parts.Add("Ctrl");
            if (HotKeyModifiers.HasFlag(ModifierKeys.Alt)) parts.Add("Alt");
            if (HotKeyModifiers.HasFlag(ModifierKeys.Shift)) parts.Add("Shift");
            if (HotKeyModifiers.HasFlag(ModifierKeys.Windows)) parts.Add("Win");
            parts.Add(HotKey.ToString());
            return string.Join("+", parts);
        }
    }

    public void StartListening()
    {
        if (_hookId != IntPtr.Zero) return;

        _hookProc = HookCallback;
        using var process = Process.GetCurrentProcess();
        using var module = process.MainModule!;
        _hookId = SetWindowsHookEx(WH_KEYBOARD_LL, _hookProc, GetModuleHandle(module.ModuleName), 0);

        if (_hookId == IntPtr.Zero)
        {
            throw new InvalidOperationException("Failed to install keyboard hook.");
        }
    }

    public void StopListening()
    {
        if (_hookId != IntPtr.Zero)
        {
            UnhookWindowsHookEx(_hookId);
            _hookId = IntPtr.Zero;
        }
    }

    public void StartCapturingHotkey()
    {
        _isCapturing = true;
    }

    public void CancelCapture()
    {
        _isCapturing = false;
    }

    private IntPtr HookCallback(int nCode, IntPtr wParam, IntPtr lParam)
    {
        if (nCode >= 0)
        {
            var hookStruct = Marshal.PtrToStructure<KBDLLHOOKSTRUCT>(lParam);
            var key = KeyInterop.KeyFromVirtualKey((int)hookStruct.vkCode);
            var msgType = wParam.ToInt32();

            // Capture mode — intercept next keypress for rebinding
            if (_isCapturing && (msgType == WM_KEYDOWN || msgType == WM_SYSKEYDOWN))
            {
                // Skip standalone modifier keys
                if (key != Key.LeftShift && key != Key.RightShift &&
                    key != Key.LeftCtrl && key != Key.RightCtrl &&
                    key != Key.LeftAlt && key != Key.RightAlt &&
                    key != Key.LWin && key != Key.RWin)
                {
                    _isCapturing = false;
                    var modifiers = GetCurrentModifiers();
                    OnHotkeyCaptured?.Invoke(key, modifiers);
                    return (IntPtr)1; // Swallow the key
                }
            }

            // Normal hotkey detection
            if (!_isCapturing)
            {
                var currentModifiers = GetCurrentModifiers();
                bool modifiersMatch = currentModifiers == HotKeyModifiers;
                bool keyMatches = key == HotKey;

                if (keyMatches && modifiersMatch)
                {
                    if ((msgType == WM_KEYDOWN || msgType == WM_SYSKEYDOWN) && !_isKeyDown)
                    {
                        _isKeyDown = true;
                        OnHotkeyDown?.Invoke();
                    }
                    else if ((msgType == WM_KEYUP || msgType == WM_SYSKEYUP) && _isKeyDown)
                    {
                        _isKeyDown = false;
                        OnHotkeyUp?.Invoke();
                    }
                }
            }
        }

        return CallNextHookEx(_hookId, nCode, wParam, lParam);
    }

    private static ModifierKeys GetCurrentModifiers()
    {
        var mods = ModifierKeys.None;
        if ((GetAsyncKeyState(0x10) & 0x8000) != 0) mods |= ModifierKeys.Shift;    // VK_SHIFT
        if ((GetAsyncKeyState(0x11) & 0x8000) != 0) mods |= ModifierKeys.Control;   // VK_CONTROL
        if ((GetAsyncKeyState(0x12) & 0x8000) != 0) mods |= ModifierKeys.Alt;       // VK_MENU
        return mods;
    }

    [DllImport("user32.dll")]
    private static extern short GetAsyncKeyState(int vKey);

    public void Dispose()
    {
        StopListening();
    }
}
