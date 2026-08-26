/**
Register addresses and bit fields of the TPS274C65.

Addresses are 7 bits wide. Offsets that are not listed here are reserved and
  must not be written.

See TI SLVSFZ2C section 8.6 for the full map.
*/

/** Fault type, ORed across all channels. Returned on every SPI frame. */
REG-FAULT-TYPE-STAT ::= 0x00
/** Which channels have any fault at all. */
REG-FAULT-CH-STAT ::= 0x01
/** Global faults: power-on reset, SPI, watchdog, undervoltage, chip thermal. */
REG-FAULT-GLOBAL-TYPE ::= 0x02
/** Off-state short-to-VS, per channel. */
REG-SHRT-VS-CH-STAT ::= 0x03
/** Off-state wire break, per channel. */
REG-WB-OFF-CH-STAT ::= 0x04
/** On-state wire break, per channel. */
REG-WB-ON-CH-STAT ::= 0x05
/** Current limit reached, per channel. */
REG-ILIMIT-CH-STAT ::= 0x06
/** Thermal shutdown, per channel. */
REG-THERMAL-SD-CH-STAT ::= 0x07
/** Thermal warning, per channel. Live status, not latched. */
REG-THERMAL-WRN-CH-STAT ::= 0x08
/** Reverse current blocked, per channel. */
REG-RVRS-BLK-CH-STAT ::= 0x09

/** Current sense ADC result for channel 1, 8 most significant bits. */
REG-ADC-RESULT-CH1-I ::= 0x0b
/** Current sense ADC result for channel 1, 2 least significant bits. */
REG-ADC-RESULT-CH1-I-LSB ::= 0x0c
/** Current sense ADC result for channel 2, 8 most significant bits. */
REG-ADC-RESULT-CH2-I ::= 0x0d
/** Current sense ADC result for channel 2, 2 least significant bits. */
REG-ADC-RESULT-CH2-I-LSB ::= 0x0e
/** Current sense ADC result for channel 3, 8 most significant bits. */
REG-ADC-RESULT-CH3-I ::= 0x0f
/** Current sense ADC result for channel 3, 2 least significant bits. */
REG-ADC-RESULT-CH3-I-LSB ::= 0x10
/** Current sense ADC result for channel 4, 8 most significant bits. */
REG-ADC-RESULT-CH4-I ::= 0x11
/** Current sense ADC result for channel 4, 2 least significant bits. */
REG-ADC-RESULT-CH4-I-LSB ::= 0x12
/** Temperature sense ADC result for channel 1. */
REG-ADC-RESULT-CH1-T ::= 0x13
/** Temperature sense ADC result for channel 2. */
REG-ADC-RESULT-CH2-T ::= 0x14
/** Temperature sense ADC result for channel 3. */
REG-ADC-RESULT-CH3-T ::= 0x15
/** Temperature sense ADC result for channel 4. */
REG-ADC-RESULT-CH4-T ::= 0x16
/** Output voltage sense ADC result for channel 1. */
REG-ADC-RESULT-CH1-V ::= 0x17
/** Output voltage sense ADC result for channel 2. */
REG-ADC-RESULT-CH2-V ::= 0x18
/** Output voltage sense ADC result for channel 3. */
REG-ADC-RESULT-CH3-V ::= 0x19
/** Output voltage sense ADC result for channel 4. */
REG-ADC-RESULT-CH4-V ::= 0x1a
/** Supply voltage ADC result, 8 most significant bits. */
REG-ADC-RESULT-VS ::= 0x1b
/** Supply voltage ADC result, 2 least significant bits. */
REG-ADC-RESULT-VS-LSB ::= 0x1c

