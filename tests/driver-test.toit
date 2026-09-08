import expect show *
import tps274c65 show *

import .fake-device

main:
  test-read-is-pipelined
  test-read-registers-is-pipelined
  test-read-touches-the-register-once
  test-read-does-not-disturb-outputs
  test-read-picks-up-faults
  test-global-faults-mask-the-phantom-bit
  test-write
  test-set-channel
  test-set-leds
  test-write-switch-state-directly
  test-set-current-limit
  test-set-current-limit-split
  test-set-inrush-mode
  test-set-reverse-blocking
  test-set-watchdog
  test-feed-watchdog
  test-set-fail-safe-state
  test-watchdog-timeouts
  test-power-config-is-locked-while-a-channel-is-on
  test-read-current-raw
  test-read-8-bit-results
  test-read-supply-voltage-raw
  test-set-adc
  test-adc-conversions
  test-read-adc-all

/**
A read has to spend two frames, because the device answers one frame late.

A single frame would return whatever the previous frame asked for, which for
  the first read of all is nothing.
*/
test-read-is-pipelined:
  device := FakeDevice
  device.contents[REG-DEV-CONFIG1] = 0x0a
  device.contents[REG-DEV-CONFIG4] = 0x02
  driver := Driver device

  expect-equals 0x0a (driver.read-register REG-DEV-CONFIG1)
  expect-equals 2 device.frames.size
  // The first frame delivers the address, the second collects the answer.
  // See $test-read-touches-the-register-once for why the second one asks
  // for FAULT_TYPE_STAT rather than repeating the address.
  expect-equals #[REG-DEV-CONFIG1, 0x00] device.frames[0]
  expect-equals #[REG-FAULT-TYPE-STAT, 0x00] device.frames[1]

  // A second read of a different register must not pick up the first one.
  expect-equals 0x02 (driver.read-register REG-DEV-CONFIG4)
  expect-equals 4 device.frames.size

  // Reading the same register twice in a row gives the same answer.
  expect-equals 0x02 (driver.read-register REG-DEV-CONFIG4)

/**
A burst read spends one frame per register, plus one to collect the last.

The device answers a read one frame late, so a stream of read frames each
  carrying the next address collects an answer per frame. That is half of
  what the same registers cost read one at a time.
*/
test-read-registers-is-pipelined:
  device := FakeDevice
  device.contents[REG-DEV-CONFIG1] = 0x0a
  device.contents[REG-DEV-CONFIG4] = 0x02
  device.contents[REG-LED5-8-CTL] = 0x07
  driver := Driver device

  registers := [REG-DEV-CONFIG1, REG-DEV-CONFIG4, REG-LED5-8-CTL]
  expect-equals #[0x0a, 0x02, 0x07] (driver.read-registers registers)
  expect-equals 4 device.frames.size
  expect-equals #[REG-DEV-CONFIG1, 0x00] device.frames[0]
  expect-equals #[REG-DEV-CONFIG4, 0x00] device.frames[1]
  expect-equals #[REG-LED5-8-CTL, 0x00] device.frames[2]
  // The collecting frame asks for FAULT_TYPE_STAT, for the reason
  // $test-read-touches-the-register-once gives.
  expect-equals #[REG-FAULT-TYPE-STAT, 0x00] device.frames[3]
  // Each register is addressed once, so a read-to-clear one keeps whatever
  // latched after it was read.
  registers.do: expect-equals 1 device.accesses[it]

  // The frames carry the switch state, like any other read.
  driver.set-channel 2 --on=true
  driver.read-registers [REG-DEV-CONFIG1]
  expect-equals #[REG-DEV-CONFIG1, 0b0010] device.frames[5]

  // An empty list costs nothing.
  expect-equals #[] (driver.read-registers [])
  expect-equals 7 device.frames.size

  // A bad address is caught before any of the burst goes out.
  expect-throw "INVALID_ARGUMENT": driver.read-registers [REG-DEV-CONFIG1, 0x80]
  expect-equals 7 device.frames.size

