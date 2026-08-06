using System.Drawing;
using System.Drawing.Drawing2D;
using System.Runtime.InteropServices;
using Microsoft.Win32;
using VoiceKey.Core;

namespace VoiceKey.App;

/// <summary>
/// The tray glyph ("Keycap &amp; rules"), drawn rather than shipped as PNGs — the
/// design is four rectangles, so vector drawing stays sharp at every scale and
/// keeps the build free of raster assets. Geometry is the macOS handoff spec's,
/// scaled from its 18-unit box to 32 px for high-DPI taskbars.
/// </summary>
internal static class TrayGlyph
{
    private const int Size = 32;
    private const float Scale = Size / 18f;

    private static readonly Dictionary<(Glyph, bool, bool), Icon> Cache = [];

    /// <summary>
    /// The icon for a state. macOS gets light/dark and dimming for free from
    /// template images; on Windows the taskbar theme has to be read and the
    /// dimmed variant drawn by hand.
    /// </summary>
    internal static Icon For(Glyph glyph, bool dimmed)
    {
        var light = TaskbarIsLight();
        var key = (glyph, dimmed, light);
        lock (Cache)
        {
            if (!Cache.TryGetValue(key, out var icon))
            {
                icon = Draw(glyph, dimmed, light);
                Cache[key] = icon;
            }
            return icon;
        }
    }

    private static Icon Draw(Glyph glyph, bool dimmed, bool lightTaskbar)
    {
        // Ink contrasts with the taskbar; a dimmed state is the same ink at 40%.
        var ink = Color.FromArgb(dimmed ? 102 : 255, lightTaskbar ? Color.Black : Color.White);

        using var bitmap = new Bitmap(Size, Size);
        using (var canvas = Graphics.FromImage(bitmap))
        {
            canvas.SmoothingMode = SmoothingMode.AntiAlias;
            canvas.ScaleTransform(Scale, Scale);

            using var rules = new GraphicsPath { FillMode = FillMode.Alternate };
            rules.AddRectangle(new RectangleF(4.5f, 6.9f, 9f, 1.4f));
            rules.AddRectangle(new RectangleF(6f, 10.3f, 6f, 1.4f));

            using var brush = new SolidBrush(ink);
            if (glyph == Glyph.Idle)
            {
                using var pen = new Pen(ink, 1.6f);
                using var key = RoundedRect(new RectangleF(1.3f, 1.3f, 15.4f, 15.4f), 4f);
                canvas.DrawPath(pen, key);
                canvas.FillPath(brush, rules);
            }
            else
            {
                // Solid keycap with the rules knocked out of it.
                using var key = RoundedRect(new RectangleF(0.5f, 0.5f, 17f, 17f), 4f);
                key.FillMode = FillMode.Alternate;
                key.AddPath(rules, false);
                canvas.FillPath(brush, key);
            }
        }

        var handle = bitmap.GetHicon();
        try
        {
            // Clone: the Icon returned by FromHandle does not own the handle, and the
            // handle must be destroyed here rather than leaked for the process's life.
            using var borrowed = Icon.FromHandle(handle);
            return (Icon)borrowed.Clone();
        }
        finally
        {
            DestroyIcon(handle);
        }
    }

    private static GraphicsPath RoundedRect(RectangleF bounds, float radius)
    {
        var diameter = radius * 2;
        var path = new GraphicsPath();
        path.AddArc(bounds.Left, bounds.Top, diameter, diameter, 180, 90);
        path.AddArc(bounds.Right - diameter, bounds.Top, diameter, diameter, 270, 90);
        path.AddArc(bounds.Right - diameter, bounds.Bottom - diameter, diameter, diameter, 0, 90);
        path.AddArc(bounds.Left, bounds.Bottom - diameter, diameter, diameter, 90, 90);
        path.CloseFigure();
        return path;
    }

    private static bool TaskbarIsLight()
    {
        using var key = Registry.CurrentUser.OpenSubKey(
            @"Software\Microsoft\Windows\CurrentVersion\Themes\Personalize");
        return key?.GetValue("SystemUsesLightTheme") is int value && value != 0;
    }

    [DllImport("user32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool DestroyIcon(nint icon);
}