/** Per-channel switch state. Bits [3:0] are CH4 to CH1. */
REG-SW-STATE ::= 0x1d
/** LED 1 to 4 control. */
REG-LED1-4-CTL ::= 0x1e
/** LED 5 to 8 control. */
REG-LED5-8-CTL ::= 0x1f
/** Switch state the outputs assume on a watchdog error. */
REG-FS-SW-STATE ::= 0x20
/** Current limit and inrush duration for channels 1 and 2. */
REG-DEV-CONFIG1 ::= 0x21
/** Current limit and inrush duration for channels 3 and 4. */
REG-DEV-CONFIG2 ::= 0x22
/** Reverse current blocking, current limit split, sense range, paralleling. */
REG-DEV-CONFIG3 ::= 0x23
/** Watchdog, wire-break pull-up current and on-state threshold. */
REG-DEV-CONFIG4 ::= 0x24
/** ADC enable, auto retry, fault blanking, fail-safe, fault latching. */
REG-DEV-CONFIG5 ::= 0x25
/** Per-channel reverse-current-blocking gate control. */
REG-DEV-CONFIG6 ::= 0x26
/** Per-fault-type masking of the FLT pin. */
REG-FAULT-MASK ::= 0x27
/** Enables off-state wire-break diagnostics, per channel. */
REG-EN-WB-OFF ::= 0x28
/** Enables on-state wire-break diagnostics, per channel. */
REG-EN-WB-ON ::= 0x29
/** Enables off-state short-to-VS diagnostics, per channel. */
REG-EN-SHRT-VS ::= 0x2a
/** Skips the current sense conversion, per channel. */
REG-ADC-ISNS-DIS ::= 0x2b
/** Skips the temperature sense conversion, per channel. */
REG-ADC-TSNS-DIS ::= 0x2c
/** Skips the output voltage sense conversion, per channel. */
REG-ADC-VSNS-DIS ::= 0x2d
/** Drops whole measurement classes from the ADC round robin. */
REG-ADC-CONFIG1 ::= 0x2e
/**
Frame size and CRC selection.

Bit 1 is `D24BIT`, bit 0 is `CRC_EN`. In daisy chain, `D24BIT` selects 24-bit
  frames over 16-bit ones; it does not change the one-frame read latency.

SLVSFZ2C never specifies the CRC, giving only its 4-bit width. TI published
  the parameters on E2E: CRC-4-ITU, polynomial x^4 + x + 1 (0x3), starting
  value 1111b, most significant bit first, no final inversion, and a
  four-bit zero flush at the end. The sibling TPS2HCS10-Q1 datasheet states
  the same, and TI has confirmed the two parts match.
*/
REG-CRC-CONFIG ::= 0x2f

// FAULT_TYPE_STAT ($REG-FAULT-TYPE-STAT) bits. These are also the bits of the
// fault byte that the device returns on every frame.

/** Supply fault: VDD undervoltage lockout or VS undervoltage. */
FAULT-SUPPLY ::= 1 << 7
/** Reverse current was blocked on at least one channel. */
FAULT-RVRS-BLK ::= 1 << 6
/** At least one channel is in thermal shutdown. */
FAULT-CHAN-TSD ::= 1 << 5
/** At least one channel hit its current limit. */
FAULT-ILIMIT ::= 1 << 4
/** On-state wire break on at least one channel. */
FAULT-WB-ON ::= 1 << 3
/** Off-state wire break on at least one channel. */
FAULT-WB-OFF ::= 1 << 2
/** Off-state short to VS on at least one channel. */
FAULT-SHRT-VS ::= 1 << 1
/** A global error or warning is pending in $REG-FAULT-GLOBAL-TYPE. */
FAULT-GLOBAL ::= 1 << 0

// FAULT_GLOBAL_TYPE ($REG-FAULT-GLOBAL-TYPE) bits.

/** A power-on reset happened since this register was last read. */
GLOBAL-POR ::= 1 << 6
/** The controller die tripped its thermal warning. */
GLOBAL-CHIP-THERMALSD ::= 1 << 5
/** A SPI format, clock or CRC error was seen. */
GLOBAL-SPI-ERR ::= 1 << 4
/** The SPI watchdog timed out. */
GLOBAL-WD-ERR ::= 1 << 3
/** VDD dropped below its undervoltage lockout. */
GLOBAL-VDD-UVLO ::= 1 << 2
/** VS dropped below the undervoltage warning threshold. */
GLOBAL-VS-UV-WRN ::= 1 << 1
/** VS dropped below the undervoltage protection threshold. */
GLOBAL-VS-UV ::= 1 << 0