/**
Every ADC result comes back in one burst, decoded.

The eighteen result registers are one unbroken run of addresses, so the burst
  is 19 frames against the 36 the per-reading methods spend.
*/
test-read-adc-all:
  device := FakeDevice
  device.contents[REG-ADC-RESULT-CH1-I] = 0xff
  device.contents[REG-ADC-RESULT-CH1-I-LSB] = 0x03
  device.contents[REG-ADC-RESULT-CH2-I] = 0xc1
  device.contents[REG-ADC-RESULT-CH2-I-LSB] = 0x02
  device.contents[REG-ADC-RESULT-CH3-T] = 198
  device.contents[REG-ADC-RESULT-CH4-V] = 170
  device.contents[REG-ADC-RESULT-VS] = 0x99
  device.contents[REG-ADC-RESULT-VS-LSB] = 0x01
  device.faults = FAULT-ILIMIT

  driver := Driver device
  readings := driver.read-adc-all
  expect-equals 19 device.frames.size
  expect-equals #[REG-ADC-RESULT-CH1-I, 0x00] device.frames[0]
  expect-equals #[REG-ADC-RESULT-VS-LSB, 0x00] device.frames[17]
  expect-equals #[REG-FAULT-TYPE-STAT, 0x00] device.frames[18]

  // Ten bits for a current, the low two coming from the register beside it.
  expect-equals [1023, 0x306, 0, 0] readings.current-raw
  expect-near_ 3248.0 (readings.current 1)
  expect-near_ 2457.4 (readings.current 2)
  // Eight bits for a temperature and an output voltage.
  expect-equals [0, 0, 198, 0] readings.temperature-raw
  expect-near_ 24.1 (readings.temperature 3)
  expect-equals [0, 0, 0, 170] readings.output-voltage-raw
  expect-near_ 20.0 (readings.output-voltage 4)
  // And ten again for the supply.
  expect-equals 0x265 readings.supply-voltage-raw
  expect-near_ 17.98 readings.supply-voltage

  // The fault byte rides along on the frames, so it costs nothing.
  expect-equals FAULT-ILIMIT readings.faults

  expect-throw "INVALID_ARGUMENT": readings.current 0
  expect-throw "INVALID_ARGUMENT": readings.temperature 5
  expect-throw "INVALID_ARGUMENT": readings.output-voltage 5

  // The sense resistor and ratio are the driver's, not the call's.
  halved := (Driver device --sense-resistor=500.0).read-adc-all
  expect-near_ 6496.0 (halved.current 1)
  expect-equals 500.0 halved.sense-resistor
  expect-equals SENSE-RATIO halved.sense-ratio

  // The burst answers with what the registers hold, one read at a time or
  // eighteen at once.
  expect-equals (driver.read-current-raw 2) readings.current-raw[1]
  expect-equals (driver.read-supply-voltage-raw) readings.supply-voltage-raw

/**
The register asked for is addressed exactly once, however many frames it takes.

The collecting frame's address does not affect the value collected, so it must
  not be the register under read: pointing it there a second time would clear
  a read-to-clear register twice, throwing away anything that latched between
  the two frames. It addresses FAULT_TYPE_STAT instead, which is plain `R`.
*/
test-read-touches-the-register-once:
  device := FakeDevice
  device.read-to-clear.add REG-FAULT-GLOBAL-TYPE
  device.contents[REG-FAULT-GLOBAL-TYPE] = GLOBAL-POR | GLOBAL-VS-UV

  driver := Driver device
  expect-equals (GLOBAL-POR | GLOBAL-VS-UV) driver.read-global-faults

  // Once, not twice: a second access would clear a freshly latched fault.
  expect-equals 1 device.accesses[REG-FAULT-GLOBAL-TYPE]
  expect-equals REG-FAULT-GLOBAL-TYPE device.frames[0][0]
  expect-equals REG-FAULT-TYPE-STAT device.frames[1][0]

  // The latch really did clear, so a second read comes back empty.
  expect-equals 0 driver.read-global-faults

  // A fault that latches after the first read is still reported.
  device.contents[REG-FAULT-GLOBAL-TYPE] = GLOBAL-WD-ERR
  expect-equals GLOBAL-WD-ERR driver.read-global-faults

