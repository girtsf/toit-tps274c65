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