// DEV_CONFIG1 ($REG-DEV-CONFIG1) and DEV_CONFIG2 ($REG-DEV-CONFIG2) fields.
//
// The two registers share a layout. DEV_CONFIG1 configures channels 1 and 2
// and DEV_CONFIG2 channels 3 and 4, but DEV_CONFIG2 is only consulted when
// $CONFIG3-ILIM-SET is set; otherwise DEV_CONFIG1 governs all four channels.

/** Mask of `ILIM_REG`, the current limit code. See the `ILIM-AS-*-MA` constants. */
ILIM-REG-MASK ::= 0x0f
/** Mask of `ILIM_DURATION`, the inrush window code. See the `INRUSH-*-MS` constants. */
ILIM-DURATION-MASK ::= 0xf0
/** How far up `ILIM_DURATION` sits. See $ILIM-DURATION-MASK. */
ILIM-DURATION-SHIFT ::= 4

/**
A current limit a channel can be configured with.

The instances are the sixteen limits the `ILIM_REG` field can select, and
  there are no others: the constructor is private, so a limit cannot be
  invented and `Driver.set-current-limit` cannot be handed a plain integer
  or an $InrushWindow by mistake. The two fields share a byte and both run 0 to
  15, which is exactly the confusion the types rule out.

The limits are the ones the AS part uses. The BS part codes them the same
  way; the ASH part does not, and these constants would name the wrong
  current on one. See the README.
*/
class IlimCode:
  /** The `ILIM_REG` code selecting this limit. See $ILIM-REG-MASK. */
  value/int
  /** The typical limit, in milliamps. See $MA-250 for how wide the tolerance is. */
  milli-amps/int

  constructor.private_ .value .milli-amps:

  /**
  Returns the lowest limit that is at least $milli-amps.

  Rounds up, so a channel is never limited below the current asked for.
    Throws if $milli-amps is above $MA-2200, the highest limit there is.

  Only needed for a current that is not known until runtime. A limit chosen
    while writing the code is better named by its constant.
  */
  constructor.at-least milli-amps/int:
    ALL.do: | code/IlimCode | if code.milli-amps >= milli-amps: return code
    throw "INVALID_ARGUMENT"

  /**
  Limits at 0.25 A.

  The names carry the typical limit and the tolerance around it is wide: the
    datasheet gives 0.19 A to 0.33 A for this one and 1.85 A to 2.55 A for
    $MA-2200. Size the margins accordingly.
  */
  static MA-250 ::= IlimCode.private_ 0x0 250
  /** Limits at 0.33 A. See $MA-250. */
  static MA-330 ::= IlimCode.private_ 0x1 330
  /** Limits at 0.40 A. See $MA-250. */
  static MA-400 ::= IlimCode.private_ 0x2 400
  /** Limits at 0.48 A. See $MA-250. */
  static MA-480 ::= IlimCode.private_ 0x3 480
  /** Limits at 0.56 A. See $MA-250. */
  static MA-560 ::= IlimCode.private_ 0x4 560
  /** Limits at 0.67 A. See $MA-250. */
  static MA-670 ::= IlimCode.private_ 0x5 670
  /** Limits at 0.72 A. See $MA-250. */
  static MA-720 ::= IlimCode.private_ 0x6 720
  /** Limits at 0.85 A. See $MA-250. */
  static MA-850 ::= IlimCode.private_ 0x7 850
  /** Limits at 1.00 A. See $MA-250. */
  static MA-1000 ::= IlimCode.private_ 0x8 1000
  /** Limits at 1.10 A. See $MA-250. */
  static MA-1100 ::= IlimCode.private_ 0x9 1100
  /** Limits at 1.25 A. The reset value on every channel. See $MA-250. */
  static MA-1250 ::= IlimCode.private_ 0xa 1250
  /** Limits at 1.50 A. See $MA-250. */
  static MA-1500 ::= IlimCode.private_ 0xb 1500
  /** Limits at 1.60 A. See $MA-250. */
  static MA-1600 ::= IlimCode.private_ 0xc 1600
  /** Limits at 1.75 A. See $MA-250. */
  static MA-1750 ::= IlimCode.private_ 0xd 1750
  /** Limits at 1.90 A. See $MA-250. */
  static MA-1900 ::= IlimCode.private_ 0xe 1900
  /** Limits at 2.20 A. See $MA-250. */
  static MA-2200 ::= IlimCode.private_ 0xf 2200

  /** Every limit, indexed by its $value. */
  static ALL/List ::= [
    MA-250, MA-330, MA-400, MA-480, MA-560, MA-670, MA-720, MA-850,
    MA-1000, MA-1100, MA-1250, MA-1500, MA-1600, MA-1750, MA-1900, MA-2200,
  ]

  stringify -> string: return "$(%.2f milli-amps / 1000.0) A"