/**
Bit 7 of FAULT_GLOBAL_TYPE never reaches the caller.

A healthy device sets it however the datasheet describes it, so a caller
  comparing the raw byte against zero would never see a clean device.
*/
test-global-faults-mask-the-phantom-bit:
  device := FakeDevice
  driver := Driver device

  // Nothing wrong with the device, and it still answers 0x80 on the bus.
  expect-equals 0 driver.read-global-faults
  expect-equals 0x80 (driver.read-register REG-FAULT-GLOBAL-TYPE)

  // A real fault alongside the phantom bit comes back on its own.
  device.contents[REG-FAULT-GLOBAL-TYPE] = GLOBAL-WD-ERR
  expect-equals GLOBAL-WD-ERR driver.read-global-faults
  expect-equals (0x80 | GLOBAL-WD-ERR) (driver.read-register REG-FAULT-GLOBAL-TYPE)

/** Reading resends the switch state, so the outputs keep their state. */
test-read-does-not-disturb-outputs:
  device := FakeDevice
  driver := Driver device
  driver.set-channel 2 --on
  driver.set-channel 4 --on
  expected := (channel-mask 2) | (channel-mask 4)

  device.frames.clear
  driver.read-register REG-DEV-CONFIG1
  device.frames.do: | frame/ByteArray |
    expect-equals expected frame[1] & 0x0f
  expect-equals expected device.contents[REG-SW-STATE]
  expect-equals expected driver.switch-state

/** The fault byte is not pipelined, so it is current after any frame. */
test-read-picks-up-faults:
  device := FakeDevice
  driver := Driver device
  expect-equals 0 driver.faults

  device.faults = FAULT-SUPPLY | FAULT-GLOBAL
  driver.read-register REG-DEV-CONFIG1
  expect-equals (FAULT-SUPPLY | FAULT-GLOBAL) driver.faults

/** A write takes one frame, and reads back as written. */
test-write:
  device := FakeDevice
  driver := Driver device

  driver.write-register REG-DEV-CONFIG3 0x80
  expect-equals 1 device.frames.size
  expect-equals #[0x80 | REG-DEV-CONFIG3, 0x80] device.frames[0]
  expect-equals 0x80 (driver.read-register REG-DEV-CONFIG3)

/** Setting one channel leaves the others alone, and always writes. */
test-set-channel:
  device := FakeDevice
  driver := Driver device

  driver.set-channel 1 --on
  expect-equals 0b0001 driver.switch-state
  driver.set-channel 3 --on
  expect-equals 0b0101 driver.switch-state
  expect (driver.channel-on 1)
  expect (driver.channel-on 3)
  expect-not (driver.channel-on 2)

  frames := device.frames.size
  // Turning on a channel that is already on still writes SW_STATE. The write
  // is idempotent, and it is what feeds the watchdog, so a run of no-op calls
  // must not go silent on the bus.
  driver.set-channel 3 --on
  expect-equals frames + 1 device.frames.size
  expect-equals 0b0101 driver.switch-state
  expect-equals 0b0101 device.contents[REG-SW-STATE]

  driver.set-channel 1 --no-on
  expect-equals 0b0100 driver.switch-state
  expect-equals 0b0100 device.contents[REG-SW-STATE]

  driver.close
  expect-equals 0 driver.switch-state
  expect-equals 0 device.contents[REG-SW-STATE]

