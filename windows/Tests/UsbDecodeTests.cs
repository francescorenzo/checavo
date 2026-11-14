using System.Text;
using Sonda;

// The buffers follow the packed (1-byte) layouts of usbioctl.h.
public class UsbDecodeTests
{
    [Fact]
    public void IoctlCodesMatchTheHeader()
    {
        Assert.Equal(0x220408u, UsbDecode.Ioctl(258));  // GET_NODE_INFORMATION
        Assert.Equal(0x220448u, UsbDecode.Ioctl(274));  // GET_NODE_CONNECTION_INFORMATION_EX
        Assert.Equal(0x220458u, UsbDecode.Ioctl(278));  // GET_PORT_CONNECTOR_PROPERTIES
        Assert.Equal(0x22045Cu, UsbDecode.Ioctl(279));  // GET_NODE_CONNECTION_INFORMATION_EX_V2
    }

    [Fact]
    public void HubPortCountIsReadFromTheHubDescriptor()
    {
        var b = new byte[UsbDecode.NodeInfoSize];
        b[6] = 4;
        Assert.Equal(4, UsbDecode.PortCount(b));
    }

    [Fact]
    public void ConnectionInfoGivesDeviceAndSpeed()
    {
        var b = new byte[UsbDecode.ConnectionExSize];
        BitConverter.GetBytes(3u).CopyTo(b, 0);
        BitConverter.GetBytes((ushort)0x0320).CopyTo(b, 6);
        BitConverter.GetBytes((ushort)0x05AC).CopyTo(b, 12);
        BitConverter.GetBytes((ushort)0x1234).CopyTo(b, 14);
        b[23] = 3;
        b[24] = 1;
        BitConverter.GetBytes(1u).CopyTo(b, 31);
        var c = UsbDecode.Connection(b);
        Assert.Equal(new UsbConnection(Status: 1, Speed: 3, Vid: 0x05AC, Pid: 0x1234, BcdUsb: 0x0320, IsHub: true), c);
        Assert.Equal("collegato", UsbDecode.StatusName(c.Status));
        Assert.StartsWith("SuperSpeed", UsbDecode.SpeedName(c.Speed));
    }

    [Fact]
    public void V2FlagsTellSuperSpeedPlus()
    {
        var b = new byte[UsbDecode.ConnectionExV2Size];
        BitConverter.GetBytes(0b0110u).CopyTo(b, 8);
        BitConverter.GetBytes(0b1101u).CopyTo(b, 12);
        var v = UsbDecode.ConnectionV2(b);
        Assert.Equal("USB 2.0, USB 3", v.Protocols);
        Assert.Equal("funziona a SuperSpeed o più, funziona a SuperSpeedPlus o più, regge SuperSpeedPlus o più", v.Flags);
    }

    [Fact]
    public void PortConnectorTellsTypeCAndCompanion()
    {
        var b = new byte[UsbDecode.PortConnectorSize];
        BitConverter.GetBytes(0b1001u).CopyTo(b, 8);
        BitConverter.GetBytes((ushort)1).CopyTo(b, 12);
        BitConverter.GetBytes((ushort)2).CopyTo(b, 14);
        Encoding.Unicode.GetBytes(@"\\?\usb#root_hub30" + "\0").CopyTo(b, 16);
        var p = UsbDecode.PortConnector(b);
        Assert.True(p.IsTypeC);
        Assert.True(p.UserConnectable);
        Assert.Equal(2, p.CompanionPort);
        Assert.Equal(@"\\?\usb#root_hub30", p.CompanionHub);
    }
}