/**
An inrush window a channel pair can be configured with.

The instances are the sixteen windows the `ILIM_DURATION` field can select.
  See $IlimCode for why they are a type rather than plain integers, and
  `Driver.set-inrush-mode` for what the window does.
*/
class InrushWindow:
  /** The `ILIM_DURATION` code selecting this window. See $ILIM-DURATION-MASK. */
  value/int
  /** How long the window lasts, in milliseconds. */
  ms/int

  constructor.private_ .value .ms:

  /**
  Returns the shortest window lasting at least $ms.

  Rounds up. Throws if $ms is longer than $MS-64.
  */
  constructor.at-least ms/int:
    ALL.do: | window/InrushWindow | if window.ms >= ms: return window
    throw "INVALID_ARGUMENT"

  /** No window at all. The reset value on every channel. */
  static MS-0 ::= InrushWindow.private_ 0x0 0
  /** A window of 2 ms. */
  static MS-2 ::= InrushWindow.private_ 0x1 2
  /** A window of 4 ms. */
  static MS-4 ::= InrushWindow.private_ 0x2 4
  /** A window of 6 ms. */
  static MS-6 ::= InrushWindow.private_ 0x3 6
  /** A window of 8 ms. */
  static MS-8 ::= InrushWindow.private_ 0x4 8
  /** A window of 10 ms. */
  static MS-10 ::= InrushWindow.private_ 0x5 10
  /** A window of 12 ms. */
  static MS-12 ::= InrushWindow.private_ 0x6 12
  /** A window of 16 ms. */
  static MS-16 ::= InrushWindow.private_ 0x7 16
  /** A window of 20 ms. */
  static MS-20 ::= InrushWindow.private_ 0x8 20
  /** A window of 24 ms. */
  static MS-24 ::= InrushWindow.private_ 0x9 24
  /** A window of 28 ms. */
  static MS-28 ::= InrushWindow.private_ 0xa 28
  /** A window of 32 ms. */
  static MS-32 ::= InrushWindow.private_ 0xb 32
  /** A window of 40 ms. */
  static MS-40 ::= InrushWindow.private_ 0xc 40
  /** A window of 48 ms. */
  static MS-48 ::= InrushWindow.private_ 0xd 48
  /** A window of 56 ms. */
  static MS-56 ::= InrushWindow.private_ 0xe 56
  /** A window of 64 ms. */
  static MS-64 ::= InrushWindow.private_ 0xf 64

  /** Every window, indexed by its $value. */
  static ALL/List ::= [
    MS-0, MS-2, MS-4, MS-6, MS-8, MS-10, MS-12, MS-16,
    MS-20, MS-24, MS-28, MS-32, MS-40, MS-48, MS-56, MS-64,
  ]

  stringify -> string: return "$ms ms"

