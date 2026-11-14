namespace CheCavo.Windows;

// What Windows can see of the USB-C ports, read once by Reader and judged by Assessment.
public enum UsbSpeed { Low, Full, High, Super, SuperPlus }

public record UsbDevice(string Name, ushort Vid, ushort Pid, UsbSpeed Speed, bool SuperSpeedCapable, bool SuperSpeedPlusCapable, uint Status, bool IsHub);
public record Display(string Name, uint Technology, int Width, int Height, double Hertz);
public record PowerState(bool HasBattery, bool External, int? ChargeMilliwatts);
public record Observation(IReadOnlyList<UsbDevice> Devices, IReadOnlyList<Display> Displays, PowerState Power, IReadOnlyList<string> Errors);

// The same answers as the Mac app; «dichiarato dal cavo» does not exist on Windows (no access to the cable chip).
public enum Verdict { Yes, Partial, No, Unknown }
public enum Certainty { Measured, Inferred, Unknowable }

public record Answer(Verdict Verdict, string Summary, string Detail, Certainty? Certainty);
public record Trial(string Title, string HowTo, string WhatYouSee, bool Done, string? Result);
public record Report(Answer Chip, string Headline, Answer Charging, Answer Video, Answer Audio, Answer Data, IReadOnlyList<Trial> Trials, IReadOnlyList<string> Notes);
