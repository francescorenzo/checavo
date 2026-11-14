using System.Diagnostics;
using System.Diagnostics.Eventing.Reader;
using System.Runtime.Versioning;
using System.Security;
using System.Text;
using System.Text.RegularExpressions;
using Microsoft.Win32;

namespace Sonda;

/// What the probe reads besides the USB ports: system, drivers, registry, battery, monitors, devices, event logs.
/// Read directly from Windows, without PowerShell. Each section catches its own errors so one failure does not hide the rest.
[SupportedOSPlatform("windows")]
public static class WindowsProbe
{
    static readonly Guid BatteryInterface = new("72631e54-78a4-11d0-bcf7-00aa00b7b32a");  // GUID_DEVCLASS_BATTERY
    static readonly Regex DriverFile = new("^(Ucm|Usb4|UsbXhci|Ucx|UsbHub3|Tbt|Thunderbolt)", RegexOptions.IgnoreCase);
    static readonly Regex UsbLog = new("USB|Ucm|Ucsi|TypeC|USB4|Thunderbolt", RegexOptions.IgnoreCase);
    static readonly Regex SystemProvider = new("USB|Ucm|Ucsi|USB4|Thunderbolt|Kernel-Power|ACPI|Battery", RegexOptions.IgnoreCase);

    static void Section(StringBuilder sb, string title, Action body)
    {
        sb.AppendLine($"\n--- {title} ---");
        try { body(); }
        catch (Exception e) { sb.AppendLine($"(non leggibile: {e.Message})"); }
    }

    /// Read once: what the PC is, which USB-C drivers it has, how UCSI is set up.
    public static string Static()
    {
        var sb = new StringBuilder();
        Section(sb, "Sistema", () =>
        {
            using var cv = Registry.LocalMachine.OpenSubKey(@"SOFTWARE\Microsoft\Windows NT\CurrentVersion")
                ?? throw new IOException("chiave della versione assente");
            sb.AppendLine($"Windows: {cv.GetValue("ProductName")} {cv.GetValue("DisplayVersion")}, build {cv.GetValue("CurrentBuild")}.{cv.GetValue("UBR")} (dalla build 22000 è Windows 11)");
            using var bios = Registry.LocalMachine.OpenSubKey(@"HARDWARE\DESCRIPTION\System\BIOS");
            sb.AppendLine($"PC: {bios?.GetValue("SystemManufacturer")} {bios?.GetValue("SystemProductName")} | famiglia {bios?.GetValue("SystemFamily")} | BIOS {bios?.GetValue("BIOSVersion")} del {bios?.GetValue("BIOSReleaseDate")}");
            using var cpu = Registry.LocalMachine.OpenSubKey(@"HARDWARE\DESCRIPTION\System\CentralProcessor\0");
            sb.AppendLine($"Processore: {cpu?.GetValue("ProcessorNameString")}");
        });
        Section(sb, "Driver USB-C, USB4, Thunderbolt e USB", () =>
        {
            var files = Directory.GetFiles(Path.Combine(Environment.SystemDirectory, "drivers"), "*.sys")
                .Where(f => DriverFile.IsMatch(Path.GetFileName(f))).Order(StringComparer.OrdinalIgnoreCase).ToList();
            if (files.Count == 0) sb.AppendLine("nessuno");
            foreach (var f in files) sb.AppendLine($"{Path.GetFileName(f)}: versione {FileVersionInfo.GetVersionInfo(f).FileVersion}");
        });
        Section(sb, "Dispositivi USB-C, UCSI, USB4 e Thunderbolt (tutte le proprietà)", () =>
        {
            var devs = TypeCDevices(Native.Devices());
            if (devs.Count == 0) sb.AppendLine("nessuno: Windows non vede un controller USB-C (UCSI) né USB4");
            foreach (var d in devs)
            {
                sb.AppendLine($"== {d.Name} | classe {d.Class} | stato {d.Status}");
                sb.AppendLine($"   {d.Id}");
                using var key = Registry.LocalMachine.OpenSubKey($@"SYSTEM\CurrentControlSet\Enum\{d.Id}");
                if (key is null) sb.AppendLine("   (nessuna chiave nel registro)");
                else Dump(sb, key, "   ");
            }
        });
        Section(sb, "Registro: UCSI e driver USB-C", () =>
        {
            foreach (var k in new[] { @"SYSTEM\CurrentControlSet\Enum\ACPI\USBC000", @"SYSTEM\CurrentControlSet\Services\UcmUcsiCx",
                                      @"SYSTEM\CurrentControlSet\Services\UcmUcsiAcpiClient", @"SYSTEM\CurrentControlSet\Services\UcmCx0101" })
            {
                using var key = Registry.LocalMachine.OpenSubKey(k);
                if (key is null) sb.AppendLine($@"HKEY_LOCAL_MACHINE\{k}: assente");
                else Dump(sb, key, "");
            }
        });
        return sb.ToString();
    }