/**
Builds the $REG-DEV-CONFIG1 or $REG-DEV-CONFIG2 value selecting $code.

$inrush gives how long the inrush window lasts. It defaults to
  $InrushWindow.MS-0, no window, which is the reset state. What the window
  does is decided by $CONFIG3-ILIM-CONFIG and $CONFIG3-INRUSH-LIMIT-MASK.

Needs no range checking: $IlimCode and $InrushWindow have no instances that
  do not fit their fields.
*/
build-ilim-config code/IlimCode --inrush/InrushWindow=InrushWindow.MS-0 -> int:
  return (inrush.value << ILIM-DURATION-SHIFT) | code.value

// DEV_CONFIG3 ($REG-DEV-CONFIG3) bits. This register is device wide: it holds
// no per-channel fields, only ones that apply to every channel at once.

/**
Disables reverse current blocking on all channels.

Set this when no external RCB FETs are fitted, and leave the RCB pins
  floating. Not functional on the BS part, which has no RCB at all.
*/
CONFIG3-RCB-DIS ::= 1 << 7
/**
Gives channels 3 and 4 their own current limit.

When set, channels 1 and 2 take their limit from $REG-DEV-CONFIG1 and
  channels 3 and 4 from $REG-DEV-CONFIG2. When clear, $REG-DEV-CONFIG1
  governs all four and $REG-DEV-CONFIG2 is ignored.
*/
CONFIG3-ILIM-SET ::= 1 << 6
/** Selects the current sense range above 800 mA rather than up to it. Not functional on BS. */
CONFIG3-ISNS-RANGE ::= 1 << 5
/** Channels 3 and 4 are wired in parallel. See $CONFIG3-PARALLEL-12. */
CONFIG3-PARALLEL-34 ::= 1 << 4
/**
Channels 1 and 2 are wired in parallel, roughly halving their on resistance.

The paralleling bits may only be written while all four bits of
  $REG-SW-STATE are zero, and not in a frame that sets one of them.
*/
CONFIG3-PARALLEL-12 ::= 1 << 3
/**
Turns the `ILIM_DURATION` window into a current limit timeout.

When clear the window is an inrush period: $CONFIG3-INRUSH-LIMIT-MASK picks
  the limit that applies during it, and $FAULT-ILIMIT is not reported while
  it lasts. When set the limit stays at the `ILIM_REG` setting throughout,
  the window becomes how long a channel may sit in current limit before its
  FET is switched off, and the fault is reported.
*/
CONFIG3-ILIM-CONFIG ::= 1 << 2
/** Mask of `INRUSH_LIMIT`, the limit during the inrush window. See the `INRUSH-LIMIT-*` codes. */
CONFIG3-INRUSH-LIMIT-MASK ::= 0x03

/** Limits inrush at the `ILIM_REG` setting, so the limit never changes. */
INRUSH-LIMIT-1X ::= 0
/** Limits inrush at twice the `ILIM_REG` setting. For incandescent lamps and other high-inrush loads. */
INRUSH-LIMIT-2X ::= 1
/** Limits inrush at half the `ILIM_REG` setting. For charging large capacitive loads. */
INRUSH-LIMIT-HALF ::= 2
/** Limits inrush at a fixed 2.2 A, whatever the `ILIM_REG` setting. */
INRUSH-LIMIT-FIXED ::= 3

// Structures describing the register map and the fault bits, for code that
// wants to present them rather than test them.

/** Read-only access. */
ACCESS-READ ::= "R"
/**
Read-only access, where reading the register clears the bits it returns.

Latching is configurable: with `FLT_LATCH` cleared in $REG-DEV-CONFIG5 these
  registers follow the live state instead of holding it until read.
*/
ACCESS-READ-CLEAR ::= "RC"
/** Read and write access. */
ACCESS-READ-WRITE ::= "RW"

