using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Text;
using Sonda;

// CheCavo probe for Windows: a guided, read-only tour of the USB-C ports that leaves a text log on the Desktop.
// --automatico runs every step without waiting (for the dry run); --cartella <dir> writes the log there.

Console.OutputEncoding = Encoding.UTF8;
const string OnlyWindows = "(solo su Windows)";  // what the dry run on the Mac writes instead
var automatic = args.Contains("--automatico");
var folderAt = Array.IndexOf(args, "--cartella");
var started = DateTime.Now;
var fileName = $"CheCavo-sonda-{started:yyyyMMdd-HHmm}.txt";
var path = Path.Combine(folderAt >= 0 && folderAt + 1 < args.Length ? args[folderAt + 1] : Desktop(), fileName);
var log = new StringBuilder();

var steps = new (string Title, string Ask, int Wait, bool Optional)[]
{
    ("1. Nessun cavo", "Scollega tutto dalle porte USB-C. Mouse e tastiera sulle porte USB-A possono restare.", 5, false),
    ("2. Caricatore", "Collega il caricatore USB-C al PC con il cavo da provare.", 15, true),
    ("3. Cavo tra due porte", "Collega il cavo da provare tra due porte USB-C di questo PC.", 10, true),
    ("4. Monitor", "Collega un monitor USB-C (o un adattatore video USB-C) con il cavo da provare.", 10, true),
    ("5. Dispositivo", "Collega un disco, una chiavetta o un telefono USB-C con il cavo da provare.", 10, true),
};

try
{
    Console.WriteLine("""
        CheCavo - sonda per Windows

        Questo programma guarda come Windows vede le porte USB-C mentre colleghi cavi diversi.
        Legge soltanto: non cambia impostazioni, non installa niente e non usa internet.
        Alla fine trovi un file di testo sulla Scrivania, già aperto nel Blocco note:
        è quello da mandare. Dal file vengono tolti il tuo nome utente, il nome del PC
        e i numeri di serie dei dispositivi.

        Ci vogliono circa 5 minuti. Puoi saltare i passi per cui non hai l'oggetto giusto.
        """);
    log.AppendLine($"""
        CheCavo - sonda per Windows 0.2
        Avviata: {started:yyyy-MM-dd HH:mm}
        Sistema: {RuntimeInformation.OSDescription} | architettura {RuntimeInformation.OSArchitecture}, programma {RuntimeInformation.ProcessArchitecture}
        Modo: {(automatic ? "automatico" : "guidato")}
        """);

    Console.WriteLine("Leggo le informazioni del PC...");
    log.AppendLine("\n===== Informazioni fisse =====");
    log.AppendLine(OperatingSystem.IsWindows() ? WindowsProbe.Static() : OnlyWindows);
    Save();

    foreach (var (title, ask, wait, optional) in steps)
    {
        Console.WriteLine($"\n=== {title} ===\n{ask}");
        var note = "";
        if (!automatic)
        {
            Console.Write(optional
                ? "Quando hai fatto, scrivi cosa hai collegato (marca, watt, lunghezza: facoltativo) e premi Invio.\nSe non hai l'oggetto, scrivi s e premi Invio per saltare: "
                : "Quando hai fatto, premi Invio: ");
            note = Console.ReadLine()?.Trim() ?? "";
            if (optional && note.Equals("s", StringComparison.OrdinalIgnoreCase))
            {
                log.AppendLine($"\n===== {title}: saltato =====");
                Save();
                continue;
            }
            for (var s = wait; s > 0; s--)
            {
                Console.Write($"\rAspetto {s} secondi, non toccare i cavi...   ");
                Thread.Sleep(1000);
            }
            Console.WriteLine();
        }
        Console.WriteLine("Leggo le porte...");
        log.AppendLine($"\n===== {title} ({DateTime.Now:HH:mm:ss}) =====");
        if (note.Length > 0) log.AppendLine($"Nota: {note}");
        log.Append(Snapshot());
        Save();
    }

    Console.WriteLine("\nLeggo i registri degli eventi...");
    log.AppendLine("\n===== Registri degli eventi =====");
    log.AppendLine(OperatingSystem.IsWindows() ? WindowsProbe.Events(started) : OnlyWindows);
    log.AppendLine("\n===== Fine =====");
    Save();
    Console.WriteLine($"\nFatto. Il file è qui:\n{path}");
    if (!automatic && OperatingSystem.IsWindows())
    {
        try { Process.Start(new ProcessStartInfo("notepad.exe") { ArgumentList = { path }, UseShellExecute = false }); }
        catch (Exception e) { Console.WriteLine($"(Non riesco ad aprire il Blocco note: {e.Message}. Apri il file a mano.)"); }
    }
}
catch (Exception e)
{
    log.AppendLine($"\n===== ERRORE DELLA SONDA =====\n{e}");
    Save();
    Console.WriteLine($"\nC'è stato un errore, ma il file con quello che ho letto è qui:\n{path}\n{e.Message}");
}

if (!automatic)
{
    Console.WriteLine("\nPremi Invio per chiudere.");
    Console.ReadLine();
}

string Snapshot()
{
    var sb = new StringBuilder("\n--- Porte USB (lette direttamente dagli hub) ---\n");
    if (OperatingSystem.IsWindows())
    {
        try { sb.Append(UsbTree.Describe()); }
        catch (Exception e) { sb.AppendLine($"(non leggibili: {e.Message})"); }
    }
    sb.AppendLine(OperatingSystem.IsWindows() ? WindowsProbe.Snapshot() : OnlyWindows);
    return sb.ToString();
}

// On the Mac (dry run) there is nothing to read.

// Rewritten after every step, already cleaned, so closing the window midway still leaves a usable file.
void Save()
{
    var text = Redact.Text(log.ToString(), Environment.UserName, Environment.MachineName);
    foreach (var candidate in new[] { path, Path.Combine(AppContext.BaseDirectory, fileName), Path.Combine(Path.GetTempPath(), fileName) })
    {
        try
        {
            File.WriteAllText(candidate, text, new UTF8Encoding(true));  // the BOM makes every Notepad read it as UTF-8
            path = candidate;
            return;
        }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException) { }
    }
    Console.WriteLine("(Non riesco a scrivere il file da nessuna parte.)");
}

static string Desktop()
{
    var desktop = Environment.GetFolderPath(Environment.SpecialFolder.DesktopDirectory);
    return Directory.Exists(desktop) ? desktop : AppContext.BaseDirectory;
}
