using System.Globalization;
using System.Text;

namespace CheCavo.Windows;

// Turns what Windows sees into the four answers of the Mac app. Windows has no UCSI on most PCs and no access to
// the cable chip, so every answer comes from the device on the other end of the cable, never from the cable itself.
public static class Assessment
{
    static readonly CultureInfo It = CultureInfo.GetCultureInfo("it-IT");

    // Windows does not pass the cable chip to apps, so not even «there is no chip» can be said.
    static readonly Answer Chip = new(Verdict.Unknown, "Non si legge su questo PC",
        "Windows non passa alle app i dati del chip del cavo: non posso dire se il cavo ce l'ha, né i watt e la velocità "
        + "che dichiara. Per saperlo collega il cavo a un Mac con CheCavo. Qui sotto c'è quello che Windows vede.",
        Certainty.Unknowable);

    static bool IsDisplayPort(Display d) => d.Technology is 10 or 18;
    static bool Works(UsbDevice d) => d.Status == 1;
    static bool IsFast(UsbDevice d) => d.Speed >= UsbSpeed.Super;

    // A device running below what it supports: the cable or the port is holding it back.
    // Hubs are left out: a USB 3 hub always shows its USB 2 half next to the USB 3 one.
    static bool Braked(UsbDevice d) => !d.IsHub && Works(d)
        && ((d.Speed < UsbSpeed.Super && d.SuperSpeedCapable) || (d.Speed == UsbSpeed.Super && d.SuperSpeedPlusCapable));

    // The device that says most about the cable: one that does not work, then one held back, then the fastest.
    static UsbDevice? Judged(IReadOnlyList<UsbDevice> devices) =>
        devices.FirstOrDefault(d => !Works(d)) ?? devices.FirstOrDefault(Braked) ?? devices.MaxBy(d => d.Speed);

    static string Rate(UsbSpeed s) => s switch
    {
        UsbSpeed.Low => "1,5 Mbit/s", UsbSpeed.Full => "12 Mbit/s", UsbSpeed.High => "480 Mbit/s",
        UsbSpeed.Super => "5 Gbit/s", _ => "10 Gbit/s",
    };

    public static Report Assess(Observation o)
    {
        var judged = Judged(o.Devices);
        var (data, dataHeadline) = Data(judged);
        var video = Video(o, judged);
        var audio = Audio(o);
        var charging = Charging(o.Power);

        var trials = new List<Trial>
        {
            new("Dati", "Collega al cavo un telefono, un disco o una chiavetta.",
                "La velocità a cui Windows lo fa funzionare e se il cavo ha i fili veloci.",
                data.Certainty is not null, data.Certainty is not null ? data.Summary : null),
            new("Video", "Collega al cavo un monitor che si attacca con l'USB-C.",
                "Se il monitor si accende, con la risoluzione e la frequenza.",
                video.Certainty == Certainty.Measured, video.Certainty == Certainty.Measured ? video.Summary : null),
            new("Ricarica", "Collega il caricatore al PC con questo cavo.",
                "Quanti watt entrano nella batteria in questo momento.",
                charging.Certainty == Certainty.Measured, charging.Certainty == Certainty.Measured ? charging.Summary : null),
        };

        var headline = trials[0].Done ? dataHeadline
            : trials[1].Done ? "Il cavo porta il video"
            : trials[2].Done ? "Il PC si carica"
            : "Collega qualcosa all'altro capo del cavo";

        var notes = new List<string>();
        // The two halves of a USB 3 hub are one thing on the cable.
        int things = o.Devices.Count(d => !d.IsHub) + (o.Devices.Any(d => d.IsHub) ? 1 : 0);
        if (things > 1 && judged is not null)
            notes.Add($"Ci sono {things} dispositivi sulle porte USB-C: la risposta sui dati guarda «{judged.Name}». "
                + "Per una risposta sicura lascia collegato solo quello che vuoi provare.");

        return new(Chip, headline, charging, video, audio, data, trials, notes);
    }

