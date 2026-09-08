/**
Serves the UI on a fake device, for taking screenshots without hardware.

Backed by the $FakeDevice the driver tests use, wound up with a fault
  scenario worth looking at: a channel in current limit while VS sags.

See `screenshot.sh`.
*/

import log
import math
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
  // A 1.25 A limit with a 16 ms inrush window at twice that, which is what
  // the capture below runs into.
  device.contents[tps274c65.REG-DEV-CONFIG1] = 0x7a
  device.contents[tps274c65.REG-DEV-CONFIG2] = 0x7a
  device.contents[tps274c65.REG-DEV-CONFIG3] = tps274c65.INRUSH-LIMIT-2X
  // The ADC, running, with a set of conversions to match: channels 1 and 3
  // carrying current into a supply that has sagged to 10.5 V, channels 2 and
  // 4 off and so reading nothing but their junction temperature. The
  // reserved bits of these registers read back as ones on a real device, and
  // $FakeDevice does the same without being told.
  device.contents[tps274c65.REG-DEV-CONFIG5] = tps274c65.CONFIG5-ADC-EN
  set-adc-conversion_ device tps274c65.REG-ADC-RESULT-VS 358  // 10.5 V.
  set-adc-conversion_ device tps274c65.REG-ADC-RESULT-CH1-I 151  // 479 mA.
  set-adc-conversion_ device tps274c65.REG-ADC-RESULT-CH3-I 378  // 1200 mA.
  device.contents[tps274c65.REG-ADC-RESULT-CH1-T] = 178  // 59 C.
  device.contents[tps274c65.REG-ADC-RESULT-CH2-T] = 186  // 45 C.
  device.contents[tps274c65.REG-ADC-RESULT-CH3-T] = 164  // 84 C.
  device.contents[tps274c65.REG-ADC-RESULT-CH4-T] = 198  // 24 C.
  device.contents[tps274c65.REG-ADC-RESULT-CH1-V] = 88  // 10.4 V.
  device.contents[tps274c65.REG-ADC-RESULT-CH3-V] = 87  // 10.2 V.
  install-inrush_ device
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

/**
Gives the fake device an inrush for a capture to find.

A capture trims the ADC round robin down to the one current conversion, which
  is how this tells one from the static readings the ADC box shows: while
  `ADC_CONFIG1` says every other class is dropped, the current conversion of
  whichever channel is switched on is synthesised from $inrush-conversion_
  rather than read out of the register file. Outside a capture the register
  file answers as it did before, so the ADC box keeps its own numbers.

Raises `ILIMIT` for as long as the fake load is being held at the limit, and
  puts the fault byte back as it found it once the capture is over. Following
  the condition like that is the real-time fault path, which is the one a
  capture selects; $FakeDevice models no latching of its own. That is
  what the fault lane under the chart draws, and on a real device it is the
  difference between a channel that drew nothing and a channel the device
  declined to sense.
*/
install-inrush_ device/FakeDevice -> none:
  trim := tps274c65.ADC1-TSNS-DIS | tps274c65.ADC1-VSNS-DIS | tps274c65.ADC1-VS-DIS
  since := {:}
  // The fault byte from before the capture, while one is running.
  saved/int? := null
  device.on-frame = :: | register/int |
    capturing := (device.contents.get tps274c65.REG-ADC-CONFIG1 --if-absent=: 0) == trim
    if not capturing:
      if saved != null:
        device.faults = saved
        saved = null
    else:
      index := tps274c65.ADC-CURRENT-REGISTERS.index-of register
      if index >= 0:
        if saved == null: saved = device.faults
        state := device.contents.get tps274c65.REG-SW-STATE --if-absent=: 0
        if (state & (1 << index)) == 0:
          // Off, so the register keeps whatever it held, and a channel that
          // is off is not in current limit whatever the scenario says. The
          // clock starts at the switch write, which is the next time this
          // runs.
          since.remove index
          device.faults = saved & ~tps274c65.FAULT-ILIMIT
        else:
          now := Time.monotonic-us
          start := since.get index --init=: now
          elapsed := now - start
          device.contents[register] = inrush-conversion_ elapsed
          // In limit from the write until the load is charged, which is
          // exactly the stretch $inrush-conversion_ reports as zero.
          limited := elapsed < (INRUSH-LIMITED-MS * 1000).to-int
          if limited: device.faults = saved | tps274c65.FAULT-ILIMIT
          else: device.faults = saved & ~tps274c65.FAULT-ILIMIT

/** How long the fake load is held at the current limit, in milliseconds. */
INRUSH-LIMITED-MS ::= 11.0
/** What the fake load draws once it is charged, in milliamps. */
INRUSH-STEADY-MA ::= 320.0
/** What the fake load is held at while it charges, in milliamps. */
INRUSH-PEAK-MA ::= 2500.0
/** How fast the fake load falls out of the limit, in milliseconds. */
INRUSH-DECAY-MS ::= 2.5

/**
The current conversion of a capacitive load $elapsed us into its turn-on.

Zero while the load is being held at the limit, then an exponential decay
  onto the steady draw once it is charged.

The zero is the point. A channel held at the current limit is regulating
  rather than fully on, and the sense is gated on being fully on, so the
  conversion register sits on what it last held -- it does not report the
  limit it is being held at. That is what a real trace looked like: nothing
  at all until the limit released, then the current falling away.
*/
inrush-conversion_ elapsed/int -> int:
  limited-us := (INRUSH-LIMITED-MS * 1000).to-int
  if elapsed < limited-us: return 0
  ms := (elapsed - limited-us) / 1000.0
  decayed := math.exp -ms / INRUSH-DECAY-MS
  milli-amps := INRUSH-STEADY-MA + (INRUSH-PEAK-MA - INRUSH-STEADY-MA) * decayed
  // Back through $tps274c65.adc-milli-amps, and down to the eight bits a
  // capture keeps.
  scale := tps274c65.ADC-FULL-SCALE-10-BIT * tps274c65.DEFAULT-SENSE-RESISTOR-OHMS
  span := (tps274c65.SENSE-RATIO * tps274c65.ADC-REFERENCE-MV).to-float
  raw := (milli-amps * scale / span).to-int
  return min 0xff (max 0 (raw >> 2))
