// The verdicts of the Windows app, one test per row of the table in docs/superpowers/plans/2026-11-14-che-cavo-windows.md.
public class AssessmentTests
{
    static readonly PowerState OnBattery = new(HasBattery: true, External: false, ChargeMilliwatts: null);

    static UsbDevice Dev(UsbSpeed speed, bool ss = false, bool ssp = false, uint status = 1, string name = "Xiaomi 17 Ultra") =>
        new(name, 0x2717, 0xFF48, speed, ss, ssp, status, IsHub: false);

    static Display Monitor(uint tech, string name = "ARZOPA") => new(name, tech, 3840, 2160, 60.0);

    static Report Assess(UsbDevice[]? devices = null, Display[]? displays = null, PowerState? power = null, string[]? errors = null) =>
        Assessment.Assess(new(devices ?? [], displays ?? [], power ?? OnBattery, errors ?? []));

    // --- Data ---

    [Fact]
    public void NothingOnTheUsbCPortsAsksForADeviceAndExplainsAChargeOnlyCable()
    {
        var r = Assess();
        Assert.Equal(Verdict.Unknown, r.Data.Verdict);
        Assert.Equal("Da provare", r.Data.Summary);
        Assert.Null(r.Data.Certainty);
        Assert.Contains("solo da ricarica", r.Data.Detail);
        Assert.Equal("Collega qualcosa all'altro capo del cavo", r.Headline);
    }

    [Fact]
    public void ADeviceThatDoesNotStartIsNeverReportedAsFine()
    {
        var r = Assess([Dev(UsbSpeed.High, status: 2)]);
        Assert.Equal(Verdict.Partial, r.Data.Verdict);
        Assert.Equal("Windows vede «Xiaomi 17 Ultra» ma non funziona", r.Data.Summary);
        Assert.Contains("enumerazione fallita", r.Data.Detail);
        Assert.Equal(Certainty.Measured, r.Data.Certainty);
        Assert.Equal("Il dispositivo non funziona", r.Headline);
        Assert.Equal(Verdict.Unknown, r.Audio.Verdict);
    }

    [Fact]
    public void SuperSpeedPlusMeansFastWires()
    {
        var r = Assess([Dev(UsbSpeed.SuperPlus, ss: true, ssp: true)]);
        Assert.Equal(Verdict.Yes, r.Data.Verdict);
        Assert.Equal("Almeno 10 Gbit/s (10 GB in circa 15 secondi)", r.Data.Summary);
        Assert.Equal(Certainty.Measured, r.Data.Certainty);
        Assert.Equal("Cavo veloce: almeno 10 Gbit/s", r.Headline);
    }

    [Fact]
    public void FiveGigabitWithADeviceThatDoesTenBlamesCableOrPort()
    {
        var r = Assess([Dev(UsbSpeed.Super, ss: true, ssp: true)]);
        Assert.Equal(Verdict.Partial, r.Data.Verdict);
        Assert.Equal("5 Gbit/s, ma il dispositivo regge 10", r.Data.Summary);
        Assert.Contains("un'altra porta", r.Data.Detail);
        Assert.Equal(Certainty.Measured, r.Data.Certainty);
        Assert.Equal("Cavo o porta fermi a 5 Gbit/s", r.Headline);
    }

    [Fact]
    public void FiveGigabitDeviceShowsFastWires()
    {
        var r = Assess([Dev(UsbSpeed.Super, ss: true)]);
        Assert.Equal(Verdict.Yes, r.Data.Verdict);
        Assert.Equal("5 Gbit/s (10 GB in circa 30 secondi)", r.Data.Summary);
        Assert.Equal("Cavo con i fili veloci (USB 3)", r.Headline);
    }

    [Fact]
    public void FastDeviceStuckAtUsb2PointsAtTheCable()  // the Xiaomi of the 2026-11-14 logs
    {
        var r = Assess([Dev(UsbSpeed.High, ss: true, ssp: true)]);
        Assert.Equal(Verdict.Partial, r.Data.Verdict);
        Assert.Equal("Lenti: 480 Mbit/s, ma il dispositivo regge 10 Gbit/s", r.Data.Summary);
        Assert.Contains("solo i fili USB 2.0", r.Data.Detail);
        Assert.Contains("Trasferimento file", r.Data.Detail);
        Assert.Equal(Certainty.Inferred, r.Data.Certainty);
        Assert.Equal("Cavo probabilmente solo USB 2.0", r.Headline);
        Assert.Equal("Lenti: 480 Mbit/s, ma il dispositivo regge 5 Gbit/s", Assess([Dev(UsbSpeed.High, ss: true)]).Data.Summary);
    }

