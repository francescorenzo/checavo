using System.Windows;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using System.Windows.Media;
using System.Windows.Shapes;
using System.Windows.Threading;
using CheCavo.Windows;

namespace CheCavo.App;

/// The Mac window on Windows: the plug and the trials on the left; on the right the cable chip first, next to the
/// watt dial, then what Windows sees. Windows is read every 2 seconds; the window changes only when what Windows sees changes.
sealed class MainWindow : Window
{
    readonly PlugArt plug = new() { HorizontalAlignment = HorizontalAlignment.Left };
    readonly TextBlock status = Label("Sto leggendo le porte USB-C…", 18, FontWeights.SemiBold);
    readonly StackPanel trials = new();
    readonly StackPanel chip = new();
    readonly TextBlock headline = Label("", 18, FontWeights.SemiBold, top: 4);
    readonly UniformGrid tiles = new() { Columns = 4 };
    readonly StackPanel notes = new() { Margin = new(0, 12, 0, 0) };
    readonly TextBox details = new()
    {
        IsReadOnly = true, TextWrapping = TextWrapping.Wrap, FontFamily = new("Consolas"), FontSize = 12,
        BorderThickness = new(0), Background = Brushes.Transparent,
    };
    readonly WattGauge gauge = new() { HorizontalAlignment = HorizontalAlignment.Center, Margin = new(0, 8, 0, 0) };
    readonly TextBlock wattsNote = Label("", 12, secondary: true, top: 4);
    readonly Button copy = new() { Content = "Copia dati grezzi", IsEnabled = false, Padding = new(12, 5, 12, 5) };
    readonly DispatcherTimer timer = new() { Interval = TimeSpan.FromSeconds(2) };
    string shown = "";  // Assessment.Details of what is on screen
    bool reading;

    // Fits a Full HD screen at the usual 150% scaling (1280×680 points free); only smaller screens scroll.
    const double ContentWidth = 1180;

    public MainWindow()
    {
        SetResourceReference(StyleProperty, typeof(Window));  // a subclass does not get the theme's implicit Window style
        Title = "CheCavo · a cosa serve questo cavo USB-C";
        SizeToContent = SizeToContent.WidthAndHeight;
        MaxWidth = SystemParameters.WorkArea.Width;
        MaxHeight = SystemParameters.WorkArea.Height;
        ResizeMode = ResizeMode.CanMinimize;
        WindowStartupLocation = WindowStartupLocation.CenterScreen;
        copy.Click += Copy;

        // wide rather than tall: the trials on the left; the chip and the watt dial side by side; the four tiles in one row
        var upper = new Grid();
        upper.ColumnDefinitions.Add(new() { Width = new(1, GridUnitType.Star) });
        upper.ColumnDefinitions.Add(new() { Width = new(12) });
        upper.ColumnDefinitions.Add(new() { Width = new(240) });
        chip.VerticalAlignment = VerticalAlignment.Center;  // as tall as the dial beside it
        Add(upper, 0, Panel(chip));
        Add(upper, 2, Panel(Gauge()));

        var right = new Grid();
        right.RowDefinitions.Add(new() { Height = GridLength.Auto });
        right.RowDefinitions.Add(new() { Height = new(12) });
        right.RowDefinitions.Add(new() { Height = new(1, GridUnitType.Star) });
        right.Children.Add(upper);
        var seen = Panel(Seen());
        Grid.SetRow(seen, 2);
        right.Children.Add(seen);

        var columns = new Grid { Width = ContentWidth, Margin = new(12) };
        columns.ColumnDefinitions.Add(new() { Width = new(230) });
        columns.ColumnDefinitions.Add(new() { Width = new(12) });
        columns.ColumnDefinitions.Add(new() { Width = new(1, GridUnitType.Star) });
        Add(columns, 0, Panel(Sidebar()));
        Add(columns, 2, right);
        Content = new ScrollViewer
        {
            Content = columns,
            VerticalScrollBarVisibility = ScrollBarVisibility.Auto,
            HorizontalScrollBarVisibility = ScrollBarVisibility.Auto,
        };

        gauge.Set(null, "nessuna ricarica");
        Loaded += Tick;
        timer.Tick += Tick;
        timer.Start();
    }

    UIElement Sidebar()
    {
        // the plug beside the status, not above it, and what Windows cannot do at the bottom: no empty column
        var head = new DockPanel();
        plug.Width = plug.Height = 44;
        plug.Margin = new(0, 0, 10, 0);
        DockPanel.SetDock(plug, Dock.Left);
        head.Children.Add(plug);
        status.VerticalAlignment = VerticalAlignment.Center;
        head.Children.Add(status);

        var limits = new StackPanel { Margin = new(0, 16, 0, 0) };
        limits.Children.Add(Label("Su Windows inoltre non si può", 12, FontWeights.SemiBold, secondary: true));
        foreach (var line in new[]
        {
            "provare il cavo tra due porte di questo PC;",
            "sapere da quale porta arrivano il video e la corrente.",
        })
            limits.Children.Add(Label("• " + line, 12, secondary: true, top: 4));

        var side = new DockPanel();
        DockPanel.SetDock(limits, Dock.Bottom);
        side.Children.Add(limits);
        var top = new StackPanel();
        top.Children.Add(head);
        top.Children.Add(Label("Le prove che puoi fare", 13, FontWeights.SemiBold, secondary: true, top: 16));
        top.Children.Add(trials);
        side.Children.Add(top);
        return side;
    }