    static (Answer, string) Data(UsbDevice? d)
    {
        if (d is null)
            return (new(Verdict.Unknown, "Da provare",
                "Collega al cavo un telefono, un disco o una chiavetta. Se Windows non vede niente, "
                + "il cavo è probabilmente solo da ricarica (oppure il telefono chiede di scegliere «Trasferimento file»).", null), "");

        if (!Works(d))
            return (new(Verdict.Partial, $"Windows vede «{d.Name}» ma non funziona",
                $"Stato della porta: {UsbDecode.StatusName(d.Status)}. Succede con un cavo rovinato o un contatto sporco: "
                + "scollega e ricollega bene, poi prova un altro cavo.", Certainty.Measured), "Il dispositivo non funziona");

        if (d.Speed == UsbSpeed.SuperPlus)
            return (new(Verdict.Yes, "Almeno 10 Gbit/s (10 GB in circa 15 secondi)",
                $"«{d.Name}» funziona a 10 Gbit/s o più: il cavo ha i fili veloci.", Certainty.Measured), "Cavo veloce: almeno 10 Gbit/s");

        if (d.Speed == UsbSpeed.Super && d.SuperSpeedPlusCapable)
            return (new(Verdict.Partial, "5 Gbit/s, ma il dispositivo regge 10",
                $"«{d.Name}» potrebbe andare a 10 Gbit/s. Il limite è il cavo o questa porta del PC: "
                + "prova un'altra porta, e se resta a 5 è il cavo.", Certainty.Measured), "Cavo o porta fermi a 5 Gbit/s");

        if (d.Speed == UsbSpeed.Super)
            return (new(Verdict.Yes, "5 Gbit/s (10 GB in circa 30 secondi)",
                $"«{d.Name}» funziona a 5 Gbit/s: il cavo ha i fili veloci (USB 3).", Certainty.Measured), "Cavo con i fili veloci (USB 3)");

        if (Braked(d))
            return (new(Verdict.Partial, $"Lenti: {Rate(d.Speed)}, ma il dispositivo regge {(d.SuperSpeedPlusCapable ? "10" : "5")} Gbit/s",
                $"«{d.Name}» potrebbe andare molto più veloce. Di solito vuol dire che il cavo ha solo i fili USB 2.0. "
                + "Sui telefoni succede anche finché non scegli «Trasferimento file»: se l'hai già scelto, è il cavo.",
                Certainty.Inferred), "Cavo probabilmente solo USB 2.0");

        return (new(Verdict.Yes, d.Speed == UsbSpeed.High ? "480 Mbit/s (10 GB in circa 5 minuti)" : Rate(d.Speed),
            $"«{d.Name}» è un dispositivo lento e funziona alla sua velocità: il cavo porta i dati. "
            + "Per sapere se ha anche i fili veloci prova con un disco o una chiavetta USB 3.", Certainty.Measured), "Il cavo porta i dati");
    }

    static Answer Video(Observation o, UsbDevice? judged)
    {
        if (o.Displays.FirstOrDefault(IsDisplayPort) is { } m)
        {
            var mode = m.Width > 0 ? $", {m.Width}×{m.Height} a {Math.Round(m.Hertz)} Hz" : "";
            return new(Verdict.Yes, $"Sì: {m.Name}{mode}",
                "Windows vede un monitor collegato in DisplayPort, il video che passa dall'USB-C. "
                + "Windows non dice da quale porta arriva: se hai collegato solo questo cavo, è lui.", Certainty.Measured);
        }
        if (judged is not null && Braked(judged) && judged.Speed < UsbSpeed.Super)
            return new(Verdict.No, "Probabilmente no",
                "Il video passa sui fili veloci, e questo cavo sembra avere solo quelli USB 2.0.", Certainty.Inferred);
        if (o.Devices.Any(d => Works(d) && IsFast(d)))
            return new(Verdict.Yes, "Probabilmente sì",
                "Il cavo ha i fili veloci, quelli che servono anche al video. Per esserne certo prova con un monitor USB-C.", Certainty.Inferred);

        var hdmi = o.Displays.Any(d => d.Technology == 5) ? " Il monitor in HDMI non conta: non passa da questo cavo." : "";
        return new(Verdict.Unknown, "Da provare con un monitor USB-C",
            "Collega al cavo un monitor che si attacca con l'USB-C: se si accende, il cavo porta il video." + hdmi, null);
    }