/** Setting one LED leaves the others alone, and writes only its register. */
test-set-leds:
  device := FakeDevice
  driver := Driver device

  driver.set-leds 1 --on
  expect-equals 0b0000_0001 driver.leds
  expect-equals 1 device.frames.size
  expect-equals #[0x80 | REG-LED1-4-CTL, 0b0001] device.frames[0]

  // LED5 to LED8 live in the other register, and it takes the high nibble
  // of $Driver.leds shifted down to its own bits [3:0].
  driver.set-leds 6 --on
  expect-equals 0b0010_0001 driver.leds
  expect-equals #[0x80 | REG-LED5-8-CTL, 0b0010] device.frames[1]
  expect-equals 0b0001 device.contents[REG-LED1-4-CTL]
  expect-equals 0b0010 device.contents[REG-LED5-8-CTL]

  // Turning one off leaves the other register untouched, on the bus as well.
  driver.set-leds 1 --no-on
  expect-equals 0b0010_0000 driver.leds
  expect-equals #[0x80 | REG-LED1-4-CTL, 0b0000] device.frames[2]
  expect-equals 0b0010 device.contents[REG-LED5-8-CTL]

  // Writing a control register directly keeps the shadow in step.
  driver.write-register REG-LED1-4-CTL 0b1010
  expect-equals 0b0010_1010 driver.leds

  expect-throw "INVALID_ARGUMENT": driver.set-leds 0 --on
  expect-throw "INVALID_ARGUMENT": driver.set-leds LED-COUNT + 1 --on

/**
Writing SW_STATE by hand keeps the shadow inside the four channels.

The shadow goes back out in the data byte of every read frame, so keeping a
  value with reserved bits set would make the next read throw instead of
  reaching the bus.
*/
test-write-switch-state-directly:
  device := FakeDevice
  driver := Driver device

  driver.write-register REG-SW-STATE 0b0101
  expect-equals 0b0101 driver.switch-state

  // Bits [7:4] of SW_STATE are reserved. The device gets what was asked for,
  // but only the four channel bits are carried in the read frames.
  driver.write-register REG-SW-STATE 0b0011_0010
  expect-equals 0b0010 driver.switch-state
  expect-equals #[0x80 | REG-SW-STATE, 0b0011_0010] device.frames[1]
  driver.read-register REG-DEV-CONFIG1
  expect-equals #[REG-DEV-CONFIG1, 0b0010] device.frames[2]

  // Reading it back gets those reserved bits as ones, so what comes over the
  // wire is 0xf2 and not 0x02. Confirmed on a real device.
  expect-equals 0xf2 (driver.read-register REG-SW-STATE)

/**
The current limit of all four channels is DEV_CONFIG1 plus a clear ILIM_SET.

ILIM_SET is already clear out of reset, so the read-modify-write of
  DEV_CONFIG3 puts back what it found. It still costs its three frames: the
  driver keeps no copy of the register and has to ask.
*/
test-set-current-limit:
  device := FakeDevice
  driver := Driver device

  driver.set-current-limit IlimCode.MA-2200
  expect-equals 4 device.frames.size
  expect-equals #[0x80 | REG-DEV-CONFIG1, 0x0f] device.frames[0]
  // Frames 1 and 2 read DEV_CONFIG3 -- reads take two -- and frame 3 writes
  // it back with ILIM_SET clear, which is where it already was.
  expect-equals #[REG-DEV-CONFIG3, 0x00] device.frames[1]
  expect-equals #[0x80 | REG-DEV-CONFIG3, 0x00] device.frames[3]

  // The inrush window shares the register, in the top nibble.
  driver.set-current-limit IlimCode.MA-1000 --inrush=InrushWindow.MS-6
  expect-equals #[0x80 | REG-DEV-CONFIG1, 0x38] device.frames[4]
  expect-equals 0x38 device.contents[REG-DEV-CONFIG1]

/**
Splitting the limit sets ILIM_SET, and only after both registers are written.

Channels 3 and 4 switch over to DEV_CONFIG2 the moment ILIM_SET goes in, so
  writing it first would run them against whatever DEV_CONFIG2 held before.
*/
test-set-current-limit-split:
  device := FakeDevice
  driver := Driver device

  driver.set-current-limit-split
      --channels-1-2=IlimCode.MA-400
      --channels-3-4=IlimCode.MA-2200
      --inrush-3-4=InrushWindow.MS-2
  expect-equals 5 device.frames.size
  expect-equals #[0x80 | REG-DEV-CONFIG1, 0x02] device.frames[0]
  expect-equals #[0x80 | REG-DEV-CONFIG2, 0x1f] device.frames[1]
  expect-equals #[0x80 | REG-DEV-CONFIG3, CONFIG3-ILIM-SET] device.frames[4]

  // Going back to one limit for all four channels clears the bit again, and
  // the read in the middle is what finds it set.
  driver.set-current-limit IlimCode.MA-1250
  expect-equals 9 device.frames.size
  expect-equals #[0x80 | REG-DEV-CONFIG1, 0x0a] device.frames[5]
  expect-equals #[0x80 | REG-DEV-CONFIG3, 0x00] device.frames[8]
  expect-equals 0x00 device.contents[REG-DEV-CONFIG3]

