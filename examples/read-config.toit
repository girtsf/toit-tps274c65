/** Dumps the TPS274C65 configuration. */

import spi
import tps274c65

// Pin mapping.
SCK ::= 12
MOSI ::= 11
MISO ::= 13
CS ::= 10

/**
Registers to dump: address, name, value expected after reset, and what that
  expected value means.

The meaning describes the *expected* value, not whatever the device returns,
  so it is only printed when the two agree.
*/
REGISTERS ::= [
  [tps274c65.REG-DEV-CONFIG1, "DEV_CONFIG1", 0x0a, "current limit 1.25 A"],
  [tps274c65.REG-DEV-CONFIG2, "DEV_CONFIG2", 0x0a, "current limit 1.25 A"],
  [tps274c65.REG-DEV-CONFIG3, "DEV_CONFIG3", 0x00, "RCB on, no paralleling"],
  [tps274c65.REG-DEV-CONFIG4, "DEV_CONFIG4", 0x02, "watchdog off"],
  [tps274c65.REG-DEV-CONFIG5, "DEV_CONFIG5", 0xc0, "ADC off, faults latched"],
  [tps274c65.REG-DEV-CONFIG6, "DEV_CONFIG6", 0xff, "RCB on all four channels"],
  [tps274c65.REG-FAULT-MASK, "FAULT_MASK", 0x00, "nothing masked"],
  [tps274c65.REG-EN-WB-OFF, "EN_WB_OFF", 0xf0, "diagnostics off"],
  [tps274c65.REG-EN-WB-ON, "EN_WB_ON", 0xf0, "diagnostics off"],
  [tps274c65.REG-EN-SHRT-VS, "EN_SHRT_VS", 0xf0, "diagnostics off"],
  [tps274c65.REG-CRC-CONFIG, "CRC_CONFIG", 0xfc, "16-bit frames, no CRC"],
]

main:
  bus := spi.Bus --clock=SCK --mosi=MOSI --miso=MISO
  device := bus.device
      --cs=CS
      --frequency=1_000_000
      --mode=tps274c65.SPI-MODE
      // TPS274C65 requires at least 45ns between CS dropping and first SCLK.
      --cs-setup-cycles=1
  driver := tps274c65.Driver device
  try:
    // The device latches its global faults, so the first read reports
    // everything that has happened since the last one. Read twice: the
    // second read is the one that says what is wrong *now*.
    driver.read-global-faults
    print "global faults: 0x$(%02x driver.read-global-faults)"
    print "fault type:    0x$(%02x driver.faults)"
    print ""
    REGISTERS.do: | entry/List |
      register/int := entry[0]
      name/string := entry[1]
      expected/int := entry[2]
      meaning/string := entry[3]
      value := driver.read-register register
      // Only describe the value when it is the one the description is about.
      note := value == expected
          ? meaning
          : "DIFFERS, expected 0x$(%02x expected) at reset"
      print "  0x$(%02x register) $(%-12s name) -> 0x$(%02x value)  $note"
  finally:
    driver.close
    device.close
    bus.close
