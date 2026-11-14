using System.Text;
using Sonda;

// Buffers follow the Windows headers: batclass.h for the battery, wingdi.h for QueryDisplayConfig.
public class WinDecodeTests
{
    static byte[] BatteryStatus(uint state, uint capacity, uint voltage, int rate)
    {
        var b = new byte[WinDecode.BatteryStatusSize];
        BitConverter.GetBytes(state).CopyTo(b, 0);
        BitConverter.GetBytes(capacity).CopyTo(b, 4);
        BitConverter.GetBytes(voltage).CopyTo(b, 8);
        BitConverter.GetBytes(rate).CopyTo(b, 12);
        return b;
    }

    [Fact]
    public void BatteryIoctlCodesMatchTheHeader()
    {
        Assert.Equal(0x294040u, WinDecode.BatteryIoctl(0x10));  // IOCTL_BATTERY_QUERY_TAG
        Assert.Equal(0x294044u, WinDecode.BatteryIoctl(0x11));  // IOCTL_BATTERY_QUERY_INFORMATION
        Assert.Equal(0x29404Cu, WinDecode.BatteryIoctl(0x13));  // IOCTL_BATTERY_QUERY_STATUS
    }

    [Fact]
    public void ChargingBatteryShowsTheChargeRate()
    {
        Assert.Equal(
            "alimentazione esterna: sì | in carica: sì | in scarica: no | ricarica 2770 mW | scarica 0 mW | tensione 11789 mV | carica residua 27753 mWh",
            WinDecode.Battery(BatteryStatus(1 | 4, 27753, 11789, 2770)));
    }

    [Fact]
    public void DischargingBatteryShowsTheDrainAsAPositiveNumber()
    {
        Assert.Equal(
            "alimentazione esterna: no | in carica: no | in scarica: sì | ricarica 0 mW | scarica 14780 mW | tensione 11665 mV | carica residua 28281 mWh",
            WinDecode.Battery(BatteryStatus(2, 28281, 11665, -14780)));
    }

    [Fact]
    public void UnknownBatteryValuesAreSaidAsUnknown()
    {
        var line = WinDecode.Battery(BatteryStatus(1, 0xFFFFFFFF, 0xFFFFFFFF, unchecked((int)0x80000000)));
        Assert.Contains("ricarica ? mW", line);
        Assert.Contains("tensione ? mV", line);
        Assert.Contains("carica residua ? mWh", line);
    }

    [Fact]
    public void FullChargeCapacityIsReadFromBatteryInformation()
    {
        var b = new byte[WinDecode.BatteryInformationSize];
        BitConverter.GetBytes(53372u).CopyTo(b, 16);
        Assert.Equal(53372u, WinDecode.FullChargedCapacity(b));
    }

    [Theory]
    [InlineData(10u, "DisplayPort esterno")]
    [InlineData(5u, "HDMI")]
    [InlineData(18u, "DisplayPort dentro USB4")]
    [InlineData(0x80000000u, "schermo interno")]
    [InlineData(77u, "codice 77")]
    public void OutputTechnologyHasAName(uint code, string name) => Assert.Equal(name, WinDecode.OutputTechnology(code));

    [Fact]
    public void TargetNameRequestCopiesAdapterAndTargetOfThePath()
    {
        var paths = new byte[2 * WinDecode.PathInfoSize];
        var second = WinDecode.PathInfoSize;
        for (var i = 0; i < 12; i++) paths[second + 20 + i] = (byte)(i + 1);  // target adapterId (8) + id (4)
        var r = WinDecode.TargetNameRequest(paths, 1);
        Assert.Equal(WinDecode.TargetNameSize, r.Length);
        Assert.Equal(2u, BitConverter.ToUInt32(r, 0));                         // DISPLAYCONFIG_DEVICE_INFO_GET_TARGET_NAME
        Assert.Equal((uint)WinDecode.TargetNameSize, BitConverter.ToUInt32(r, 4));
        Assert.Equal(Enumerable.Range(1, 12).Select(i => (byte)i), r[8..20]);
    }

    [Fact]
    public void TargetNameGivesMonitorTechnologyConnectorAndPath()
    {
        var b = new byte[WinDecode.TargetNameSize];
        BitConverter.GetBytes(10u).CopyTo(b, 24);
        BitConverter.GetBytes(2u).CopyTo(b, 32);
        Encoding.Unicode.GetBytes("ARZOPA\0").CopyTo(b, 36);
        Encoding.Unicode.GetBytes(@"\\?\DISPLAY#GWDB161#5&6c0a38a&0&UID261#{x}" + "\0").CopyTo(b, 164);
        Assert.Equal(new DisplayTarget("ARZOPA", 10, 2, @"\\?\DISPLAY#GWDB161#5&6c0a38a&0&UID261#{x}"), WinDecode.Target(b));
    }

    [Theory]
    [InlineData(@"ACPI\USBC000\0", true)]
    [InlineData("USB Type-C Connector System Software Interface (UCSI)", true)]
    [InlineData("Router USB4", true)]
    [InlineData("thunderbolt controller", true)]
    [InlineData(@"USB\VID_18D1&PID_4E11\<seriale> Xiaomi 17 Ultra USBDevice", false)]
    public void TypeCRelatedDevicesAreRecognised(string text, bool expected) => Assert.Equal(expected, WinDecode.IsTypeCRelated(text));

    [Theory]
    [InlineData(0x0180200Au, 0u, "OK")]       // DN_STARTED among other flags
    [InlineData(0x01802000u, 0u, "fermo")]
    [InlineData(0x01802400u, 28u, "problema 28")]
    public void DeviceStatusReadsLikeDeviceManager(uint status, uint problem, string expected) =>
        Assert.Equal(expected, WinDecode.DeviceStatus(status, problem));

    [Fact]
    public void RegistryValuesAreFlattened()
    {
        Assert.Equal("0A FF".Replace(" ", ""), WinDecode.Value(new byte[] { 0x0A, 0xFF }));
        Assert.Equal("a; b", WinDecode.Value(new[] { "a", "b" }));
        Assert.Equal("3", WinDecode.Value(3));
        Assert.Equal("", WinDecode.Value(null));
    }

    [Fact]
    public void LongMessagesAreShortenedOnOneLine()
    {
        Assert.Equal("(senza testo)", WinDecode.Short(null));
        Assert.Equal("riga uno riga due", WinDecode.Short("riga uno\r\n  riga due "));
        var cut = WinDecode.Short(new string('x', 400));
        Assert.Equal(303, cut.Length);
        Assert.EndsWith("...", cut);
    }
}
