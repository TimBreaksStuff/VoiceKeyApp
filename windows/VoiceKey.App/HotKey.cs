using System.Runtime.InteropServices;
using System.Windows.Interop;

namespace VoiceKey.App;

/// <summary>
/// Global hotkey. <c>RegisterHotKey</c> gives the press and swallows the keystroke
/// so the focused app never sees it; Win32 has no matching "hotkey released"
/// message, so a low-level keyboard hook supplies the release that hold-to-talk
/// needs. Both are reported, so toggle and hold-to-talk share one key.
/// </summary>
internal sealed class HotKey : IDisposable
{
    private const int WmHotKey = 0x0312;
    private const int HotKeyId = 1;
    private const int WhKeyboardLl = 13;
    private const int WmKeyUp = 0x0101;
    private const int WmSysKeyUp = 0x0105;
    private const uint ModNoRepeat = 0x4000;

    private readonly HwndSource _source;
    private readonly Action _onPress;
    private readonly Action _onRelease;
    private readonly uint _virtualKey;
    private readonly LowLevelKeyboardProc _hookProc;
    private readonly nint _hook;
    private bool _isPressed;

    internal bool IsRegistered { get; }

    internal HotKey(Shortcut shortcut, Action onPress, Action onRelease)
    {
        _onPress = onPress;
        _onRelease = onRelease;
        _virtualKey = shortcut.VirtualKey;

        // A message-only window: somewhere for WM_HOTKEY to land without any UI.
        _source = new HwndSource(new HwndSourceParameters("VoiceKeyHotKey")
        {
            ParentWindow = -3, // HWND_MESSAGE
            WindowStyle = 0,
        });
        _source.AddHook(WndProc);

        IsRegistered = RegisterHotKey(_source.Handle, HotKeyId,
                                      shortcut.Modifiers | ModNoRepeat, shortcut.VirtualKey);
        Log.Line($"hotkey registration {(IsRegistered ? "ok" : "FAILED")} for {shortcut.Label}");

        _hookProc = HookProc;
        _hook = SetWindowsHookExW(WhKeyboardLl, _hookProc, nint.Zero, 0);
        if (_hook == nint.Zero) Log.Line("keyboard hook installation FAILED — hold-to-talk is off");
    }

    private nint WndProc(nint hwnd, int message, nint wParam, nint lParam, ref bool handled)
    {
        if (message != WmHotKey || wParam != HotKeyId) return nint.Zero;
        handled = true;
        if (_isPressed) return nint.Zero;
        _isPressed = true;
        _onPress();
        return nint.Zero;
    }

    private nint HookProc(int code, nint wParam, nint lParam)
    {
        if (code >= 0 && _isPressed && (wParam == WmKeyUp || wParam == WmSysKeyUp)
            && (uint)Marshal.ReadInt32(lParam) == _virtualKey)
        {
            _isPressed = false;
            _onRelease();
        }
        return CallNextHookEx(nint.Zero, code, wParam, lParam);
    }

    public void Dispose()
    {
        if (IsRegistered) UnregisterHotKey(_source.Handle, HotKeyId);
        if (_hook != nint.Zero) UnhookWindowsHookEx(_hook);
        _source.RemoveHook(WndProc);
        _source.Dispose();
    }

    private delegate nint LowLevelKeyboardProc(int code, nint wParam, nint lParam);

    [DllImport("user32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool RegisterHotKey(nint hWnd, int id, uint modifiers, uint virtualKey);

    [DllImport("user32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool UnregisterHotKey(nint hWnd, int id);

    [DllImport("user32.dll", SetLastError = true)]
    private static extern nint SetWindowsHookExW(int idHook, LowLevelKeyboardProc lpfn,
                                                 nint hMod, uint threadId);

    [DllImport("user32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool UnhookWindowsHookEx(nint hook);

    [DllImport("user32.dll")]
    private static extern nint CallNextHookEx(nint hook, int code, nint wParam, nint lParam);
}
