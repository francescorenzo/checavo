using System.Text.RegularExpressions;

namespace Sonda;

/// Removes what could identify the person from the log before it is written.
public static class Redact
{
    // Device instance ids: BUS\HARDWARE\INSTANCE, or BUS#HARDWARE#INSTANCE inside device paths. The last part is
    // the serial number when the device has one; when it has none, Windows makes up an id with '&' in it.
    // Not \b: in ids like SWD\WPDBUSENUM\_??_USBSTOR#...#<serial>#{guid} the bus name follows an underscore.
    static readonly Regex InstanceId = new(
        @"(?<![A-Za-z0-9])(USBSTOR|USB|HID|BTHENUM|SCSI)([\\#])([^\\#\s]+)\2([^\\#\s""',;]+)",
        RegexOptions.IgnoreCase | RegexOptions.CultureInvariant);

    public static string Text(string text, string userName, string machineName)
    {
        // the machine name first: it often contains the user name
        foreach (var name in new[] { machineName, userName })
            if (name.Length >= 3)
                text = Regex.Replace(text, Regex.Escape(name), name == machineName ? "<pc>" : "<utente>", RegexOptions.IgnoreCase);

        return InstanceId.Replace(text, m =>
        {
            var bus = m.Groups[1].Value.ToUpperInvariant();
            var last = m.Groups[4].Value;
            var isSerial = bus is "USBSTOR" or "SCSI" || (!last.Contains('&') && last.Length > 4);
            var sep = m.Groups[2].Value;
            return isSerial ? $"{m.Groups[1].Value}{sep}{m.Groups[3].Value}{sep}<seriale>" : m.Value;
        });
    }
}
