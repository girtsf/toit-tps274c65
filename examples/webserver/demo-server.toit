/**
Serves the UI on a fake device, for taking screenshots without hardware.

Backed by the $FakeDevice the driver tests use, wound up with a fault
  scenario worth looking at: a channel in current limit while VS sags.

See `screenshot.sh`.
*/

import log
import net
import tps274c65

import ...tests.fake-device
import .api

/** The port the demo is served on. */
PORT ::= 8099

main:
  // The http package logs every request at debug level, which buries the one
  // line worth reading here.
  log.set-default (log.default.with-level log.WARN-LEVEL)
  device := FakeDevice
  // SUPPLY, ILIMIT and GLOBAL, the three the scenario below explains.
  device.faults = tps274c65.FAULT-SUPPLY | tps274c65.FAULT-ILIMIT | tps274c65.FAULT-GLOBAL
  device.contents[tps274c65.REG-FAULT-GLOBAL-TYPE] = tps274c65.GLOBAL-VS-UV
  device.contents[tps274c65.REG-ILIMIT-CH-STAT] = 0b0010  // Channel 2.
  // The reset values of the current-limit registers, so the box that reads
  // them has something real to show.
  device.contents[tps274c65.REG-DEV-CONFIG1] = 0x0a
  device.contents[tps274c65.REG-DEV-CONFIG2] = 0x0a
  // The ADC, running, with a set of conversions to match: channels 1 and 3
  // carrying current into a supply that has sagged to 10.5 V, channels 2 and
  // 4 off and so reading nothing but their junction temperature. The reserved
  // bits of the registers that have them read back as ones, the way they do
  // on a real device.
  device.reserved-ones[tps274c65.REG-DEV-CONFIG5] = 0xc0
  device.contents[tps274c65.REG-DEV-CONFIG5] = tps274c65.CONFIG5-ADC-EN
  [
    tps274c65.REG-ADC-RESULT-CH1-I-LSB, tps274c65.REG-ADC-RESULT-CH2-I-LSB,
    tps274c65.REG-ADC-RESULT-CH3-I-LSB, tps274c65.REG-ADC-RESULT-CH4-I-LSB,
    tps274c65.REG-ADC-RESULT-VS-LSB,
  ].do: device.reserved-ones[it] = 0xfc
  set-adc-conversion_ device tps274c65.REG-ADC-RESULT-VS 358  // 10.5 V.
  set-adc-conversion_ device tps274c65.REG-ADC-RESULT-CH1-I 151  // 479 mA.
  set-adc-conversion_ device tps274c65.REG-ADC-RESULT-CH3-I 378  // 1200 mA.
  device.contents[tps274c65.REG-ADC-RESULT-CH1-T] = 178  // 59 C.
  device.contents[tps274c65.REG-ADC-RESULT-CH2-T] = 186  // 45 C.
  device.contents[tps274c65.REG-ADC-RESULT-CH3-T] = 164  // 84 C.
  device.contents[tps274c65.REG-ADC-RESULT-CH4-T] = 198  // 24 C.
  device.contents[tps274c65.REG-ADC-RESULT-CH1-V] = 88  // 10.4 V.
  device.contents[tps274c65.REG-ADC-RESULT-CH3-V] = 87  // 10.2 V.
  device.read-to-clear.add tps274c65.REG-FAULT-GLOBAL-TYPE
  device.read-to-clear.add tps274c65.REG-ILIMIT-CH-STAT
  driver := tps274c65.Driver device
  network := net.open
  try:
    print "demo UI on http://localhost:$PORT/"
    (Ui driver).listen network PORT
  finally:
    network.close

/**
Puts the 10-bit conversion $raw into $register and the LSB register above it.

The two ten-bit results, the currents and the supply voltage, are split over
  a register pair whose second half holds the bottom two bits.
*/
set-adc-conversion_ device/FakeDevice register/int raw/int -> none:
  device.contents[register] = raw >> 2
  device.contents[register + 1] = raw & 0x03
