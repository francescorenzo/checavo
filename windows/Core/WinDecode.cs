using System.Buffers.Binary;
using System.Text;
using System.Text.RegularExpressions;

namespace CheCavo.Windows;

public readonly record struct DisplayTarget(string Name, uint Technology, uint Connector, string Path);

/// Reads the answers of the battery driver and of QueryDisplayConfig, and formats what Windows returns.
/// Pure functions, so they are tested on the Mac too.
public static class WinDecode
{
    public const int BatteryStatusSize = 16;        // BATTERY_STATUS
    public const int BatteryInformationSize = 36;   // BATTERY_INFORMATION
    public const int PathInfoSize = 72;             // DISPLAYCONFIG_PATH_INFO
    public const int ModeInfoSize = 64;             // DISPLAYCONFIG_MODE_INFO
    public const int TargetNameSize = 420;          // DISPLAYCONFIG_TARGET_DEVICE_NAME

    const uint Unknown = 0xFFFFFFFF;                // BATTERY_UNKNOWN_CAPACITY, _VOLTAGE
    const int UnknownRate = unchecked((int)0x80000000);

    static uint U32(byte[] b, int at) => BinaryPrimitives.ReadUInt32LittleEndian(b.AsSpan(at));

    /// CTL_CODE(FILE_DEVICE_BATTERY, function, METHOD_BUFFERED, FILE_READ_ACCESS)
    public static uint BatteryIoctl(uint function) => (0x29u << 16) | (1u << 14) | (function << 2);

    public static string Battery(byte[] s)
    {
        var state = U32(s, 0);
        var capacity = U32(s, 4);
        var voltage = U32(s, 8);
        var rate = BinaryPrimitives.ReadInt32LittleEndian(s.AsSpan(12));
        string YesNo(uint bit) => (state & bit) != 0 ? "sì" : "no";
        string Known(uint v) => v == Unknown ? "?" : v.ToString();
        var charge = rate == UnknownRate ? "?" : Math.Max(rate, 0).ToString();
        var drain = rate == UnknownRate ? "?" : Math.Max(-(long)rate, 0).ToString();
        return $"alimentazione esterna: {YesNo(1)} | in carica: {YesNo(4)} | in scarica: {YesNo(2)} | ricarica {charge} mW | scarica {drain} mW | tensione {Known(voltage)} mV | carica residua {Known(capacity)} mWh";
    }

    public static uint FullChargedCapacity(byte[] info) => U32(info, 16);

    /// The power entering the battery, or null when it is not charging or the driver does not know.
    public static int? ChargeMilliwatts(byte[] status)
    {
        var rate = BinaryPrimitives.ReadInt32LittleEndian(status.AsSpan(12));
        return rate > 0 ? rate : null;  // BATTERY_UNKNOWN_RATE is negative
    }

    /// The target of path i: its mode index (byte 32) and its refresh rate (numerator and denominator at 48 and 52).
    public static uint PathModeIndex(byte[] paths, int i) => U32(paths, i * PathInfoSize + 32);

    public static double PathRefresh(byte[] paths, int i)
    {
        var den = U32(paths, i * PathInfoSize + 52);
        return den == 0 ? 0 : (double)U32(paths, i * PathInfoSize + 48) / den;
    }

    /// The active size of a target mode (DISPLAYCONFIG_MODE_INFO_TYPE_TARGET = 2), or (0, 0) for anything else.
    public static (int W, int H) TargetSize(byte[] modes, uint index)
    {
        if (index >= modes.Length / ModeInfoSize) return (0, 0);
        var at = (int)index * ModeInfoSize;
        return U32(modes, at) == 2 ? ((int)U32(modes, at + 40), (int)U32(modes, at + 44)) : (0, 0);
    }

    public static string OutputTechnology(uint code) => code switch
    {
        0 => "VGA", 1 => "S-Video", 2 => "composito", 3 => "component", 4 => "DVI", 5 => "HDMI", 6 => "LVDS",
        8 => "D-Jpn", 9 => "SDI", 10 => "DisplayPort esterno", 11 => "DisplayPort integrato", 12 => "UDI esterno",
        13 => "UDI integrato", 14 => "dongle SDTV", 15 => "Miracast", 16 => "indiretto via cavo",
        17 => "indiretto virtuale", 18 => "DisplayPort dentro USB4", 0x80000000 => "schermo interno",
        0xFFFFFFFF => "altro", _ => $"codice {code}",
    };

    /// DISPLAYCONFIG_DEVICE_INFO_GET_TARGET_NAME for the target of path i (its adapterId and id start at byte 20).
    public static byte[] TargetNameRequest(byte[] paths, int i)
    {
        var r = new byte[TargetNameSize];
        BitConverter.GetBytes(2u).CopyTo(r, 0);
        BitConverter.GetBytes((uint)TargetNameSize).CopyTo(r, 4);
        Array.Copy(paths, i * PathInfoSize + 20, r, 8, 12);
        return r;
    }

    public static DisplayTarget Target(byte[] b) => new(
        Name: Wide(b, 36, 64), Technology: U32(b, 24), Connector: U32(b, 32), Path: Wide(b, 164, 128));

    static string Wide(byte[] b, int at, int chars)
    {
        var s = Encoding.Unicode.GetString(b, at, chars * 2);
        var end = s.IndexOf('\0');
        return end >= 0 ? s[..end] : s;
    }

    static readonly Regex TypeC = new("USBC000|PNP0CA0|UCM|UCSI|Type-?C|USB4|Thunderbolt", RegexOptions.IgnoreCase);

    public static bool IsTypeCRelated(string text) => TypeC.IsMatch(text);

    /// What Device Manager would say: a problem code wins, then whether the driver started (DN_STARTED).
    public static string DeviceStatus(uint status, uint problem) =>
        problem != 0 ? $"problema {problem}" : (status & 0x8) != 0 ? "OK" : "fermo";

    public static string Value(object? v) => v switch
    {
        null => "",
        byte[] bytes => Convert.ToHexString(bytes),
        string[] list => string.Join("; ", list),
        _ => v.ToString() ?? "",
    };

    public static string Short(string? m)
    {
        if (m is null) return "(senza testo)";
        m = Regex.Replace(m, @"\s+", " ").Trim();
        return m.Length > 300 ? m[..300] + "..." : m;
    }
}