/** A documented register of the device. See $REGISTERS. */
class Register:
  /** The 7-bit address the register lives at. */
  address/int
  /** The datasheet name of the register. */
  name/string
  /** What the register holds. */
  description/string
  /** How the register may be accessed. One of the `ACCESS-*` constants. */
  access/string

  constructor .address .name .description .access:

  stringify -> string: return "0x$(%02x address) $name"

/**
Every documented register, in address order.

Addresses that are missing from this list are reserved.
*/
REGISTERS/List ::= [
  Register REG-FAULT-TYPE-STAT "FAULT_TYPE_STAT" "Fault type, ORed across all channels" ACCESS-READ,
  Register REG-FAULT-CH-STAT "FAULT_CH_STAT" "Which channels have any fault at all" ACCESS-READ-CLEAR,
  Register REG-FAULT-GLOBAL-TYPE "FAULT_GLOBAL_TYPE" "Global faults" ACCESS-READ-CLEAR,
  Register REG-SHRT-VS-CH-STAT "SHRT_VS_CH_STAT" "Off-state short-to-VS, per channel" ACCESS-READ-CLEAR,
  Register REG-WB-OFF-CH-STAT "WB_OFF_CH_STAT" "Off-state wire break, per channel" ACCESS-READ-CLEAR,
  Register REG-WB-ON-CH-STAT "WB_ON_CH_STAT" "On-state wire break, per channel" ACCESS-READ-CLEAR,
  Register REG-ILIMIT-CH-STAT "ILIMIT_CH_STAT" "Current limit reached, per channel" ACCESS-READ-CLEAR,
  Register REG-THERMAL-SD-CH-STAT "THERMAL_SD_CH_STAT" "Thermal shutdown, per channel" ACCESS-READ-CLEAR,
  Register REG-THERMAL-WRN-CH-STAT "THERMAL_WRN_CH_STAT" "Thermal warning, per channel" ACCESS-READ,
  Register REG-RVRS-BLK-CH-STAT "RVRS_BLK_CH_STAT" "Reverse current blocked, per channel" ACCESS-READ-CLEAR,
  Register REG-ADC-RESULT-CH1-I "ADC_RESULT_CH1_I" "Current sense of channel 1, 8 MSBs" ACCESS-READ,
  Register REG-ADC-RESULT-CH1-I-LSB "ADC_RESULT_CH1_I_LSB" "Current sense of channel 1, 2 LSBs" ACCESS-READ,
  Register REG-ADC-RESULT-CH2-I "ADC_RESULT_CH2_I" "Current sense of channel 2, 8 MSBs" ACCESS-READ,
  Register REG-ADC-RESULT-CH2-I-LSB "ADC_RESULT_CH2_I_LSB" "Current sense of channel 2, 2 LSBs" ACCESS-READ,
  Register REG-ADC-RESULT-CH3-I "ADC_RESULT_CH3_I" "Current sense of channel 3, 8 MSBs" ACCESS-READ,
  Register REG-ADC-RESULT-CH3-I-LSB "ADC_RESULT_CH3_I_LSB" "Current sense of channel 3, 2 LSBs" ACCESS-READ,
  Register REG-ADC-RESULT-CH4-I "ADC_RESULT_CH4_I" "Current sense of channel 4, 8 MSBs" ACCESS-READ,
  Register REG-ADC-RESULT-CH4-I-LSB "ADC_RESULT_CH4_I_LSB" "Current sense of channel 4, 2 LSBs" ACCESS-READ,
  Register REG-ADC-RESULT-CH1-T "ADC_RESULT_CH1_T" "Temperature sense of channel 1" ACCESS-READ,
  Register REG-ADC-RESULT-CH2-T "ADC_RESULT_CH2_T" "Temperature sense of channel 2" ACCESS-READ,
  Register REG-ADC-RESULT-CH3-T "ADC_RESULT_CH3_T" "Temperature sense of channel 3" ACCESS-READ,
  Register REG-ADC-RESULT-CH4-T "ADC_RESULT_CH4_T" "Temperature sense of channel 4" ACCESS-READ,
  Register REG-ADC-RESULT-CH1-V "ADC_RESULT_CH1_V" "Output voltage of channel 1" ACCESS-READ,
  Register REG-ADC-RESULT-CH2-V "ADC_RESULT_CH2_V" "Output voltage of channel 2" ACCESS-READ,
  Register REG-ADC-RESULT-CH3-V "ADC_RESULT_CH3_V" "Output voltage of channel 3" ACCESS-READ,
  Register REG-ADC-RESULT-CH4-V "ADC_RESULT_CH4_V" "Output voltage of channel 4" ACCESS-READ,
  Register REG-ADC-RESULT-VS "ADC_RESULT_VS" "Supply voltage, 8 MSBs" ACCESS-READ,
  Register REG-ADC-RESULT-VS-LSB "ADC_RESULT_VS_LSB" "Supply voltage, 2 LSBs" ACCESS-READ,
  Register REG-SW-STATE "SW_STATE" "Per-channel switch state" ACCESS-READ-WRITE,
  Register REG-LED1-4-CTL "LED1_4_CTL" "LED 1 to 4 control" ACCESS-READ-WRITE,
  Register REG-LED5-8-CTL "LED5_8_CTL" "LED 5 to 8 control" ACCESS-READ-WRITE,
  Register REG-FS-SW-STATE "FS_SW_STATE" "Switch state assumed on a watchdog error" ACCESS-READ-WRITE,
  Register REG-DEV-CONFIG1 "DEV_CONFIG1" "Current limit and inrush for channels 1 and 2" ACCESS-READ-WRITE,
  Register REG-DEV-CONFIG2 "DEV_CONFIG2" "Current limit and inrush for channels 3 and 4" ACCESS-READ-WRITE,
  Register REG-DEV-CONFIG3 "DEV_CONFIG3" "Reverse blocking, sense range, paralleling" ACCESS-READ-WRITE,
  Register REG-DEV-CONFIG4 "DEV_CONFIG4" "Watchdog and wire-break thresholds" ACCESS-READ-WRITE,
  Register REG-DEV-CONFIG5 "DEV_CONFIG5" "ADC, auto retry, blanking, fault latching" ACCESS-READ-WRITE,
  Register REG-DEV-CONFIG6 "DEV_CONFIG6" "Per-channel reverse-blocking gate control" ACCESS-READ-WRITE,
  Register REG-FAULT-MASK "FAULT_MASK" "Per-fault-type masking of the FLT pin" ACCESS-READ-WRITE,
  Register REG-EN-WB-OFF "EN_WB_OFF" "Off-state wire-break diagnostics, per channel" ACCESS-READ-WRITE,
  Register REG-EN-WB-ON "EN_WB_ON" "On-state wire-break diagnostics, per channel" ACCESS-READ-WRITE,
  Register REG-EN-SHRT-VS "EN_SHRT_VS" "Off-state short-to-VS diagnostics, per channel" ACCESS-READ-WRITE,
  Register REG-ADC-ISNS-DIS "ADC_ISNS_DIS" "Skips the current sense conversion, per channel" ACCESS-READ-WRITE,
  Register REG-ADC-TSNS-DIS "ADC_TSNS_DIS" "Skips the temperature conversion, per channel" ACCESS-READ-WRITE,
  Register REG-ADC-VSNS-DIS "ADC_VSNS_DIS" "Skips the voltage conversion, per channel" ACCESS-READ-WRITE,
  Register REG-ADC-CONFIG1 "ADC_CONFIG1" "Measurement classes in the ADC round robin" ACCESS-READ-WRITE,
  Register REG-CRC-CONFIG "CRC_CONFIG" "Frame size and CRC selection" ACCESS-READ-WRITE,
]