    /// The key, its values and every subkey below it. Values named like a serial number are left out.
    static void Dump(StringBuilder sb, RegistryKey key, string indent)
    {
        sb.AppendLine($"{indent}[{key.Name}]");
        foreach (var n in key.GetValueNames())
            if (!n.Contains("Serial", StringComparison.OrdinalIgnoreCase))
                sb.AppendLine($"{indent}   {n} = {WinDecode.Value(key.GetValue(n, null, RegistryValueOptions.DoNotExpandEnvironmentNames))}");
        foreach (var s in key.GetSubKeyNames())
        {
            try
            {
                using var sub = key.OpenSubKey(s);
                if (sub is not null) Dump(sb, sub, indent);
            }
            catch (Exception e) when (e is SecurityException or UnauthorizedAccessException or IOException)
            {
                sb.AppendLine($@"{indent}[{key.Name}\{s}] non leggibile");
            }
        }
    }

    static List<(string Id, string Name, string Class, string Status)> TypeCDevices(List<(string Id, string Name, string Class, string Status)> all) =>
        all.Where(d => WinDecode.IsTypeCRelated($"{d.Id} {d.Name} {d.Class}")).ToList();

    /// Read at every step: power, monitors and the devices Windows sees right now.
    public static string Snapshot()
    {
        var sb = new StringBuilder();
        Section(sb, "Batteria e alimentazione", () => Battery(sb));
        Section(sb, "Monitor", () => Monitors(sb));
        var devices = new List<(string Id, string Name, string Class, string Status)>();
        Section(sb, "Dispositivi USB-C, UCSI, USB4 e Thunderbolt", () =>
        {
            devices = Native.Devices();
            var devs = TypeCDevices(devices);
            if (devs.Count == 0) sb.AppendLine("nessuno");
            foreach (var d in devs) sb.AppendLine($"{d.Status} | {d.Class} | {d.Name} | {d.Id}");
        });
        Section(sb, "Dispositivi USB presenti", () =>
        {
            foreach (var d in devices.Where(d => d.Id.StartsWith(@"USB\VID_", StringComparison.OrdinalIgnoreCase))
                                     .OrderBy(d => d.Id, StringComparer.OrdinalIgnoreCase))
                sb.AppendLine($"{d.Status} | {d.Class} | {d.Name} | {d.Id}");
        });
        return sb.ToString();
    }

    static void Battery(StringBuilder sb)
    {
        if (Native.GetSystemPowerStatus(out var ps))
            sb.AppendLine($"Windows: alimentazione esterna {ps.ACLineStatus switch { 0 => "no", 1 => "sì", _ => "?" }} | carica {(ps.BatteryLifePercent == 255 ? "?" : ps.BatteryLifePercent)}%");
        var batteries = Native.Interfaces(BatteryInterface);
        if (batteries.Count == 0) sb.AppendLine("nessuna batteria (PC fisso?)");
        foreach (var (path, _, name) in batteries)
        {
            using var h = Native.Open(path, Native.GenericRead);
            var tag = new byte[4];
            if (!Native.Query(h, WinDecode.BatteryIoctl(0x10), new byte[4] /* do not wait */, tag, out var err))
            {
                sb.AppendLine($"{name}: non leggibile (errore Win32 {err})");
                continue;
            }
            if (BitConverter.ToUInt32(tag) == 0) { sb.AppendLine($"{name}: nessuna batteria inserita"); continue; }

            var wait = new byte[20];  // BATTERY_WAIT_STATUS: the tag, then a zero timeout and no conditions
            tag.CopyTo(wait, 0);
            var status = new byte[WinDecode.BatteryStatusSize];
            sb.AppendLine(Native.Query(h, WinDecode.BatteryIoctl(0x13), wait, status, out err)
                ? WinDecode.Battery(status) : $"{name}: stato non leggibile (errore Win32 {err})");

            var query = new byte[12];  // BATTERY_QUERY_INFORMATION: the tag, then level BatteryInformation (0)
            tag.CopyTo(query, 0);
            var info = new byte[WinDecode.BatteryInformationSize];
            if (Native.Query(h, WinDecode.BatteryIoctl(0x11), query, info, out _))
                sb.AppendLine($"capacità piena: {WinDecode.FullChargedCapacity(info)} mWh");
        }
    }