    [Fact]
    public void Usb2DeviceWorksButDoesNotTestTheFastWires()
    {
        var r = Assess([Dev(UsbSpeed.High, name: "Chiavetta")]);
        Assert.Equal(Verdict.Yes, r.Data.Verdict);
        Assert.Equal("480 Mbit/s (10 GB in circa 5 minuti)", r.Data.Summary);
        Assert.Contains("USB 3", r.Data.Detail);
        Assert.Equal(Certainty.Measured, r.Data.Certainty);
        Assert.Equal("Il cavo porta i dati", r.Headline);
        Assert.Equal("12 Mbit/s", Assess([Dev(UsbSpeed.Full)]).Data.Summary);
    }

    [Fact]
    public void WithSeveralDevicesTheMostTellingOneIsJudgedAndTheUserIsWarned()
    {
        var r = Assess([Dev(UsbSpeed.Super, ss: true, name: "Disco"), Dev(UsbSpeed.High, ss: true, ssp: true, name: "Telefono")]);
        Assert.Equal("Lenti: 480 Mbit/s, ma il dispositivo regge 10 Gbit/s", r.Data.Summary);
        Assert.Contains(r.Notes, n => n.Contains("2 dispositivi") && n.Contains("«Telefono»"));
        Assert.DoesNotContain(Assess([Dev(UsbSpeed.High)]).Notes, n => n.Contains("dispositivi"));
    }

    [Fact]
    public void AUsb3HubShowsTwoHalvesAndIsNotABrakedDevice()
    {
        UsbDevice Hub(UsbSpeed s, ushort pid) => new("Hub", 0x05E3, pid, s, true, false, 1, IsHub: true);
        var r = Assess([Hub(UsbSpeed.High, 0x0610), Hub(UsbSpeed.Super, 0x0620)]);
        Assert.Equal(Verdict.Yes, r.Data.Verdict);
        Assert.Equal("5 Gbit/s (10 GB in circa 30 secondi)", r.Data.Summary);
        Assert.DoesNotContain(r.Notes, n => n.Contains("dispositivi"));
    }

    // --- Video ---

    [Theory]
    [InlineData(10u)]   // DisplayPort esterno
    [InlineData(18u)]   // DisplayPort dentro USB4
    public void ADisplayPortMonitorProvesVideo(uint tech)
    {
        var r = Assess(displays: [Monitor(0x80000000, "interno"), Monitor(tech)]);
        Assert.Equal(Verdict.Yes, r.Video.Verdict);
        Assert.Equal("Sì: ARZOPA, 3840×2160 a 60 Hz", r.Video.Summary);
        Assert.Contains("non dice da quale porta", r.Video.Detail);
        Assert.Equal(Certainty.Measured, r.Video.Certainty);
        Assert.Equal("Il cavo porta il video", r.Headline);
        Assert.Equal(Verdict.Yes, r.Audio.Verdict);
        Assert.Equal("Sì, verso il monitor", r.Audio.Summary);
    }

    [Fact]
    public void Usb2OnlyCableProbablyCarriesNoVideo()
    {
        var r = Assess([Dev(UsbSpeed.High, ss: true, ssp: true)]);
        Assert.Equal(Verdict.No, r.Video.Verdict);
        Assert.Equal("Probabilmente no", r.Video.Summary);
        Assert.Equal(Certainty.Inferred, r.Video.Certainty);
    }

    [Theory]
    [InlineData(UsbSpeed.Super, false)]
    [InlineData(UsbSpeed.Super, true)]
    [InlineData(UsbSpeed.SuperPlus, true)]
    public void FastWiresProbablyCarryVideo(UsbSpeed speed, bool ssp)
    {
        var r = Assess([Dev(speed, ss: true, ssp: ssp)]);
        Assert.Equal(Verdict.Yes, r.Video.Verdict);
        Assert.Equal("Probabilmente sì", r.Video.Summary);
        Assert.Equal(Certainty.Inferred, r.Video.Certainty);
    }

    [Fact]
    public void HdmiOrInternalScreensDoNotProveTheUsbCCable()
    {
        var r = Assess(displays: [Monitor(0x80000000, "interno"), Monitor(11, "eDP"), Monitor(5, "TV")]);
        Assert.Equal(Verdict.Unknown, r.Video.Verdict);
        Assert.Equal("Da provare con un monitor USB-C", r.Video.Summary);
        Assert.Contains("HDMI", r.Video.Detail);
        Assert.Null(r.Video.Certainty);
        Assert.DoesNotContain("HDMI", Assess(displays: [Monitor(0x80000000)]).Video.Detail);
    }

    // --- Audio ---

    [Fact]
    public void AWorkingUsbDeviceMeansUsbAudioWorks()
    {
        var r = Assess([Dev(UsbSpeed.High)]);
        Assert.Equal(Verdict.Yes, r.Audio.Verdict);
        Assert.Equal("Sì, per cuffie e schede audio USB", r.Audio.Summary);
        Assert.Equal(Certainty.Inferred, r.Audio.Certainty);
        Assert.Equal(Verdict.Unknown, Assess().Audio.Verdict);
    }

    // --- Charging ---

