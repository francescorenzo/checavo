// The decoders the app reader adds on top of the probe ones.
public class ReaderDecodeTests
{
    static byte[] Hex(string s) => Convert.FromHexString(s);

    // The Xiaomi 17 Ultra of the 2026-11-14 logs: High Speed on the USB 2 half of a USB-C port
    const string XiaomiConnection = "010000001201100200000040172748FF12060102030101020001000500000001000000";

    static byte[] V2(uint protocols, uint flags)
    {
        var b = new byte[UsbDecode.ConnectionExV2Size];
        BitConverter.GetBytes(protocols).CopyTo(b, 8);
        BitConverter.GetBytes(flags).CopyTo(b, 12);
        return b;
    }

    [Fact]
    public void V2KeepsTheRawBits()
    {
        var v = UsbDecode.ConnectionV2(V2(0b0011, 0b1010));
        Assert.Equal(0b0011u, v.ProtocolBits);
        Assert.Equal(0b1010u, v.FlagBits);
        Assert.Equal("USB 1.1, USB 2.0", v.Protocols);
    }

    [Fact]
    public void SpeedComesFromTheSpeedByteAndTheV2Flags()
    {
        var xiaomi = UsbDecode.Connection(Hex(XiaomiConnection));
        Assert.Equal(UsbSpeed.High, UsbDecode.Speed(xiaomi.Speed, 0b1010));  // supports SS+ but runs at High Speed
        Assert.Equal(UsbSpeed.Low, UsbDecode.Speed(0, 0));
        Assert.Equal(UsbSpeed.Full, UsbDecode.Speed(1, 0));
        Assert.Equal(UsbSpeed.Super, UsbDecode.Speed(3, 0b0011));
        Assert.Equal(UsbSpeed.SuperPlus, UsbDecode.Speed(3, 0b1111));
        Assert.Equal(UsbSpeed.Super, UsbDecode.Speed(3, 0));  // V2 not answered: the speed byte alone
    }

    static byte[] Path(int count, int i, uint modeIndex, uint num, uint den)
    {
        var b = new byte[count * WinDecode.PathInfoSize];
        var at = i * WinDecode.PathInfoSize;
        BitConverter.GetBytes(modeIndex).CopyTo(b, at + 32);
        BitConverter.GetBytes(num).CopyTo(b, at + 48);
        BitConverter.GetBytes(den).CopyTo(b, at + 52);
        return b;
    }

    [Fact]
    public void PathGivesItsTargetModeAndRefresh()
    {
        var paths = Path(2, 1, 3, 60000, 1001);
        Assert.Equal(3u, WinDecode.PathModeIndex(paths, 1));
        Assert.Equal(59.94, WinDecode.PathRefresh(paths, 1), 2);
        Assert.Equal(0, WinDecode.PathRefresh(Path(1, 0, 0, 60, 0), 0));  // unspecified refresh
    }

    [Fact]
    public void TargetModeGivesTheResolutionOnlyForTargetModes()
    {
        var modes = new byte[3 * WinDecode.ModeInfoSize];
        void Mode(int i, uint type, int cx, int cy)
        {
            var at = i * WinDecode.ModeInfoSize;
            BitConverter.GetBytes(type).CopyTo(modes, at);
            BitConverter.GetBytes(cx).CopyTo(modes, at + 40);
            BitConverter.GetBytes(cy).CopyTo(modes, at + 44);
        }
        Mode(0, 1, 1920, 1080);  // source mode: not the monitor
        Mode(2, 2, 3840, 2160);
        Assert.Equal((3840, 2160), WinDecode.TargetSize(modes, 2));
        Assert.Equal((0, 0), WinDecode.TargetSize(modes, 0));
        Assert.Equal((0, 0), WinDecode.TargetSize(modes, 0xFFFFFFFF));  // DISPLAYCONFIG_PATH_MODE_IDX_INVALID
        Assert.Equal((0, 0), WinDecode.TargetSize(modes, 7));
    }

    static byte[] Status(int rate)
    {
        var b = new byte[WinDecode.BatteryStatusSize];
        BitConverter.GetBytes(rate).CopyTo(b, 12);
        return b;
    }

    [Fact]
    public void ChargeIsOnlyThePowerEnteringTheBattery()
    {
        Assert.Equal(2770, WinDecode.ChargeMilliwatts(Status(2770)));  // the CHUWI on the charger
        Assert.Null(WinDecode.ChargeMilliwatts(Status(-14780)));         // discharging
        Assert.Null(WinDecode.ChargeMilliwatts(Status(0)));              // full
        Assert.Null(WinDecode.ChargeMilliwatts(Status(unchecked((int)0x80000000))));  // BATTERY_UNKNOWN_RATE
    }

    [Fact]
    public void DeviceNamePrefersTheFunctionOverTheGenericCompositeParent()
    {
        List<(string Id, string Name, string Class, string Status)> all =
        [
            (@"USB\VID_27170&PID_FF48\X", "altro", "USB", "ok"),             // a longer VID must not match
            (@"USB\VID_2717&PID_FF48\SERIALE", "Dispositivo USB composito", "USB", "ok"),
            (@"USB\VID_2717&PID_FF48&MI_00\7&1", "Xiaomi 17 Ultra", "WPD", "ok"),
            (@"USB\VID_0781&PID_5581\SERIALE", "Dispositivo di archiviazione di massa USB", "USB", "ok"),
        ];
        Assert.Equal("Xiaomi 17 Ultra", Reader.NameFor(all, 0x2717, 0xFF48));
        Assert.Equal("Dispositivo di archiviazione di massa USB", Reader.NameFor(all, 0x0781, 0x5581));
        Assert.Equal("Dispositivo USB 18D1:4E11", Reader.NameFor(all, 0x18D1, 0x4E11));
        Assert.Equal("Dispositivo USB 18D1:4E11", Reader.NameFor([(@"USB\VID_18D1&PID_4E11\S", "?", "USB", "ok")], 0x18D1, 0x4E11));
    }
}