    UIElement Seen()
    {
        var seen = new StackPanel();
        seen.Children.Add(Label("Quello che Windows vede adesso", 13, FontWeights.Medium, secondary: true));
        seen.Children.Add(headline);
        tiles.Margin = new(-5, 6, -5, 0);
        seen.Children.Add(tiles);
        seen.Children.Add(notes);
        // the raw data sit next to the technical details they come from
        var bottom = new DockPanel { Margin = new(0, 8, 0, 0) };
        copy.VerticalAlignment = VerticalAlignment.Top;
        DockPanel.SetDock(copy, Dock.Right);
        bottom.Children.Add(copy);
        bottom.Children.Add(new Expander { Header = "Dettagli tecnici", Content = details, Margin = new(0, 0, 12, 0) });
        seen.Children.Add(bottom);
        return seen;
    }

    UIElement Gauge()
    {
        var panel = new StackPanel();
        var title = Label("Ricarica della batteria", 13, FontWeights.Medium, secondary: true);
        title.TextAlignment = TextAlignment.Center;
        panel.Children.Add(title);
        panel.Children.Add(gauge);
        wattsNote.TextAlignment = TextAlignment.Center;
        panel.Children.Add(wattsNote);
        return panel;
    }

    async void Tick(object? sender, EventArgs e)
    {
        if (reading) return;  // a slow read (a hub that answers late) never piles up
        reading = true;
        try { Show(await Task.Run(Reader.Read)); }
        catch (Exception ex) { headline.Text = "Non riesco a leggere le porte: " + ex.Message; shown = ""; }  // the next good read redraws
        finally { reading = false; }
    }

    void Show(Observation o)
    {
        var raw = Assessment.Details(o);
        if (raw == shown) return;
        shown = raw;
        copy.IsEnabled = true;
        details.Text = raw;

        var r = Assessment.Assess(o);
        bool seen = r.Trials.Any(t => t.Done);
        plug.Set(seen);
        status.Text = seen ? "Windows vede qualcosa collegato" : "Collega un cavo";
        headline.Text = r.Headline;

        chip.Children.Clear();
        chip.Children.Add(ChipRow(r.Chip));

        trials.Children.Clear();
        foreach (var t in r.Trials) trials.Children.Add(TrialRow(t));

        tiles.Children.Clear();
        tiles.Children.Add(Tile("Ricarica", "\uE945", r.Charging));  // LightningBolt
        tiles.Children.Add(Tile("Video", "\uE7F4", r.Video));        // TVMonitor
        tiles.Children.Add(Tile("Audio", "\uE767", r.Audio));        // Volume
        tiles.Children.Add(Tile("Dati", "\uE8AB", r.Data));          // Switch: two arrows

        notes.Children.Clear();
        foreach (var n in r.Notes) notes.Children.Add(Label("ⓘ  " + n, 13, secondary: true, top: 4));

        var p = o.Power;
        gauge.Set(p.ChargeMilliwatts, !p.HasBattery ? "PC senza batteria" : p.ChargeMilliwatts is not null ? "in carica adesso" : "nessuna ricarica");
        wattsNote.Text = !p.HasBattery ? "Questo PC non ha una batteria."
            : p.ChargeMilliwatts is not null ? "Entrano adesso nella batteria."
            : p.External ? "Il PC è alimentato, ma la batteria non si sta caricando."
            : "Collega il caricatore al PC con questo cavo.";
    }

    /// The cable chip comes first: what the user wants to know before anything else.
    static UIElement ChipRow(Answer a)
    {
        var art = new ChipArt { VerticalAlignment = VerticalAlignment.Top, Margin = new(0, 2, 12, 0) };
        var text = new StackPanel();
        text.Children.Add(Label("Chip del cavo", 13, FontWeights.Medium, secondary: true));
        text.Children.Add(Label(a.Summary, 18, FontWeights.SemiBold, top: 2));
        text.Children.Add(Label(a.Detail, 13, secondary: true, top: 4));
        if (a.Certainty is { } c) text.Children.Add(Pill(c));
        var row = new DockPanel();
        DockPanel.SetDock(art, Dock.Left);
        row.Children.Add(art);
        row.Children.Add(text);
        return row;
    }

    static UIElement TrialRow(Trial t)
    {
        var mark = Label(t.Done ? "✓" : "○", 16, FontWeights.SemiBold, secondary: !t.Done);
        if (t.Done) mark.SetResourceReference(TextBlock.ForegroundProperty, "SystemFillColorSuccessBrush");
        mark.Width = 24;

        var text = new StackPanel();
        text.Children.Add(Label(t.Title, 14, FontWeights.SemiBold));
        text.Children.Add(Label(t.HowTo, 12, secondary: true, top: 2));
        text.Children.Add(t.Done
            ? Label(t.Result ?? "", 12, FontWeights.SemiBold, top: 4)
            : Label("Vedrai: " + t.WhatYouSee, 12, secondary: true, top: 4));

        var row = new DockPanel { Margin = new(0, 12, 0, 0) };
        DockPanel.SetDock(mark, Dock.Left);
        row.Children.Add(mark);
        row.Children.Add(text);
        return row;
    }