    [Fact]
    public void WithoutABatteryChargingCannotBeMeasured()
    {
        var r = Assess(power: new(HasBattery: false, External: true, ChargeMilliwatts: null));
        Assert.Equal(Verdict.Unknown, r.Charging.Verdict);
        Assert.Equal("Non misurabile su questo PC", r.Charging.Summary);
        Assert.Equal(Certainty.Unknowable, r.Charging.Certainty);
        Assert.False(r.Trials[2].Done);
    }

    [Theory]
    [InlineData(27753, "Sì: entrano 28 W nella batteria")]
    [InlineData(2770, "Sì: entrano 2,8 W nella batteria")]
    public void ChargingShowsTheWattsEnteringTheBattery(int milliwatts, string summary)
    {
        var r = Assess(power: new(HasBattery: true, External: true, ChargeMilliwatts: milliwatts));
        Assert.Equal(Verdict.Yes, r.Charging.Verdict);
        Assert.Equal(summary, r.Charging.Summary);
        Assert.Contains("non il massimo del cavo", r.Charging.Detail);
        Assert.Contains("da quale porta", r.Charging.Detail);
        Assert.Equal(Certainty.Measured, r.Charging.Certainty);
        Assert.Equal("Il PC si carica", r.Headline);
    }

    [Fact]
    public void FullBatteryOnTheChargerIsPoweredNotZeroWatts()
    {
        var r = Assess(power: new(HasBattery: true, External: true, ChargeMilliwatts: null));
        Assert.Equal(Verdict.Yes, r.Charging.Verdict);
        Assert.Equal("Sì: il PC è alimentato", r.Charging.Summary);
        Assert.DoesNotContain("0 W", r.Charging.Summary);
    }

    [Fact]
    public void OnBatteryChargingIsStillToTry()
    {
        var r = Assess();
        Assert.Equal(Verdict.Unknown, r.Charging.Verdict);
        Assert.Equal("Da provare", r.Charging.Summary);
    }

    // --- Trials, headline order, details ---

    [Fact]
    public void TheThreeTrialsAreDoneByWhatIsConnected()
    {
        var none = Assess();
        Assert.Equal(["Dati", "Video", "Ricarica"], none.Trials.Select(t => t.Title));
        Assert.All(none.Trials, t => { Assert.False(t.Done); Assert.Null(t.Result); });

        // inferred video does not count as a video trial
        var all = Assess([Dev(UsbSpeed.SuperPlus, ss: true, ssp: true)], [Monitor(10)], new(true, true, 20000));
        Assert.All(all.Trials, t => Assert.True(t.Done));
        Assert.Equal("Sì: ARZOPA, 3840×2160 a 60 Hz", all.Trials[1].Result);
        Assert.False(Assess([Dev(UsbSpeed.SuperPlus, ss: true, ssp: true)]).Trials[1].Done);
        Assert.Equal("Cavo veloce: almeno 10 Gbit/s", all.Headline);  // data first, then video, then charging
    }

    [Fact]
    public void DetailsListEverythingReadAndTheReadErrors()
    {
        var o = new Observation([Dev(UsbSpeed.High, ss: true, ssp: true)], [Monitor(10)], new(true, true, 2770), ["hub non apribile"]);
        var d = Assessment.Details(o);
        Assert.Contains("2717:FF48 Xiaomi 17 Ultra", d);
        Assert.Contains("DisplayPort esterno", d);
        Assert.Contains("2770 mW", d);
        Assert.Contains("hub non apribile", d);
    }

    // --- Cable chip: first thing on screen, and on Windows always unreadable ---

    [Fact]
    public void TheChipIsAlwaysUnreadableOnWindowsAndPointsToTheMac()
    {
        foreach (var r in new[] { Assess(), Assess([Dev(UsbSpeed.SuperPlus, ss: true, ssp: true)], [Monitor(10)], new(true, true, 25000)) })
        {
            Assert.Equal(Verdict.Unknown, r.Chip.Verdict);
            Assert.Equal(Certainty.Unknowable, r.Chip.Certainty);
            Assert.Equal("Non si legge su questo PC", r.Chip.Summary);
            Assert.Contains("se il cavo ce l'ha", r.Chip.Detail);
            Assert.Contains("Mac", r.Chip.Detail);
        }
    }

    [Fact]
    public void TheNotesNoLongerRepeatWhatTheChipRowSays()
    {
        Assert.Empty(Assess().Notes);
    }

    // --- Watt dial ---

    [Theory]
    [InlineData(null, 30)]
    [InlineData(0, 30)]
    [InlineData(25000, 30)]
    [InlineData(30000, 30)]
    [InlineData(30001, 60)]
    [InlineData(65000, 100)]
    [InlineData(240000, 240)]
    [InlineData(250500, 260)]
    public void TheDialScaleIsTheFirstUsualChargerSizeAboveTheWatts(int? milliwatts, int scale)
    {
        Assert.Equal(scale, Assessment.GaugeScale(milliwatts));
    }
}
