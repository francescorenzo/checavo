using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Shapes;
using CheCavo.Windows;

namespace CheCavo.App;

// The drawings of the Mac app, redrawn with WPF shapes. Colors come from the Fluent theme: they follow light and dark mode.

/// A stylized USB-C plug with its cable on an 18×18 grid (the Mac's PlugArt): outline when nothing is seen, solid when something is.
sealed class PlugArt : Viewbox
{
    readonly Path tip = Stroked(new RectangleGeometry(new(5.25, 1.25, 7.5, 4.5), 2.25, 2.25), 1.5);
    readonly Path slot = Stroked(new LineGeometry(new(7.5, 3.5), new(10.5, 3.5)), 1.25);
    readonly Path grip = new() { Data = new RectangleGeometry(new(4.25, 6.25, 9.5, 5), 2, 2) };
    readonly Path gripLine = Stroked(new RectangleGeometry(new(4.25, 6.25, 9.5, 5), 2, 2), 1.5);
    readonly Path cable = Stroked(new LineGeometry(new(9, 12), new(9, 17.5)), 2);

    public PlugArt()
    {
        var c = new Canvas { Width = 18, Height = 18 };
        foreach (var p in new[] { grip, tip, slot, gripLine, cable }) c.Children.Add(p);
        Child = c;
        Width = Height = 56;
        Set(found: false);
    }

    public void Set(bool found)
    {
        var brush = found ? "AccentFillColorDefaultBrush" : "TextFillColorSecondaryBrush";
        foreach (var p in new[] { tip, slot, gripLine, cable }) p.SetResourceReference(Shape.StrokeProperty, brush);
        grip.SetResourceReference(Shape.FillProperty, brush);
        grip.Opacity = found ? 1 : 0.2;  // a light fill keeps the grip readable as a plug
    }

    internal static Path Stroked(Geometry g, double width) => new()
    {
        Data = g, StrokeThickness = width, StrokeStartLineCap = PenLineCap.Round, StrokeEndLineCap = PenLineCap.Round,
    };
}

/// The cable chip, drawn grey: on Windows it is never read.
sealed class ChipArt : Viewbox
{
    public ChipArt()
    {
        var c = new Canvas { Width = 18, Height = 18 };
        var lines = new List<Path> { PlugArt.Stroked(new RectangleGeometry(new(4, 4, 10, 10), 1.5, 1.5), 1.5) };
        foreach (var i in new[] { 6.5, 9, 11.5 })
            foreach (var (a, b) in new[] { ((i, 1.5), (i, 4.0)), ((i, 14.0), (i, 16.5)), ((1.5, i), (4.0, i)), ((14.0, i), (16.5, i)) })
                lines.Add(PlugArt.Stroked(new LineGeometry(new(a.Item1, a.Item2), new(b.Item1, b.Item2)), 1.25));
        foreach (var l in lines) { l.SetResourceReference(Shape.StrokeProperty, "TextFillColorSecondaryBrush"); c.Children.Add(l); }
        var core = new Path { Data = new RectangleGeometry(new(7, 7, 4, 4), 0.75, 0.75) };
        core.SetResourceReference(Shape.FillProperty, "TextFillColorSecondaryBrush");
        c.Children.Add(core);
        Child = c;
        Width = Height = 34;
    }
}

/// A speedometer-style dial with the watts entering the battery now (the Mac's WattGauge).
sealed class WattGauge : Canvas
{
    const double R = 80, C = 88, Sweep = 240;  // degrees, from lower left (150°) clockwise to lower right (30°)

    public WattGauge()
    {
        Width = 2 * C;
        Height = 168;  // the dial is open at the bottom: the watts sit in the gap
    }

    public void Set(int? milliwatts, string caption)
    {
        Children.Clear();
        int scale = Assessment.GaugeScale(milliwatts);
        double f = Math.Clamp((milliwatts ?? 0) / 1000.0 / scale, 0, 1);

        var track = Arc(0, 1);
        track.SetResourceReference(Shape.StrokeProperty, "TextFillColorPrimaryBrush");
        track.Opacity = 0.1;
        Children.Add(track);
        if (f > 0)
        {
            var value = Arc(0, f);
            value.Stroke = new LinearGradientBrush(Color.FromRgb(0x30, 0xB0, 0xC7), Color.FromRgb(0x34, 0xC7, 0x59), 0);
            Children.Add(value);
        }

        for (int i = 0; i <= 8; i++)
        {
            bool longTick = i % 4 == 0;
            var tick = PlugArt.Stroked(new LineGeometry(At(i / 8.0, R - 12), At(i / 8.0, R - (longTick ? 20 : 16))), longTick ? 1.5 : 1);
            tick.SetResourceReference(Shape.StrokeProperty, "TextFillColorSecondaryBrush");
            Children.Add(tick);
        }
        foreach (var t in new[] { 0.0, 0.5, 1.0 })
        {
            var p = At(t, R - 32);
            var label = new TextBlock { Text = ((int)Math.Round(scale * t)).ToString(), FontSize = 11, Width = 40, TextAlignment = TextAlignment.Center };
            label.SetResourceReference(TextBlock.ForegroundProperty, "TextFillColorSecondaryBrush");
            Place(label, p.X - 20, p.Y - 8);
        }

        // the needle stops short of the scale numbers
        var needle = PlugArt.Stroked(new LineGeometry(new(C, C), At(f, R - 40)), 4);
        needle.SetResourceReference(Shape.StrokeProperty, "TextFillColorPrimaryBrush");
        Children.Add(needle);
        Dot(14, "TextFillColorPrimaryBrush");
        Dot(5, "SolidBackgroundFillColorBaseBrush");

        var text = new StackPanel { Width = 2 * C };
        text.Children.Add(new TextBlock
        {
            Text = milliwatts is { } mw ? Assessment.Watts(mw) + " W" : "0 W",
            FontSize = 28, FontWeight = FontWeights.SemiBold, TextAlignment = TextAlignment.Center,
        });
        var cap = new TextBlock { Text = caption, FontSize = 12, TextAlignment = TextAlignment.Center };
        cap.SetResourceReference(TextBlock.ForegroundProperty, "TextFillColorSecondaryBrush");
        text.Children.Add(cap);
        Place(text, 0, C + R * 0.62 - 26);
    }

    static Point At(double f, double r)
    {
        double a = (150 + Sweep * f) * Math.PI / 180;
        return new(C + r * Math.Cos(a), C + r * Math.Sin(a));
    }

    static Path Arc(double from, double to)
    {
        var figure = new PathFigure { StartPoint = At(from, R) };
        figure.Segments.Add(new ArcSegment(At(to, R), new(R, R), 0, (to - from) * Sweep > 180, SweepDirection.Clockwise, true));
        var path = PlugArt.Stroked(new PathGeometry([figure]), 12);
        return path;
    }

    void Dot(double size, string brush)
    {
        var e = new Ellipse { Width = size, Height = size };
        e.SetResourceReference(Shape.FillProperty, brush);
        Place(e, C - size / 2, C - size / 2);
    }

    void Place(UIElement e, double left, double top)
    {
        SetLeft(e, left);
        SetTop(e, top);
        Children.Add(e);
    }
}