    static UIElement Tile(string title, string icon, Answer a)
    {
        var mark = Badge(a.Verdict);
        var symbol = Label(icon, 14, secondary: true);
        symbol.FontFamily = Icons;
        symbol.Margin = new(0, 1, 6, 0);
        var head = new DockPanel();
        DockPanel.SetDock(mark, Dock.Right);
        DockPanel.SetDock(symbol, Dock.Left);
        head.Children.Add(mark);
        head.Children.Add(symbol);
        head.Children.Add(Label(title, 13, FontWeights.Medium, secondary: true));

        var body = new StackPanel();
        body.Children.Add(head);
        body.Children.Add(Label(a.Summary, 14, FontWeights.SemiBold, top: 4));
        body.Children.Add(Label(a.Detail, 12, secondary: true, top: 4));
        if (a.Certainty is { } c) body.Children.Add(Pill(c));

        var tile = new Border { CornerRadius = new(10), Padding = new(12), Margin = new(5), Child = body };
        tile.SetResourceReference(Border.BackgroundProperty, "SubtleFillColorSecondaryBrush");
        return tile;
    }

    // Segoe Fluent Icons on Windows 11, Segoe MDL2 Assets on Windows 10: the same code points.
    static readonly FontFamily Icons = new("Segoe Fluent Icons, Segoe MDL2 Assets");

    /// The verdict as a colored disc with a white sign, like the Mac's filled SF Symbols.
    static UIElement Badge(Verdict v)
    {
        var (sign, brush) = v switch
        {
            Verdict.Yes => ("\uE73E", "SystemFillColorSuccessBrush"),
            Verdict.Partial => ("!", "SystemFillColorCautionBrush"),
            Verdict.No => ("\uE711", "SystemFillColorCriticalBrush"),
            _ => ("?", "TextFillColorSecondaryBrush"),
        };
        var disc = new Ellipse { Width = 22, Height = 22 };
        disc.SetResourceReference(Shape.FillProperty, brush);
        var text = new TextBlock
        {
            Text = sign, Foreground = Brushes.White, FontWeight = FontWeights.Bold, FontSize = sign.Length == 1 && sign[0] < 0xE000 ? 14 : 11,
            HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Center,
        };
        if (sign[0] >= 0xE000) text.FontFamily = Icons;
        var g = new Grid { VerticalAlignment = VerticalAlignment.Top };
        g.Children.Add(disc);
        g.Children.Add(text);
        return g;
    }

    static UIElement Pill(Certainty c)
    {
        var (text, color) = c switch
        {
            Certainty.Measured => ("provato adesso", Color.FromRgb(0x2E, 0x9E, 0x44)),
            Certainty.Inferred => ("dedotto", Color.FromRgb(0x8A, 0x8A, 0x8A)),  // grey as on the Mac: blue is «dichiarato dal chip»
            _ => ("non si può sapere", Color.FromRgb(0x8A, 0x8A, 0x8A)),
        };
        return new Border
        {
            CornerRadius = new(9), Padding = new(8, 1, 8, 2), Margin = new(0, 8, 0, 0),
            HorizontalAlignment = HorizontalAlignment.Left,
            Background = new SolidColorBrush(Color.FromArgb(0x30, color.R, color.G, color.B)),
            Child = new TextBlock { Text = text, FontSize = 11, FontWeight = FontWeights.Medium, Foreground = new SolidColorBrush(color) },
        };
    }

    async void Copy(object sender, RoutedEventArgs e)
    {
        try { Clipboard.SetText(shown); copy.Content = "Copiato"; }
        catch (Exception) { copy.Content = "Appunti occupati, riprova"; }  // another app is holding the clipboard
        await Task.Delay(1500);
        copy.Content = "Copia dati grezzi";
    }

    /// The rounded box of each column (the Mac's .panel()).
    static Border Panel(UIElement child)
    {
        var card = new Border { CornerRadius = new(12), Padding = new(16), BorderThickness = new(1), Child = child };
        card.SetResourceReference(Border.BackgroundProperty, "CardBackgroundFillColorDefaultBrush");
        card.SetResourceReference(Border.BorderBrushProperty, "CardStrokeColorDefaultBrush");
        return card;
    }

    static TextBlock Label(string text, double size, FontWeight? weight = null, bool secondary = false, double top = 0)
    {
        var t = new TextBlock { Text = text, FontSize = size, FontWeight = weight ?? FontWeights.Normal, TextWrapping = TextWrapping.Wrap, Margin = new(0, top, 0, 0) };
        if (secondary) t.SetResourceReference(TextBlock.ForegroundProperty, "TextFillColorSecondaryBrush");
        return t;
    }

    static void Add(Grid grid, int column, UIElement child)
    {
        Grid.SetColumn(child, column);
        grid.Children.Add(child);
    }
}
