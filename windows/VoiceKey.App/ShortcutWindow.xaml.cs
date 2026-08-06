using System.Windows;
using System.Windows.Input;

namespace VoiceKey.App;

/// <summary>
/// Captures the next key combo pressed and hands it back. Esc, or closing the
/// window, cancels and leaves the current shortcut alone.
/// </summary>
public partial class ShortcutWindow : Window
{
    private Shortcut? _captured;

    private ShortcutWindow() => InitializeComponent();

    /// <summary>The combo the user pressed, or null if they cancelled.</summary>
    internal static Shortcut? Capture(Window? owner)
    {
        var window = new ShortcutWindow();
        if (owner is not null && owner.IsVisible) window.Owner = owner;
        else window.WindowStartupLocation = WindowStartupLocation.CenterScreen;
        window.ShowDialog();
        return window._captured;
    }

    private void OnPreviewKeyDown(object sender, KeyEventArgs e)
    {
        e.Handled = true; // swallow the keystroke, whatever it turns out to be
        if (e.Key == Key.Escape)
        {
            Close();
            return;
        }

        // Alt arrives as Key.System with the real key in SystemKey.
        var key = e.Key == Key.System ? e.SystemKey : e.Key;
        // An unusable combo is simply ignored: the window waits for a better one.
        if (Shortcut.From(key, Keyboard.Modifiers) is not { } shortcut) return;

        _captured = shortcut;
        Close();
    }
}