/**
DEV_CONFIG3 is read back before it is written, keeping the bits not asked about.

Each call reads what the device really holds, so the bits set by the call
  before it survive without the driver having to remember them.
*/
test-set-inrush-mode:
  device := FakeDevice
  driver := Driver device

  // A bit of DEV_CONFIG3 that has nothing to do with the inrush window.
  driver.write-register REG-DEV-CONFIG3 CONFIG3-RCB-DIS

  driver.set-inrush-mode --limit=INRUSH-LIMIT-2X
  expect-equals 4 device.frames.size
  expect-equals #[0x80 | REG-DEV-CONFIG3, CONFIG3-RCB-DIS | INRUSH-LIMIT-2X]
      device.frames[3]

  // The timeout flag lives in the same register, and the limit code goes
  // away with it. RCB_DIS stays, having been read back.
  driver.set-inrush-mode --timeout
  expect-equals #[0x80 | REG-DEV-CONFIG3, CONFIG3-RCB-DIS | CONFIG3-ILIM-CONFIG]
      device.frames[6]

  driver.set-inrush-mode --limit=INRUSH-LIMIT-HALF
  expect-equals #[0x80 | REG-DEV-CONFIG3, CONFIG3-RCB-DIS | INRUSH-LIMIT-HALF]
      device.frames[9]

  expect-throw "INVALID_ARGUMENT": driver.set-inrush-mode --limit=4

/**
Disabling reverse current blocking sets RCB_DIS, keeping the rest of DEV_CONFIG3.

The current limit and inrush settings share the register, and a board with
  no external RCB FETs still has to be able to configure them.
*/
test-set-reverse-blocking:
  device := FakeDevice
  driver := Driver device

  // Something in the register that has nothing to do with blocking.
  driver.write-register REG-DEV-CONFIG3 CONFIG3-ILIM-SET

  expect driver.reverse-blocking-enabled
  driver.set-reverse-blocking --no-enabled
  expect-equals CONFIG3-ILIM-SET | CONFIG3-RCB-DIS device.contents[REG-DEV-CONFIG3]
  expect-not driver.reverse-blocking-enabled

  // A later current limit call reads the register back, so RCB_DIS survives it.
  driver.set-current-limit-split
      --channels-1-2=IlimCode.MA-1250
      --channels-3-4=IlimCode.MA-1250
  expect-not driver.reverse-blocking-enabled

  driver.set-reverse-blocking --enabled
  expect-equals CONFIG3-ILIM-SET device.contents[REG-DEV-CONFIG3]
  expect driver.reverse-blocking-enabled