    static void Monitors(StringBuilder sb)
    {
        const uint ActivePaths = 2;  // QDC_ONLY_ACTIVE_PATHS
        byte[] paths = [];
        uint np = 0;
        for (var attempt = 0; ; attempt++)
        {
            var err = Native.GetDisplayConfigBufferSizes(ActivePaths, out np, out var nm);
            if (err != 0) throw new IOException($"errore {err}");
            paths = new byte[np * WinDecode.PathInfoSize];
            var modes = new byte[nm * WinDecode.ModeInfoSize];
            err = Native.QueryDisplayConfig(ActivePaths, ref np, paths, ref nm, modes, IntPtr.Zero);
            if (err == 0) break;
            if (err != 122 /* ERROR_INSUFFICIENT_BUFFER: a monitor came or went meanwhile */ || attempt == 2) throw new IOException($"errore {err}");
        }
        if (np == 0) sb.AppendLine("nessun monitor attivo");
        for (var i = 0; i < np; i++)
        {
            var target = WinDecode.TargetNameRequest(paths, i);
            var err = Native.DisplayConfigGetDeviceInfo(target);
            if (err != 0) { sb.AppendLine($"monitor {i + 1}: non leggibile (errore {err})"); continue; }
            var t = WinDecode.Target(target);
            sb.AppendLine($"{t.Name} | collegamento: {WinDecode.OutputTechnology(t.Technology)} | connettore {t.Connector} | {t.Path}");
        }
    }

    /// Read at the end: what the USB-C drivers wrote while the user plugged cables in.
    public static string Events(DateTime since)
    {
        var sb = new StringBuilder();
        var session = EventLogSession.GlobalSession;
        Section(sb, "Registri degli eventi USB, USB-C e USB4 (ultimi 40 per registro)", () =>
        {
            var any = false;
            foreach (var log in session.GetLogNames().Where(n => UsbLog.IsMatch(n)).Order(StringComparer.OrdinalIgnoreCase))
            {
                long count;
                try { count = session.GetLogInformation(log, PathType.LogName).RecordCount ?? 0; }
                catch (Exception) { continue; }  // analytic and debug logs cannot be read this way
                if (count == 0) continue;
                any = true;
                sb.AppendLine($"== {log} ({count} eventi)");
                // One log that fails must not hide the others.
                try
                {
                    foreach (var line in Read(new EventLogQuery(log, PathType.LogName) { ReverseDirection = true }, 40, _ => true,
                                 e => $"{e.TimeCreated:yyyy-MM-dd HH:mm:ss} [{e.Id}] {Message(e)}"))
                        sb.AppendLine(line);
                }
                catch (Exception e) { sb.AppendLine($"(non leggibile: {e.Message})"); }
            }
            if (!any) sb.AppendLine("nessun registro con eventi");
        });
        Section(sb, "Dispositivi aggiunti o cambiati durante la sonda (Kernel-PnP)", () =>
        {
            var query = new EventLogQuery("Microsoft-Windows-Kernel-PnP/Configuration", PathType.LogName,
                $"*[System[TimeCreated[@SystemTime>='{since.ToUniversalTime():yyyy-MM-ddTHH:mm:ss.fffZ}']]]");
            var lines = Read(query, 2000, _ => true, e => $"{e.TimeCreated:HH:mm:ss} [{e.Id}] {Message(e)}");
            if (lines.Count == 0) sb.AppendLine("nessuno");
            foreach (var l in lines) sb.AppendLine(l);
        });
        Section(sb, "Registro di sistema, ultimi 2 giorni (USB, USB-C, alimentazione)", () =>
        {
            var query = new EventLogQuery("System", PathType.LogName, "*[System[TimeCreated[timediff(@SystemTime) <= 172800000]]]")
                { ReverseDirection = true };
            foreach (var l in Read(query, 3000, e => SystemProvider.IsMatch(e.ProviderName ?? ""),
                         e => $"{e.TimeCreated:yyyy-MM-dd HH:mm:ss} {e.ProviderName} [{e.Id}] {Message(e)}").Take(80))
                sb.AppendLine(l);
        });
        return sb.ToString();
    }

    /// Up to max events from the query, formatted, keeping those that pass the filter.
    static List<string> Read(EventLogQuery query, int max, Func<EventRecord, bool> keep, Func<EventRecord, string> line)
    {
        var lines = new List<string>();
        using var reader = new EventLogReader(query);
        for (var n = 0; n < max; n++)
        {
            using var e = reader.ReadEvent();
            if (e is null) break;
            if (keep(e)) lines.Add(line(e));
        }
        return lines;
    }

    /// The event's text, or its raw values when Windows has no text for it.
    static string Message(EventRecord e)
    {
        string? text = null;
        try { text = e.FormatDescription(); } catch (EventLogException) { }
        return WinDecode.Short(text ?? (e.Properties.Count > 0 ? string.Join(" ", e.Properties.Select(p => p.Value)) : null));
    }
}
