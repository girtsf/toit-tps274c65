import expect show *
import tps274c65 show *

import .fake-device

main:
  test-read-is-pipelined
  test-read-touches-the-register-once
  test-read-does-not-disturb-outputs
  test-read-picks-up-faults
  test-write
  test-set-channel
  test-set-leds
  test-write-switch-state-directly
  test-set-current-limit
  test-set-current-limit-split
  test-set-inrush-mode

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