/**
A current conversion is assembled from two registers, the LSBs masked down.

ADC_RESULT_CHx_I_LSB has six reserved bits above the two that matter, and
  reserved bits read back as ones.
*/
/**
The power-path registers refuse to be written while a channel is on.

The device drops those writes silently -- no SPI_ERR, nothing in the fault
  byte -- so a caller that is not told goes on believing it changed a current
  limit it did not. Confirmed on hardware: DEV_CONFIG1, DEV_CONFIG2,
  DEV_CONFIG3 and DEV_CONFIG6 all read back unchanged after a write with one
  output up, and everything else in the map takes its write as usual.
*/
test-power-config-is-locked-while-a-channel-is-on:
  device := FakeDevice
  driver := Driver device

  // With everything off they are ordinary registers.
  POWER-CONFIG-REGISTERS.do: | register/int |
    driver.write-register register 0x05
    expect-equals 0x05 device.contents[register]

  driver.set-channel 1 --on=true
  POWER-CONFIG-REGISTERS.do: | register/int |
    expect-throw POWER-CONFIG-LOCKED-ERROR: driver.write-register register 0x0a
    // And nothing went out on the bus: the throw is ahead of the frame.
    expect-equals 0x05 device.contents[register]

  // One channel on locks all four, including the two that govern the other
  // pair. That is the device's rule, not a per-channel one.
  expect-throw POWER-CONFIG-LOCKED-ERROR:
      driver.set-current-limit IlimCode.MA-2200
  expect-throw POWER-CONFIG-LOCKED-ERROR:
      driver.set-current-limit-split --channels-1-2=IlimCode.MA-250 --channels-3-4=IlimCode.MA-250
  expect-throw POWER-CONFIG-LOCKED-ERROR:
      driver.set-inrush-mode --limit=INRUSH-LIMIT-2X
  expect-throw POWER-CONFIG-LOCKED-ERROR:
      driver.set-reverse-blocking --enabled=false

  // Everything outside that set still writes, DEV_CONFIG4 and DEV_CONFIG5
  // included despite the names.
  [REG-DEV-CONFIG4, REG-DEV-CONFIG5, REG-FAULT-MASK, REG-ADC-CONFIG1,
   REG-LED1-4-CTL, REG-EN-WB-ON].do: | register/int |
    driver.write-register register 0x03
    expect-equals 0x03 device.contents[register]

  // And they go back to being writable once the outputs are down.
  driver.set-channel 1 --on=false
  POWER-CONFIG-REGISTERS.do: | register/int |
    driver.write-register register 0x0a
    expect-equals 0x0a device.contents[register]

test-read-current-raw:
  device := FakeDevice
  device.contents[REG-ADC-RESULT-CH2-I] = 0xc1
  device.contents[REG-ADC-RESULT-CH2-I-LSB] = 0x02

  driver := Driver device
  expect-equals 0x306 (driver.read-current-raw 2)
  // Two registers in one burst: an address frame each, and one to collect
  // the second answer.
  expect-equals 3 device.frames.size
  expect-equals #[REG-ADC-RESULT-CH2-I, 0x00] device.frames[0]
  expect-equals #[REG-ADC-RESULT-CH2-I-LSB, 0x00] device.frames[1]
  expect-equals #[REG-FAULT-TYPE-STAT, 0x00] device.frames[2]

  // Full scale is 3.25 A with the recommended 1 kOhm sense resistor.
  device.contents[REG-ADC-RESULT-CH1-I] = 0xff
  device.contents[REG-ADC-RESULT-CH1-I-LSB] = 0x03
  expect-equals 1023 (driver.read-current-raw 1)
  expect-near_ 3248.0 (driver.read-current 1)
  // Halving the sense resistor doubles the current a conversion stands for.
  expect-near_ 6496.0 ((Driver device --sense-resistor=500.0).read-current 1)

  expect-throw "INVALID_ARGUMENT": driver.read-current-raw 0
  expect-throw "INVALID_ARGUMENT": driver.read-current-raw 5

/** The temperature and output voltage results are one register each. */
test-read-8-bit-results:
  device := FakeDevice
  driver := Driver device

  // 198 is where 25 degrees lands: the scale is coarse enough that a count
  // is nearly two degrees.
  device.contents[REG-ADC-RESULT-CH3-T] = 198
  expect-equals 198 (driver.read-temperature-raw 3)
  expect-equals 2 device.frames.size
  expect-near_ 24.1 (driver.read-temperature 3)

  // 20 V of a 30 V scale.
  device.contents[REG-ADC-RESULT-CH4-V] = 170
  expect-equals 170 (driver.read-output-voltage-raw 4)
  expect-near_ 20.0 (driver.read-output-voltage 4)

  expect-throw "INVALID_ARGUMENT": driver.read-temperature-raw 5
  expect-throw "INVALID_ARGUMENT": driver.read-output-voltage-raw 0

