using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Threading;

namespace VoiceKey.App;

/// <summary>
/// Inserts text at the cursor of the foreground app: snapshot the clipboard,
/// write the transcript, synthesize Ctrl+V, restore the snapshot.
///
/// Unlike macOS this needs no permission grant — but UIPI still blocks synthetic
/// input aimed at a process running elevated when VoiceKey is not.
/// </summary>
internal static class TextInserter
{
    /// <summary>Long enough for the target app to have served the paste.</summary>
    private static readonly TimeSpan RestoreDelay = TimeSpan.FromMilliseconds(700);

    internal static void Insert(string text)
    {
        var saved = Snapshot();
        if (!SetClipboardText(text))
        {
            Log.Line("clipboard is locked by another app — nothing inserted");
            return;
        }

        SendPaste();

        var timer = new DispatcherTimer { Interval = RestoreDelay };
        timer.Tick += (_, _) =>
        {
            timer.Stop();
            Restore(saved);
        };
        timer.Start();
    }

    /// <summary>Copies out every format the clipboard currently holds, as far as it will allow.</summary>
    private static DataObject? Snapshot()
    {
        try
        {
            var current = Clipboard.GetDataObject();
            if (current is null) return null;
            var backup = new DataObject();
            foreach (var format in current.GetFormats())
            {
                try
                {
                    var value = current.GetData(format);
                    if (value is not null) backup.SetData(format, value);
                }
                catch (Exception exception) when (exception is ExternalException
                    or OutOfMemoryException or NotSupportedException)
                {
                    // A format that refuses to be read is a format we cannot restore.
                }
            }
            return backup;
        }
        catch (ExternalException)
        {
            return null;
        }
    }

    private static void Restore(DataObject? saved)
    {
        try
        {
            if (saved is null) Clipboard.Clear();
            else Clipboard.SetDataObject(saved, true);
        }
        catch (ExternalException exception)
        {
            Log.Line($"could not restore the clipboard: {exception.Message}");
        }
    }

    private static bool SetClipboardText(string text)
    {
        // The clipboard is a shared, briefly-locked resource; a couple of retries
        // is the difference between "usually works" and "works".
        for (var attempt = 0; attempt < 5; attempt++)
        {
            try
            {
                Clipboard.SetText(text);
                return true;
            }
            catch (ExternalException)
            {
                // The clipboard is a single system-wide resource another process
                // can hold open; ExternalException, not just its COMException
                // subclass, is what a busy clipboard actually throws.
                Thread.Sleep(30);
            }
        }
        return false;
    }

    // MARK: - Synthetic Ctrl+V

    private const ushort VkControl = 0x11;
    private const ushort VkV = 0x56;
    private const uint InputKeyboard = 1;
    private const uint KeyEventKeyUp = 0x0002;

    private static void SendPaste()
    {
        INPUT[] strokes =
        [
            Key(VkControl, false), Key(VkV, false),
            Key(VkV, true), Key(VkControl, true),
        ];
        var sent = SendInput((uint)strokes.Length, strokes, Marshal.SizeOf<INPUT>());
        if (sent != strokes.Length)
            Log.Line($"SendInput sent {sent}/{strokes.Length} strokes (error {Marshal.GetLastWin32Error()})");
    }

    private static INPUT Key(ushort virtualKey, bool up) => new()
    {
        type = InputKeyboard,
        union = new INPUTUNION
        {
            keyboard = new KEYBDINPUT
            {
                wVk = virtualKey,
                dwFlags = up ? KeyEventKeyUp : 0,
            },
        },
    };

    [StructLayout(LayoutKind.Sequential)]
    private struct INPUT
    {
        internal uint type;
        internal INPUTUNION union;
    }

    [StructLayout(LayoutKind.Explicit)]
    private struct INPUTUNION
    {
        [FieldOffset(0)] internal KEYBDINPUT keyboard;
        [FieldOffset(0)] internal MOUSEINPUT mouse;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct KEYBDINPUT
    {
        internal ushort wVk;
        internal ushort wScan;
        internal uint dwFlags;
        internal uint time;
        internal nint dwExtraInfo;
    }

    /// <summary>Never filled in — it is only here to give the union its true size.</summary>
    [StructLayout(LayoutKind.Sequential)]
    private struct MOUSEINPUT
    {
        internal int dx, dy;
        internal uint mouseData, dwFlags, time;
        internal nint dwExtraInfo;
    }

    [DllImport("user32.dll", SetLastError = true)]
    private static extern uint SendInput(uint count, INPUT[] inputs, int size);
}
