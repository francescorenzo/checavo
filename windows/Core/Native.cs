using System.Runtime.InteropServices;
using System.Runtime.Versioning;
using System.Text;
using Microsoft.Win32.SafeHandles;

namespace CheCavo.Windows;

/// The Windows calls the probe makes. All of them only read.
[SupportedOSPlatform("windows")]
public static class Native
{
    public const uint GenericRead = 0x80000000, GenericWrite = 0x40000000;

    /// Device interfaces of one kind (hubs, batteries): their path, instance ID and name.
    public static List<(string Path, string Id, string Name)> Interfaces(Guid kind)
    {
        var list = new List<(string, string, string)>();
        var set = SetupDiGetClassDevsW(ref kind, IntPtr.Zero, IntPtr.Zero, 0x2 | 0x10 /* PRESENT | DEVICEINTERFACE */);
        if (set == new IntPtr(-1)) throw new IOException($"elenco non disponibile (errore Win32 {Marshal.GetLastWin32Error()})");
        try
        {
            for (uint i = 0; ; i++)
            {
                var iface = new SP_DEVICE_INTERFACE_DATA { cbSize = Marshal.SizeOf<SP_DEVICE_INTERFACE_DATA>() };
                if (!SetupDiEnumDeviceInterfaces(set, IntPtr.Zero, ref kind, i, ref iface)) break;
                var info = new SP_DEVINFO_DATA { cbSize = Marshal.SizeOf<SP_DEVINFO_DATA>() };
                SetupDiGetDeviceInterfaceDetailW(set, ref iface, IntPtr.Zero, 0, out var needed, ref info);
                if (needed == 0) continue;
                var detail = Marshal.AllocHGlobal((int)needed);
                try
                {
                    Marshal.WriteInt32(detail, 8);  // cbSize of SP_DEVICE_INTERFACE_DETAIL_DATA_W in a 64-bit process
                    if (!SetupDiGetDeviceInterfaceDetailW(set, ref iface, detail, needed, out _, ref info)) continue;
                    var path = Marshal.PtrToStringUni(detail + 4) ?? "";
                    list.Add((path, InstanceId(set, ref info), Property(set, ref info, 0xC /* FRIENDLYNAME */, 0 /* DEVICEDESC */)));
                }
                finally { Marshal.FreeHGlobal(detail); }
            }
        }
        finally { SetupDiDestroyDeviceInfoList(set); }
        return list;
    }

    /// Every device Windows sees right now, like Get-PnpDevice -PresentOnly.
    public static List<(string Id, string Name, string Class, string Status)> Devices()
    {
        var list = new List<(string, string, string, string)>();
        var set = SetupDiGetClassDevsAll(IntPtr.Zero, IntPtr.Zero, IntPtr.Zero, 0x2 | 0x4 /* PRESENT | ALLCLASSES */);
        if (set == new IntPtr(-1)) throw new IOException($"elenco dei dispositivi non disponibile (errore Win32 {Marshal.GetLastWin32Error()})");
        try
        {
            var info = new SP_DEVINFO_DATA { cbSize = Marshal.SizeOf<SP_DEVINFO_DATA>() };
            for (uint i = 0; SetupDiEnumDeviceInfo(set, i, ref info); i++)
            {
                var status = CM_Get_DevNode_Status(out var flags, out var problem, info.DevInst, 0) == 0
                    ? WinDecode.DeviceStatus(flags, problem) : "sconosciuto";
                list.Add((InstanceId(set, ref info), Property(set, ref info, 0xC, 0), Property(set, ref info, 0x7 /* CLASS */), status));
            }
        }
        finally { SetupDiDestroyDeviceInfoList(set); }
        return list;
    }

    static string InstanceId(IntPtr set, ref SP_DEVINFO_DATA info)
    {
        var buf = new char[512];
        return SetupDiGetDeviceInstanceIdW(set, ref info, buf, buf.Length, out _) ? new string(buf).TrimEnd('\0') : "?";
    }

    /// The first of the given registry properties the device has, as text.
    static string Property(IntPtr set, ref SP_DEVINFO_DATA info, params uint[] props)
    {
        var buf = new byte[1024];
        foreach (var prop in props)
            if (SetupDiGetDeviceRegistryPropertyW(set, ref info, prop, out _, buf, buf.Length, out _))
                return Encoding.Unicode.GetString(buf).Split('\0')[0];
        return "?";
    }