/** The supply voltage is 10 bits, like the current, and runs to 30 V. */
test-read-supply-voltage-raw:
  device := FakeDevice
  device.contents[REG-ADC-RESULT-VS] = 0x99
  device.contents[REG-ADC-RESULT-VS-LSB] = 0x01

  driver := Driver device
  expect-equals 0x265 (driver.read-supply-voltage-raw)
  expect-equals 3 device.frames.size
  expect-near_ 17.98 (driver.read-supply-voltage)

/**
Switching the ADC on keeps the rest of DEV_CONFIG5, reserved bits aside.

The register also holds the fault latching and auto retry settings, and its
  top two bits are reserved and read back as ones -- which must not be
  written back out.
*/
test-set-adc:
  device := FakeDevice
  driver := Driver device

  // Something in the register that has nothing to do with the ADC.
  driver.write-register REG-DEV-CONFIG5 0x10  // AUTO_RETRY_DIS.

  expect-not driver.adc-enabled
  driver.set-adc --enabled
  expect-equals 0x10 | CONFIG5-ADC-EN device.contents[REG-DEV-CONFIG5]
  expect driver.adc-enabled

  driver.set-adc --no-enabled
  expect-equals 0x10 device.contents[REG-DEV-CONFIG5]
  expect-not driver.adc-enabled

/** The conversions the datasheet's own numbers pin down. */
test-adc-conversions:
  // TSNS is 2.57 V at -40 degrees, 2.17 V at 25 and 1.55 V at 125, against a
  // 2.8 V reference.
  // The datasheet gives those to three digits, which is worth about a degree
  // once it is turned back into a conversion.
  expect-near_ -40.0 (adc-celsius (adc-full-scale-fraction_ 2.57 255)) --epsilon=1.0
  expect-near_ 25.0 (adc-celsius (adc-full-scale-fraction_ 2.17 255)) --epsilon=1.0
  expect-near_ 125.0 (adc-celsius (adc-full-scale-fraction_ 1.55 255)) --epsilon=1.0

  // VOUTSNS is 1.87 V with 20 V on the output.
  expect-near_ 20.0 (adc-volts (adc-full-scale-fraction_ 1.87 255)
      --full-scale=ADC-FULL-SCALE-8-BIT)

  // Zero converts to zero everywhere but the temperature, whose scale is
  // upside down and offset.
  expect-near_ 0.0 (adc-milli-amps 0)
  expect-near_ 0.0 (adc-volts 0 --full-scale=ADC-FULL-SCALE-10-BIT)
  expect-near_ 373.5 (adc-celsius 0)

  // A count is 3.17 mA of current and 29 mV of supply voltage.
  expect-near_ 3.17 (adc-milli-amps 1)
  expect-near_ 0.0293 (adc-volts 1 --full-scale=ADC-FULL-SCALE-10-BIT) --epsilon=0.0001

/** Returns the conversion that a reading of $volts against the reference is. */
adc-full-scale-fraction_ volts/float full-scale/int -> int:
  return (volts * 1000 * full-scale / ADC-REFERENCE-MV).round

expect-near_ expected/float actual/float --epsilon/float=0.05 -> none:
  expect (expected - actual).abs <= epsilon
      --message="expected $expected, got $actual"

/**
Enabling the watchdog sets the timeout with it, leaving the wire-break
  fields of the register alone.
*/
test-set-watchdog:
  device := FakeDevice
  driver := Driver device

  // The reset contents: watchdog off, WB_ON_THD at its reset code of 2.
  driver.write-register REG-DEV-CONFIG4 0x02

  expect-not driver.watchdog-enabled
  expect-equals WatchdogTimeout.US-400 driver.watchdog-timeout

  driver.set-watchdog --enabled --timeout=WatchdogTimeout.MS-800
  expect-equals 0x02 | CONFIG4-WD-EN | 0x40 device.contents[REG-DEV-CONFIG4]
  expect driver.watchdog-enabled
  expect-equals WatchdogTimeout.MS-800 driver.watchdog-timeout

  // A shorter timeout replaces the old code rather than ORing into it.
  driver.set-watchdog --enabled --timeout=WatchdogTimeout.MS-400
  expect-equals 0x02 | CONFIG4-WD-EN | 0x20 device.contents[REG-DEV-CONFIG4]
  expect-equals WatchdogTimeout.MS-400 driver.watchdog-timeout

  // Disabling keeps the timeout code and the wire-break bits.
  driver.set-watchdog --no-enabled --timeout=WatchdogTimeout.MS-400
  expect-equals 0x02 | 0x20 device.contents[REG-DEV-CONFIG4]
  expect-not driver.watchdog-enabled
  expect-equals WatchdogTimeout.MS-400 driver.watchdog-timeout

