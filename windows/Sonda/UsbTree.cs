using System.Runtime.Versioning;
using System.Text;
using Microsoft.Win32.SafeHandles;

namespace Sonda;

/// Walks every USB hub and port the way Microsoft's USBView does, with read-only queries.
/// It tells which ports are USB-C and how fast each connected device runs.
[SupportedOSPlatform("windows")]
public static class UsbTree
{
    static readonly Guid HubInterface = new("f18a0e88-c30c-11d0-8815-00a0c906bed8");  // GUID_DEVINTERFACE_USB_HUB

    public static string Describe()
    {
        var sb = new StringBuilder();
        var hubs = Hubs();
        if (hubs.Count == 0) sb.AppendLine("Nessun hub USB trovato.");
        foreach (var (path, id, name) in hubs)
        {
            sb.AppendLine($"Hub: {name} [{id}]");
            sb.AppendLine($"  percorso: {path}");
            try { DescribeHub(path, sb); }
            catch (Exception e) { sb.AppendLine($"  errore: {e.Message}"); }
        }
        return sb.ToString();
    }

    static void DescribeHub(string path, StringBuilder sb)
    {
        using var hub = Open(path);
        var node = new byte[UsbDecode.NodeInfoSize];
        if (!Query(hub, 258, node, out var err)) { sb.AppendLine($"  non leggibile (errore Win32 {err})"); return; }
        var ports = UsbDecode.PortCount(node);
        sb.AppendLine($"  porte: {ports}");
        for (var i = 1; i <= ports; i++)
        {
            var line = new StringBuilder($"  porta {i}:");

            var pc = Indexed(UsbDecode.PortConnectorSize, i);
            if (Query(hub, 278, pc, out err))
            {
                var p = UsbDecode.PortConnector(pc);
                line.Append(p.IsTypeC ? " USB-C" : " non USB-C");
                line.Append(p.UserConnectable ? ", accessibile" : ", interna");
                if (p.CompanionPort != 0) line.Append($" | compagna: porta {p.CompanionPort} di {p.CompanionHub}");
                line.Append($" | grezzo {Hex(pc, 16)}");
            }
            else line.Append($" proprietà del connettore non leggibili (errore Win32 {err})");
            sb.AppendLine(line.ToString());

            var ci = Indexed(UsbDecode.ConnectionExSize, i);
            if (Query(hub, 274, ci, out err))
            {
                var c = UsbDecode.Connection(ci);
                if (c.Status == 0) sb.AppendLine("     vuota");
                else
                {
                    sb.Append($"     {UsbDecode.StatusName(c.Status)}");
                    if (c.Vid != 0 || c.Pid != 0)
                        sb.Append($": VID {c.Vid:X4} PID {c.Pid:X4}, dichiara USB {c.BcdUsb >> 8:X}.{c.BcdUsb & 0xFF:X2}, {UsbDecode.SpeedName(c.Speed)}{(c.IsHub ? ", è un hub" : "")}");
                    sb.AppendLine($" | grezzo {Hex(ci, 35)}");
                }
            }
            else sb.AppendLine($"     collegamento non leggibile (errore Win32 {err})");

            var v2 = Indexed(UsbDecode.ConnectionExV2Size, i);
            BitConverter.GetBytes((uint)UsbDecode.ConnectionExV2Size).CopyTo(v2, 4);
            BitConverter.GetBytes(4u).CopyTo(v2, 8);  // Usb300: the caller understands USB 3 answers
            if (Query(hub, 279, v2, out err))
            {
                var v = UsbDecode.ConnectionV2(v2);
                sb.AppendLine($"     protocolli della porta: {v.Protocols} | dispositivo: {v.Flags}");
            }
            else sb.AppendLine($"     dati USB 3 non leggibili (errore Win32 {err})");
        }
    }

    static byte[] Indexed(int size, int port)
    {
        var b = new byte[size];
        BitConverter.GetBytes((uint)port).CopyTo(b, 0);  // ConnectionIndex
        return b;
    }

    static string Hex(byte[] b, int count) => Convert.ToHexString(b, 0, Math.Min(count, b.Length));

    static bool Query(SafeFileHandle h, uint function, byte[] buffer, out int error) =>
        Native.Query(h, UsbDecode.Ioctl(function), buffer, buffer, out error);

    // USBView opens hubs for writing; Native.Open falls back to a handle without access, which still answers queries
    static SafeFileHandle Open(string path) => Native.Open(path, Native.GenericWrite);

    static List<(string Path, string Id, string Name)> Hubs() => Native.Interfaces(HubInterface);
}
