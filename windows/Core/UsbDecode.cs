using System.Buffers.Binary;
using System.Text;

namespace CheCavo.Windows;

public readonly record struct UsbConnection(uint Status, byte Speed, ushort Vid, ushort Pid, ushort BcdUsb, bool IsHub);
public readonly record struct UsbConnectionV2(string Protocols, string Flags, uint ProtocolBits, uint FlagBits);
public readonly record struct UsbPortConnector(
    bool UserConnectable, bool DebugCapable, bool MultipleCompanions, bool IsTypeC,
    int CompanionIndex, int CompanionPort, string CompanionHub);

/// Reads the answers of the USB hub driver. Offsets follow usbioctl.h, whose structures are packed to 1 byte.
public static class UsbDecode
{
    public const int NodeInfoSize = 76;                  // USB_NODE_INFORMATION
    public const int ConnectionExSize = 35 + 32 * 11;    // USB_NODE_CONNECTION_INFORMATION_EX + room for 32 pipes
    public const int ConnectionExV2Size = 16;            // USB_NODE_CONNECTION_INFORMATION_EX_V2
    public const int PortConnectorSize = 16 + 2 * 512;   // USB_PORT_CONNECTOR_PROPERTIES + the companion hub name

    /// CTL_CODE(FILE_DEVICE_USB, function, METHOD_BUFFERED, FILE_ANY_ACCESS)
    public static uint Ioctl(uint function) => (0x22u << 16) | (function << 2);

    static ushort U16(byte[] b, int at) => BinaryPrimitives.ReadUInt16LittleEndian(b.AsSpan(at));
    static uint U32(byte[] b, int at) => BinaryPrimitives.ReadUInt32LittleEndian(b.AsSpan(at));

    /// NodeType (4) + USB_HUB_DESCRIPTOR: length, type, bNumberOfPorts
    public static int PortCount(byte[] b) => b[6];

    public static UsbConnection Connection(byte[] b) => new(
        Status: U32(b, 31), Speed: b[23], Vid: U16(b, 12), Pid: U16(b, 14), BcdUsb: U16(b, 6), IsHub: b[24] != 0);

    public static UsbConnectionV2 ConnectionV2(byte[] b) => new(
        Protocols: Bits(U32(b, 8), "USB 1.1", "USB 2.0", "USB 3"),
        Flags: Bits(U32(b, 12), "funziona a SuperSpeed o più", "regge SuperSpeed o più",
                    "funziona a SuperSpeedPlus o più", "regge SuperSpeedPlus o più"),
        ProtocolBits: U32(b, 8), FlagBits: U32(b, 12));

    /// The speed byte only says «SuperSpeed or more»; the V2 flags (bit 0 runs at SuperSpeed, bit 2 at SuperSpeedPlus) tell the rest.
    public static UsbSpeed Speed(byte speed, uint flagBits) =>
        (flagBits & 4) != 0 ? UsbSpeed.SuperPlus
        : speed >= 3 || (flagBits & 1) != 0 ? UsbSpeed.Super
        : (UsbSpeed)speed;

    public static UsbPortConnector PortConnector(byte[] b)
    {
        var props = U32(b, 8);
        var name = Encoding.Unicode.GetString(b, 16, b.Length - 16);
        var end = name.IndexOf('\0');
        return new(
            UserConnectable: (props & 1) != 0, DebugCapable: (props & 2) != 0,
            MultipleCompanions: (props & 4) != 0, IsTypeC: (props & 8) != 0,
            CompanionIndex: U16(b, 12), CompanionPort: U16(b, 14),
            CompanionHub: end >= 0 ? name[..end] : name);
    }

    /// Names the set bits; bits without a name are shown in hex so nothing is lost.
    static string Bits(uint value, params string[] names)
    {
        var parts = names.Where((_, i) => (value & (1u << i)) != 0).ToList();
        var rest = value & ~((1u << names.Length) - 1);
        if (rest != 0) parts.Add($"altri bit 0x{rest:X}");
        return parts.Count == 0 ? "nessuno" : string.Join(", ", parts);
    }

    public static string StatusName(uint s) => s switch
    {
        0 => "nessun dispositivo", 1 => "collegato", 2 => "enumerazione fallita", 3 => "guasto generico",
        4 => "sovracorrente", 5 => "corrente insufficiente", 6 => "banda insufficiente", 7 => "troppi hub in fila",
        8 => "su un hub vecchio", 9 => "in enumerazione", 10 => "in reset", _ => $"stato {s}",
    };

    public static string SpeedName(byte s) => s switch
    {
        0 => "Low Speed (USB 1, 1,5 Mb/s)", 1 => "Full Speed (USB 1, 12 Mb/s)", 2 => "High Speed (USB 2, 480 Mb/s)",
        3 => "SuperSpeed o più (USB 3, 5 Gb/s o più)", _ => $"velocità {s}",
    };
}