    /// Opens a device for queries; if the access asked for is refused, a handle without access still answers most of them.
    public static SafeFileHandle Open(string path, uint access)
    {
        var h = CreateFileW(path, access, 3 /* share read and write */, IntPtr.Zero, 3 /* OPEN_EXISTING */, 0, IntPtr.Zero);
        if (h.IsInvalid) h = CreateFileW(path, 0, 3, IntPtr.Zero, 3, 0, IntPtr.Zero);
        if (h.IsInvalid) throw new IOException($"non apribile (errore Win32 {Marshal.GetLastWin32Error()})");
        return h;
    }

    public static bool Query(SafeFileHandle h, uint code, byte[] input, byte[] output, out int error)
    {
        var ok = DeviceIoControl(h, code, input, input.Length, output, output.Length, out _, IntPtr.Zero);
        error = ok ? 0 : Marshal.GetLastWin32Error();
        return ok;
    }

    [StructLayout(LayoutKind.Sequential)]
    struct SP_DEVICE_INTERFACE_DATA { public int cbSize; public Guid InterfaceClassGuid; public int Flags; public IntPtr Reserved; }

    [StructLayout(LayoutKind.Sequential)]
    struct SP_DEVINFO_DATA { public int cbSize; public Guid ClassGuid; public uint DevInst; public IntPtr Reserved; }

    [StructLayout(LayoutKind.Sequential)]
    public struct SYSTEM_POWER_STATUS { public byte ACLineStatus, BatteryFlag, BatteryLifePercent, SystemStatusFlag; public int BatteryLifeTime, BatteryFullLifeTime; }

    [DllImport("setupapi.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    static extern IntPtr SetupDiGetClassDevsW(ref Guid classGuid, IntPtr enumerator, IntPtr parent, uint flags);

    [DllImport("setupapi.dll", EntryPoint = "SetupDiGetClassDevsW", SetLastError = true, CharSet = CharSet.Unicode)]
    static extern IntPtr SetupDiGetClassDevsAll(IntPtr classGuid, IntPtr enumerator, IntPtr parent, uint flags);

    [DllImport("setupapi.dll", SetLastError = true)]
    static extern bool SetupDiEnumDeviceInterfaces(IntPtr set, IntPtr info, ref Guid guid, uint index, ref SP_DEVICE_INTERFACE_DATA data);

    [DllImport("setupapi.dll", SetLastError = true)]
    static extern bool SetupDiEnumDeviceInfo(IntPtr set, uint index, ref SP_DEVINFO_DATA info);

    [DllImport("setupapi.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    static extern bool SetupDiGetDeviceInterfaceDetailW(IntPtr set, ref SP_DEVICE_INTERFACE_DATA data, IntPtr detail, uint size, out uint required, ref SP_DEVINFO_DATA info);

    [DllImport("setupapi.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    static extern bool SetupDiGetDeviceInstanceIdW(IntPtr set, ref SP_DEVINFO_DATA info, [Out] char[] id, int size, out int required);

    [DllImport("setupapi.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    static extern bool SetupDiGetDeviceRegistryPropertyW(IntPtr set, ref SP_DEVINFO_DATA info, uint property, out uint type, byte[] buffer, int size, out int required);

    [DllImport("setupapi.dll", SetLastError = true)]
    static extern bool SetupDiDestroyDeviceInfoList(IntPtr set);

    [DllImport("cfgmgr32.dll")]
    static extern uint CM_Get_DevNode_Status(out uint status, out uint problem, uint devInst, uint flags);

    [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    static extern SafeFileHandle CreateFileW(string name, uint access, uint share, IntPtr security, uint disposition, uint flags, IntPtr template);

    [DllImport("kernel32.dll", SetLastError = true)]
    static extern bool DeviceIoControl(SafeFileHandle h, uint code, byte[] inBuffer, int inSize, byte[] outBuffer, int outSize, out int returned, IntPtr overlapped);

    [DllImport("kernel32.dll", SetLastError = true)]
    public static extern bool GetSystemPowerStatus(out SYSTEM_POWER_STATUS status);

    [DllImport("user32.dll")]
    public static extern int GetDisplayConfigBufferSizes(uint flags, out uint paths, out uint modes);

    [DllImport("user32.dll")]
    public static extern int QueryDisplayConfig(uint flags, ref uint pathCount, byte[] paths, ref uint modeCount, byte[] modes, IntPtr topology);

    [DllImport("user32.dll")]
    public static extern int DisplayConfigGetDeviceInfo(byte[] packet);
}