/** Returns the $Register at $address, or null if $address is reserved. */
register-for address/int -> Register?:
  REGISTERS.do: | register/Register |
    if register.address == address: return register
  return null

/** A named bit of a fault register. See $FAULT-TYPE-BITS and $GLOBAL-FAULT-BITS. */
class FaultBit:
  /** The mask selecting the bit. */
  mask/int
  /** The datasheet name of the bit. */
  name/string
  /** What the bit means when it is set. */
  description/string
  /**
  The register naming the channels behind this fault, or null if there is none.

  Reading it is also what clears the fault, since these registers are
    $ACCESS-READ-CLEAR.
  */
  detail-register/int?

  constructor .mask .name .description --.detail-register=null:

  /** Whether the bit is set in $value. */
  is-set value/int -> bool: return (value & mask) != 0

  stringify -> string: return name

/**
The bits of $REG-FAULT-TYPE-STAT, most significant first.

These are also the bits of the fault byte the device returns on every frame,
  which is what `Driver.faults` holds.
*/
FAULT-TYPE-BITS/List ::= [
  FaultBit FAULT-SUPPLY "SUPPLY" "VDD undervoltage lockout or VS undervoltage"
      --detail-register=REG-FAULT-GLOBAL-TYPE,
  FaultBit FAULT-RVRS-BLK "RVRS_BLK" "Reverse current was blocked"
      --detail-register=REG-RVRS-BLK-CH-STAT,
  FaultBit FAULT-CHAN-TSD "CHAN_TSD" "A channel is in thermal shutdown"
      --detail-register=REG-THERMAL-SD-CH-STAT,
  FaultBit FAULT-ILIMIT "ILIMIT" "A channel hit its current limit"
      --detail-register=REG-ILIMIT-CH-STAT,
  FaultBit FAULT-WB-ON "WB_ON" "On-state wire break"
      --detail-register=REG-WB-ON-CH-STAT,
  FaultBit FAULT-WB-OFF "WB_OFF" "Off-state wire break"
      --detail-register=REG-WB-OFF-CH-STAT,
  FaultBit FAULT-SHRT-VS "SHRT_VS" "Off-state short to VS"
      --detail-register=REG-SHRT-VS-CH-STAT,
  FaultBit FAULT-GLOBAL "GLOBAL" "A global error or warning is pending"
      --detail-register=REG-FAULT-GLOBAL-TYPE,
]