    static Answer Audio(Observation o)
    {
        if (o.Devices.FirstOrDefault(Works) is { } d)
            return new(Verdict.Yes, "Sì, per cuffie e schede audio USB",
                $"L'audio USB usa i fili che già funzionano con «{d.Name}».", Certainty.Inferred);
        if (o.Displays.Any(IsDisplayPort))
            return new(Verdict.Yes, "Sì, verso il monitor",
                "L'audio viaggia insieme al video DisplayPort, se il monitor ha gli altoparlanti.", Certainty.Inferred);
        return new(Verdict.Unknown, "Da provare",
            "Basta che un dispositivo USB funzioni con questo cavo: l'audio USB usa gli stessi fili.", null);
    }

    static Answer Charging(PowerState p)
    {
        const string NotTheMax = " È quanto chiede la batteria adesso, non il massimo del cavo. "
            + "Windows non dice da quale porta arriva la corrente: se il caricatore è collegato con questo cavo, è lui.";
        if (!p.HasBattery)
            return new(Verdict.Unknown, "Non misurabile su questo PC",
                "Questo PC non ha una batteria, quindi Windows non dice quanta corrente entra.", Certainty.Unknowable);
        if (p.External && p.ChargeMilliwatts is > 0 and var mw)
        {
            return new(Verdict.Yes, $"Sì: entrano {Watts(mw)} W nella batteria", "La batteria si sta caricando." + NotTheMax, Certainty.Measured);
        }
        if (p.External)
            return new(Verdict.Yes, "Sì: il PC è alimentato",
                "Il PC va a corrente, ma la batteria in questo momento non si carica (forse è già piena)." + NotTheMax, Certainty.Measured);
        return new(Verdict.Unknown, "Da provare", "Collega il caricatore al PC con questo cavo.", null);
    }

    /// Watts as people read them: one decimal below 10 W («2,8»), whole above («28»).
    public static string Watts(int milliwatts)
    {
        double w = milliwatts / 1000.0;
        return w < 10 ? w.ToString("0.0", It) : Math.Round(w).ToString(It);
    }

    /// The top of the watt dial: the first usual charger size that holds the watts, as on the Mac.
    public static int GaugeScale(int? milliwatts)
    {
        double w = (milliwatts ?? 0) / 1000.0;
        return new[] { 30, 60, 100, 140, 240 }.FirstOrDefault(s => s >= w, (int)Math.Ceiling(w / 10) * 10);
    }

    // The raw data behind the answers, for «Copia dati grezzi» and the technical details.
    public static string Details(Observation o)
    {
        var sb = new StringBuilder();
        sb.AppendLine("Dispositivi sulle porte USB-C:");
        if (o.Devices.Count == 0) sb.AppendLine("  nessuno");
        foreach (var d in o.Devices)
            sb.AppendLine($"  {d.Vid:X4}:{d.Pid:X4} {d.Name}{(d.IsHub ? " (hub)" : "")}: {Rate(d.Speed)}, "
                + $"regge SuperSpeed {(d.SuperSpeedCapable ? "sì" : "no")}, SuperSpeedPlus {(d.SuperSpeedPlusCapable ? "sì" : "no")}, "
                + UsbDecode.StatusName(d.Status));
        sb.AppendLine("Schermi:");
        foreach (var m in o.Displays)
            sb.AppendLine($"  {m.Name}: {WinDecode.OutputTechnology(m.Technology)}, {m.Width}×{m.Height} a {m.Hertz.ToString("0.##", It)} Hz");
        var p = o.Power;
        sb.AppendLine($"Batteria: {(p.HasBattery ? "sì" : "no")}, caricatore: {(p.External ? "sì" : "no")}, "
            + $"ricarica: {(p.ChargeMilliwatts is { } mw ? $"{mw} mW" : "—")}");
        if (o.Errors.Count > 0)
        {
            sb.AppendLine("Letture non riuscite:");
            foreach (var e in o.Errors) sb.AppendLine($"  {e}");
        }
        return sb.ToString();
    }
}
