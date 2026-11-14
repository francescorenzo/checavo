using System.Runtime.Versioning;
using Microsoft.Win32.SafeHandles;

namespace CheCavo.Windows;

/// Reads what the app judges, with the same read-only calls as the probe. Every part has its own try:
/// a part that fails ends up in Errors and the others still answer.
public static class Reader
{
    static readonly Guid HubInterface = new("f18a0e88-c30c-11d0-8815-00a0c906bed8");      // GUID_DEVINTERFACE_USB_HUB
    static readonly Guid BatteryInterface = new("72631e54-78a4-11d0-bcf7-00aa00b7b32a");  // GUID_DEVCLASS_BATTERY

    [SupportedOSPlatform("windows")]
    public static Observation Read()
    {
        var errors = new List<string>();
        var devices = new List<UsbDevice>();
        try { devices = UsbOnTypeC(errors); }
        catch (Exception e) { errors.Add($"porte USB: {e.Message}"); }

        var displays = new List<Display>();
        try { displays = Displays(errors); }
        catch (Exception e) { errors.Add($"monitor: {e.Message}"); }

        // If the power state cannot be read, say «da provare» rather than «PC senza batteria».
        var power = new PowerState(HasBattery: true, External: false, ChargeMilliwatts: null);
        try { power = Power(errors); }
        catch (Exception e) { errors.Add($"alimentazione: {e.Message}"); }

        return new(devices, displays, power, errors);
    }

    /// The device name Windows shows. A composite device has a generic parent («Dispositivo USB composito»)
    /// and named functions (USB\VID_x&PID_y&MI_00\…): a function with its own class is the better name.
    public static string NameFor(IReadOnlyList<(string Id, string Name, string Class, string Status)> all, ushort vid, ushort pid)
    {
        var prefix = $@"USB\VID_{vid:X4}&PID_{pid:X4}";
        var mine = all.Where(d => d.Id.StartsWith(prefix, StringComparison.OrdinalIgnoreCase)
                                  && d.Id.Length > prefix.Length && d.Id[prefix.Length] is '\\' or '&'
                                  && d.Name is not ("" or "?")).ToList();
        if (mine.Count == 0) return $"Dispositivo USB {vid:X4}:{pid:X4}";
        return mine.FirstOrDefault(d => !d.Class.Equals("USB", StringComparison.OrdinalIgnoreCase), mine[0]).Name;
    }

    [SupportedOSPlatform("windows")]
    static List<UsbDevice> UsbOnTypeC(List<string> errors)
    {
        var found = new List<(ushort Vid, ushort Pid, UsbSpeed Speed, uint Flags, uint Status, bool IsHub)>();
        foreach (var (path, _, name) in Native.Interfaces(HubInterface))
        {
            try
            {
                // USBView opens hubs for writing; Native.Open falls back to a handle without access, which still answers queries
                using var hub = Native.Open(path, Native.GenericWrite);
                var node = new byte[UsbDecode.NodeInfoSize];
                if (!Query(hub, 258, node, out var err)) { errors.Add($"hub «{name}»: non leggibile (errore Win32 {err})"); continue; }
                for (var i = 1; i <= UsbDecode.PortCount(node); i++)
                {
                    var pc = Indexed(UsbDecode.PortConnectorSize, i);
                    if (!Query(hub, 278, pc, out _) || !UsbDecode.PortConnector(pc).IsTypeC) continue;
                    var ci = Indexed(UsbDecode.ConnectionExSize, i);
                    if (!Query(hub, 274, ci, out _)) continue;
                    var c = UsbDecode.Connection(ci);
                    if (c.Status == 0) continue;

                    var v2 = Indexed(UsbDecode.ConnectionExV2Size, i);
                    BitConverter.GetBytes((uint)UsbDecode.ConnectionExV2Size).CopyTo(v2, 4);
                    BitConverter.GetBytes(4u).CopyTo(v2, 8);  // Usb300: the caller understands USB 3 answers
                    var flags = Query(hub, 279, v2, out _) ? UsbDecode.ConnectionV2(v2).FlagBits : 0;
                    found.Add((c.Vid, c.Pid, UsbDecode.Speed(c.Speed, flags), flags, c.Status, c.IsHub));
                }
            }
            catch (Exception e) { errors.Add($"hub «{name}»: {e.Message}"); }
        }
        if (found.Count == 0) return [];

        var all = Native.Devices();
        return found.Select(f => new UsbDevice(NameFor(all, f.Vid, f.Pid), f.Vid, f.Pid, f.Speed,
            SuperSpeedCapable: (f.Flags & 2) != 0, SuperSpeedPlusCapable: (f.Flags & 8) != 0, f.Status, f.IsHub)).ToList();
    }