/** The bits of $REG-FAULT-GLOBAL-TYPE, most significant first. */
GLOBAL-FAULT-BITS/List ::= [
  FaultBit GLOBAL-POR "POR" "The device reset and lost its configuration",
  FaultBit GLOBAL-CHIP-THERMALSD "CHIP_THERMALSD" "The controller die tripped its thermal warning",
  FaultBit GLOBAL-SPI-ERR "SPI_ERR" "A SPI format, clock or CRC error was seen",
  FaultBit GLOBAL-WD-ERR "WD_ERR" "The SPI watchdog timed out",
  FaultBit GLOBAL-VDD-UVLO "VDD_UVLO" "VDD dropped below its undervoltage lockout",
  FaultBit GLOBAL-VS-UV-WRN "VS_UV_WRN" "VS dropped below the undervoltage warning threshold",
  FaultBit GLOBAL-VS-UV "VS_UV" "VS dropped below the undervoltage protection threshold",
]

/**
Returns the $FAULT-TYPE-BITS that are set in $faults.

Takes the fault byte of a frame, or the contents of $REG-FAULT-TYPE-STAT.
  See `Driver.faults`.
*/
decode-faults faults/int -> List:
  return FAULT-TYPE-BITS.filter: | bit/FaultBit | bit.is-set faults

/**
Returns the $GLOBAL-FAULT-BITS that are set in $faults.

Takes the contents of $REG-FAULT-GLOBAL-TYPE. See `Driver.read-global-faults`.
*/
decode-global-faults faults/int -> List:
  return GLOBAL-FAULT-BITS.filter: | bit/FaultBit | bit.is-set faults
