using Sonda;

public class RedactTests
{
    static string R(string text) => Redact.Text(text, userName: "Francesco", machineName: "FRANCESCO-PC");

    [Fact]
    public void UserAndPcNamesAreHidden()
    {
        Assert.Equal(@"C:\Users\<utente>\Desktop", R(@"C:\Users\francesco\Desktop"));
        Assert.Equal("Nome: <pc>", R("Nome: FRANCESCO-PC"));
    }

    [Fact]
    public void VeryShortNamesAreLeftAloneToAvoidMangling()
    {
        Assert.Equal("abc", Redact.Text("abc", userName: "ab", machineName: "x"));
    }

    [Theory]
    [InlineData(@"USB\VID_05AC&PID_12A8\00008030000A0B0C0D0E0F10", @"USB\VID_05AC&PID_12A8\<seriale>")]
    [InlineData(@"USBSTOR\Disk&Ven_Sams&Prod_T7&Rev_1.0\S5RANS0R123456&0", @"USBSTOR\Disk&Ven_Sams&Prod_T7&Rev_1.0\<seriale>")]
    [InlineData(@"Id: USB\VID_0BDA&PID_8153\000001000000 stato OK", @"Id: USB\VID_0BDA&PID_8153\<seriale> stato OK")]
    [InlineData(@"\\?\USB#VID_2109&PID_0817#000000001#{f18a0e88-c30c-11d0-8815-00a0c906bed8}", @"\\?\USB#VID_2109&PID_0817#<seriale>#{f18a0e88-c30c-11d0-8815-00a0c906bed8}")]
    [InlineData(@"SWD\WPDBUSENUM\_??_USBSTOR#DISK&VEN_SANDISK&PROD_ULTRA&REV_1.00#4C530001234567890&0#{53f56307-b6bf-11d0-94f2-00a0c91efb8b}", @"SWD\WPDBUSENUM\_??_USBSTOR#DISK&VEN_SANDISK&PROD_ULTRA&REV_1.00#<seriale>#{53f56307-b6bf-11d0-94f2-00a0c91efb8b}")]  // Kernel-PnP, when a stick is plugged in
    [InlineData(@"STORAGE\VOLUME\_??_USBSTOR#DISK&VEN_SANDISK&PROD_ULTRA&REV_1.00#4C530001234567890&0#{53f56307-b6bf-11d0-94f2-00a0c91efb8b}", @"STORAGE\VOLUME\_??_USBSTOR#DISK&VEN_SANDISK&PROD_ULTRA&REV_1.00#<seriale>#{53f56307-b6bf-11d0-94f2-00a0c91efb8b}")]
    public void DeviceSerialNumbersAreHidden(string input, string expected) => Assert.Equal(expected, R(input));

    [Theory]
    [InlineData(@"USB\VID_8087&PID_0033\5&2B4E1A2&0&10")]  // no serial: Windows made this id up
    [InlineData(@"ACPI\USBC000\0")]
    [InlineData(@"USB\ROOT_HUB30\4&1C1A2B3&0&0")]
    [InlineData(@"\\?\USB#ROOT_HUB30#4&1c1a2b3&0&0#{f18a0e88-c30c-11d0-8815-00a0c906bed8}")]
    [InlineData(@"SWD\WPDBUSENUM\_??_USB#VID_04E8&PID_6860&MI_00#6&1A2B3C&0&0000#{6ac27878-a6fa-4155-ba85-f98f491d4f33}")]  // a phone: no serial here
    public void IdsWithoutSerialStayReadable(string id) => Assert.Equal(id, R(id));
}