/** Feeding rewrites the switch state without moving an output. */
test-feed-watchdog:
  device := FakeDevice
  driver := Driver device

  driver.set-channel 2 --on
  frames := device.frames.size

  driver.feed-watchdog
  expect-equals frames + 1 device.frames.size
  expect-equals #[0x80 | REG-SW-STATE, 0b0010] device.frames[frames]
  expect-equals 0b0010 driver.switch-state
  expect-equals 0b0010 device.contents[REG-SW-STATE]

  // With every output down it still goes out on the bus.
  driver.switch-state = 0
  frames = device.frames.size
  driver.feed-watchdog
  expect-equals frames + 1 device.frames.size
  expect-equals 0 driver.switch-state

/** The fail-safe state is written before the bit that puts it to use. */
test-set-fail-safe-state:
  device := FakeDevice
  driver := Driver device

  // Something in DEV_CONFIG5 that has nothing to do with the fail-safe state.
  driver.write-register REG-DEV-CONFIG5 CONFIG5-ADC-EN

  expect-null driver.fail-safe-state

  frames := device.frames.size
  driver.set-fail-safe-state 0b0101
  expect-equals #[0x80 | REG-FS-SW-STATE, 0b0101] device.frames[frames]
  expect-equals 0b0101 device.contents[REG-FS-SW-STATE]
  expect-equals CONFIG5-ADC-EN | CONFIG5-SW-FS-CFG device.contents[REG-DEV-CONFIG5]
  expect-equals 0b0101 driver.fail-safe-state

  // All four outputs down on a watchdog error is a state like any other,
  // and is not the same as holding.
  driver.set-fail-safe-state 0
  expect-equals 0 device.contents[REG-FS-SW-STATE]
  expect-equals 0 driver.fail-safe-state

  // Null holds, and leaves FS_SW_STATE alone.
  driver.write-register REG-FS-SW-STATE 0b1010
  driver.set-fail-safe-state null
  expect-equals 0b1010 device.contents[REG-FS-SW-STATE]
  expect-equals CONFIG5-ADC-EN device.contents[REG-DEV-CONFIG5]
  expect-null driver.fail-safe-state

  expect-throw "INVALID_ARGUMENT": driver.set-fail-safe-state 0b1_0000

/** The watchdog timeouts are the four the `WD_TO` field can hold. */
test-watchdog-timeouts:
  expect-equals 4 WatchdogTimeout.ALL.size
  WatchdogTimeout.ALL.size.repeat: | index/int |
    expect-equals index WatchdogTimeout.ALL[index].value

  expect-equals (Duration --us=400) WatchdogTimeout.US-400.duration
  expect-equals (Duration --ms=1200) WatchdogTimeout.MS-1200.duration

  // Rounds up to the next code the device has, and takes an exact one as is.
  expect-equals WatchdogTimeout.US-400
      WatchdogTimeout.at-least (Duration --us=1)
  expect-equals WatchdogTimeout.MS-400
      WatchdogTimeout.at-least (Duration --us=401)
  expect-equals WatchdogTimeout.MS-800
      WatchdogTimeout.at-least (Duration --ms=800)
  expect-equals WatchdogTimeout.MS-1200
      WatchdogTimeout.at-least (Duration --ms=801)
  expect-throw "INVALID_ARGUMENT":
    WatchdogTimeout.at-least (Duration --ms=1201)