    [SupportedOSPlatform("windows")]
    static List<Display> Displays(List<string> errors)
    {
        const uint ActivePaths = 2;  // QDC_ONLY_ACTIVE_PATHS
        byte[] paths = [], modes = [];
        uint np = 0;
        for (var attempt = 0; ; attempt++)
        {
            var err = Native.GetDisplayConfigBufferSizes(ActivePaths, out np, out var nm);
            if (err != 0) throw new IOException($"errore {err}");
            paths = new byte[np * WinDecode.PathInfoSize];
            modes = new byte[nm * WinDecode.ModeInfoSize];
            err = Native.QueryDisplayConfig(ActivePaths, ref np, paths, ref nm, modes, IntPtr.Zero);
            if (err == 0) break;
            if (err != 122 /* ERROR_INSUFFICIENT_BUFFER: a monitor came or went meanwhile */ || attempt == 2) throw new IOException($"errore {err}");
        }
        var list = new List<Display>();
        for (var i = 0; i < np; i++)
        {
            var target = WinDecode.TargetNameRequest(paths, i);
            var err = Native.DisplayConfigGetDeviceInfo(target);
            if (err != 0) { errors.Add($"monitor {i + 1}: non leggibile (errore {err})"); continue; }
            var t = WinDecode.Target(target);
            var (w, h) = WinDecode.TargetSize(modes, WinDecode.PathModeIndex(paths, i));
            var display = t.Name.Length > 0 ? t.Name : WinDecode.OutputTechnology(t.Technology);
            list.Add(new(display, t.Technology, w, h, WinDecode.PathRefresh(paths, i)));
        }
        return list;
    }

    [SupportedOSPlatform("windows")]
    static PowerState Power(List<string> errors)
    {
        if (!Native.GetSystemPowerStatus(out var ps)) throw new IOException("stato non leggibile");
        bool hasBattery = (ps.BatteryFlag & 128) == 0;  // 128 = no system battery
        bool external = ps.ACLineStatus == 1;
        if (!hasBattery) return new(false, external, null);

        int? charge = null;
        foreach (var (path, _, name) in Native.Interfaces(BatteryInterface))
        {
            try
            {
                using var h = Native.Open(path, Native.GenericRead);
                var tag = new byte[4];
                if (!Native.Query(h, WinDecode.BatteryIoctl(0x10), new byte[4] /* do not wait */, tag, out var err))
                { errors.Add($"batteria «{name}»: non leggibile (errore Win32 {err})"); continue; }
                if (BitConverter.ToUInt32(tag) == 0) continue;  // slot without a battery
                var wait = new byte[20];  // BATTERY_WAIT_STATUS: the tag, then a zero timeout and no conditions
                tag.CopyTo(wait, 0);
                var status = new byte[WinDecode.BatteryStatusSize];
                if (!Native.Query(h, WinDecode.BatteryIoctl(0x13), wait, status, out err))
                { errors.Add($"batteria «{name}»: stato non leggibile (errore Win32 {err})"); continue; }
                if (WinDecode.ChargeMilliwatts(status) is { } mw) charge = (charge ?? 0) + mw;
            }
            catch (Exception e) { errors.Add($"batteria «{name}»: {e.Message}"); }
        }
        return new(true, external, charge);
    }

    static byte[] Indexed(int size, int port)
    {
        var b = new byte[size];
        BitConverter.GetBytes((uint)port).CopyTo(b, 0);  // ConnectionIndex
        return b;
    }

    [SupportedOSPlatform("windows")]
    static bool Query(SafeFileHandle h, uint function, byte[] buffer, out int error) =>
        Native.Query(h, UsbDecode.Ioctl(function), buffer, buffer, out error);
}
