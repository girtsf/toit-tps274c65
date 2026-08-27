import expect show *
import tps274c65 show *

import .fake-device

main:
  test-capture-trims-and-restores-the-adc
  test-capture-leaves-the-channel-on
  test-capture-streams-one-frame-per-sample
  test-capture-drops-the-frame-after-the-switch-write
  test-capture-spans-the-switch-write
  test-capture-records-changes-only
  test-capture-follows-a-ramp
  test-capture-truncates
  test-capture-sizes-itself-to-the-window
  test-capture-records-the-fault-byte
  test-capture-takes-the-faults-off-the-latch
  test-capture-switches-off-first
  test-capture-rejects-bad-arguments
  test-capture-conversions

/** A capture short enough to keep the tests quick. */
PRE ::= Duration --ms=2
POST ::= Duration --ms=4

/** Runs a capture on channel 1 with the test-sized window. */
capture_ driver/Driver --max-points/int?=null -> Capture:
  return capture-turn-on driver 1
      --pre=PRE
      --post=POST
      --max-points=max-points
      --settle=Duration.ZERO

/** Holds the channel 1 current conversion at $value for the whole capture. */
hold_ device/FakeDevice value/int -> none:
  device.contents[REG-ADC-RESULT-CH1-I] = value

/**
The round robin comes down to the one conversion, and goes back afterwards.

The three registers that does it are the caller's, so they have to come back
  exactly as they were.
*/
test-capture-trims-and-restores-the-adc:
  device := FakeDevice
  device.contents[REG-DEV-CONFIG5] = 0x10
  device.contents[REG-ADC-CONFIG1] = 0x02
  device.contents[REG-ADC-ISNS-DIS] = 0x06
  driver := Driver device
  hold_ device 0x20

  trimmed := []
  device.on-frame = :: | register |
    if register == REG-ADC-RESULT-CH1-I and trimmed.is-empty:
      trimmed.add device.contents[REG-ADC-CONFIG1]
      trimmed.add device.contents[REG-ADC-ISNS-DIS]
      trimmed.add device.contents[REG-DEV-CONFIG5]

  capture_ driver

  // What the ADC was doing while the trace was taken: temperature, output
  // voltage and supply out of the round, and every channel but this one.
  // DEV_CONFIG5 keeps the bits that were in it and gains two of its own.
  expect-equals [ADC1-TSNS-DIS | ADC1-VSNS-DIS | ADC1-VS-DIS, 0x0e,
                 0x10 | CONFIG5-ADC-EN | CONFIG5-FLT-LTCH-DIS]
      trimmed
  // And what the caller gets back.
  expect-equals 0x02 device.contents[REG-ADC-CONFIG1]
  expect-equals 0x06 device.contents[REG-ADC-ISNS-DIS]
  expect-equals 0x10 device.contents[REG-DEV-CONFIG5]

/** The capture turns the channel on and leaves it on. */
test-capture-leaves-the-channel-on:
  device := FakeDevice
  driver := Driver device
  hold_ device 0x20

  expect-not (driver.channel-on 1)
  capture_ driver
  expect (driver.channel-on 1)
  expect-equals 0x01 driver.switch-state
  expect-equals 0x01 device.contents[REG-SW-STATE]

/**
The loop spends one frame per conversion, not the two a read costs.

$Driver.read-register gives up the pipeline so a read-to-clear register is
  not addressed twice; a capture keeps it, which is safe because the ADC
  results are plain `R`.
*/
test-capture-streams-one-frame-per-sample:
  device := FakeDevice
  driver := Driver device
  hold_ device 0x20

  before := device.frames.size
  capture := capture_ driver
  loop-frames := device.frames.size - before

  // Every frame in the loop but the switch write asks for the one register.
  reads := 0
  (device.frames.copy before).do: | frame/ByteArray |
    if frame[0] == REG-ADC-RESULT-CH1-I: reads++
  // The setup and restore writes are in there too, so this is a floor rather
  // than an equality -- but the loop dominates, by thousands to one.
  expect reads > loop-frames / 2
  expect-equals 1 device.accesses[REG-SW-STATE]
  // The bus outruns the device by a wide margin, which is the point: the
  // conversion time is what limits the trace, not the frame rate.
  expect capture.frames > capture.size

/**
The frame after the switch write answers with SW_STATE, and is thrown away.

Keeping it would put a point of 0xf1 in the middle of the trace, right where
  the interesting part starts.
*/
test-capture-drops-the-frame-after-the-switch-write:
  device := FakeDevice
  driver := Driver device
  hold_ device 0x20

  capture := capture_ driver
  capture.size.repeat:
    expect-equals 0x20 capture.raw[it]

/** The trace covers both sides of the switch write, with it at zero. */
test-capture-spans-the-switch-write:
  device := FakeDevice
  driver := Driver device
  hold_ device 0x20

  capture := capture_ driver
  expect-equals 1 capture.channel
  expect capture.size >= 2
  expect-not capture.truncated
  // The first point is the baseline, taken before the write.
  expect capture.micros.first < 0
  // The last one is the end of the trace, after it.
  expect capture.micros.last > 0
  // Everything in between runs forwards.
  (capture.size - 1).repeat:
    expect capture.micros[it] <= capture.micros[it + 1]
  // The window asked for is the window taken, give or take a frame.
  expect capture.span-micros >= PRE.in-us + POST.in-us
  expect capture.frame-micros > 0.0
  expect-equals 1 capture.trigger-index
  // The dead zone after the write is not measurement, and is longer than
  // nothing.
  expect capture.valid-index >= capture.trigger-index
  expect capture.micros[capture.valid-index] >= ADC-CURRENT-SETTLING-TIME.in-us

/**
A point is a change of the conversion, not a frame.

A flat trace is two points, where it started and where it stopped, however
  many thousands of frames went into it.
*/
test-capture-records-changes-only:
  device := FakeDevice
  driver := Driver device
  hold_ device 0x20

  capture := capture_ driver
  expect-equals 2 capture.size
  expect-equals 0x20 capture.raw.first
  expect-equals 0x20 capture.raw.last
  expect capture.frames > 100

/** A moving conversion comes back as the shape it moved in. */
test-capture-follows-a-ramp:
  device := FakeDevice
  driver := Driver device
  // Walks the conversion up one step every 50 frames, so the trace has a
  // slope in it rather than a single edge.
  device.on-frame = :: | register |
    if register == REG-ADC-RESULT-CH1-I:
      steps := device.accesses[register] / 50
      device.contents[register] = min 0xff steps

  capture := capture_ driver
  expect capture.size > 10
  (capture.size - 1).repeat:
    expect capture.raw[it] <= capture.raw[it + 1]
  expect-equals 0 capture.raw.first
  expect capture.peak-milli-amps > 0.0

/** A trace with more changes in it than room stops recording and says so. */
test-capture-truncates:
  device := FakeDevice
  driver := Driver device
  device.on-frame = :: | register |
    if register == REG-ADC-RESULT-CH1-I:
      device.contents[register] = min 0xff (device.accesses[register] / 50)

  capture := capture_ driver --max-points=5
  expect capture.truncated
  expect-equals 5 capture.size

/**
The default bound on points is the window, not a number somebody picked.

Nothing changes faster than the device converts, so a capture sized that way
  cannot truncate on a trace the device produced.
*/
test-capture-sizes-itself-to-the-window:
  device := FakeDevice
  driver := Driver device
  // A new conversion every 128 us and never twice the same, so the trace
  // consumes points as fast as a real device can make it. The fake answers
  // frames far faster than that, which is exactly the case the bound is for:
  // reading harder does not produce more points.
  device.on-frame = :: | register |
    if register == REG-ADC-RESULT-CH1-I:
      tick := Time.monotonic-us / ADC-CONVERSION-TIME.in-us
      device.contents[register] = tick & 0xff

  capture := capture_ driver
  expect-not capture.truncated
  expect capture.size <= (default-capture-points --pre=PRE --post=POST)

  // And the bound really is the window: one point per conversion it can
  // hold, plus the margin the fault byte gets.
  short := default-capture-points --pre=Duration.ZERO --post=(Duration --ms=10)
  long := default-capture-points --pre=Duration.ZERO --post=(Duration --ms=20)
  expect-equals (10 * 1000 / ADC-CONVERSION-TIME.in-us + CAPTURE-POINT-MARGIN) short
  expect-equals (short - CAPTURE-POINT-MARGIN) * 2 + CAPTURE-POINT-MARGIN long

/**
The fault byte is recorded beside the conversion, and costs no frames.

Every frame carries FAULT_TYPE_STAT undelayed. It separates a current the
  device declined to sense from a current that was not there.
*/
test-capture-records-the-fault-byte:
  device := FakeDevice
  driver := Driver device
  hold_ device 0x20
  // ILIMIT comes up a little way into the capture and stays.
  raised := false
  device.on-frame = :: | register |
    if register == REG-ADC-RESULT-CH1-I and not raised:
      if device.accesses[register] > 200:
        device.faults = FAULT-ILIMIT
        raised = true

  capture := capture_ driver
  expect-equals FAULT-ILIMIT capture.faults-seen
  // The conversion never moved, so every point past the first two is one the
  // fault byte earned.
  expect capture.size >= 3
  expect-equals 0 capture.faults.first
  expect-not (capture.faulted 0 FAULT-ILIMIT)
  expect (capture.faulted capture.size - 1 FAULT-ILIMIT)
  // A capture that saw no fault says so plainly.
  clean := FakeDevice
  hold_ clean 0x20
  expect-equals 0 (capture_ (Driver clean)).faults-seen

/**
The trace is taken on the real-time fault path, not the latched one.

A capture reads no read-to-clear register, so on the latched path a fault
  could enter a trace and never leave it. $CONFIG5-FLT-LTCH-DIS picks the
  path that follows the condition, and goes back afterwards.
*/
test-capture-takes-the-faults-off-the-latch:
  device := FakeDevice
  device.contents[REG-DEV-CONFIG5] = 0x10
  driver := Driver device
  hold_ device 0x20

  during := []
  device.on-frame = :: | register |
    if register == REG-ADC-RESULT-CH1-I and during.is-empty:
      during.add device.contents[REG-DEV-CONFIG5]

  capture_ driver
  expect-equals [0x10 | CONFIG5-ADC-EN | CONFIG5-FLT-LTCH-DIS] during
  // Latching is the right default for everything that is not a trace, so it
  // has to come back.
  expect-equals 0x10 device.contents[REG-DEV-CONFIG5]

/**
A channel that is already on is switched off first.

The load needs time to discharge too, which is what `--settle` buys; these
  tests pass zero for it.
*/
test-capture-switches-off-first:
  device := FakeDevice
  driver := Driver device
  hold_ device 0x20
  driver.set-channel 1 --on=true
  expect-equals 0x01 driver.switch-state

  states := []
  device.on-frame = :: | register |
    if register == REG-ADC-RESULT-CH1-I and states.is-empty:
      states.add device.contents[REG-SW-STATE]

  capture := capture_ driver
  // Off for the baseline, back on for the event.
  expect-equals [0x00] states
  expect-equals 0x01 driver.switch-state
  expect capture.micros.first < 0

test-capture-rejects-bad-arguments:
  device := FakeDevice
  driver := Driver device
  expect-throw "INVALID_ARGUMENT": capture-turn-on driver 0
  expect-throw "INVALID_ARGUMENT": capture-turn-on driver 5
  expect-throw "INVALID_ARGUMENT": capture-turn-on driver 1 --max-points=0
  expect-throw "INVALID_ARGUMENT": capture-turn-on driver 1 --post=Duration.ZERO
  expect-throw "INVALID_ARGUMENT": capture-turn-on driver 1 --pre=(Duration --ms=-1)

/**
The eight bits a capture keeps are the top eight of a ten-bit conversion.

$Capture.raw has to be shifted up before $adc-milli-amps, which scales
  against the full ten bits.
*/
test-capture-conversions:
  device := FakeDevice
  driver := Driver device
  hold_ device 0x40

  capture := capture_ driver
  expect-equals (adc-milli-amps 0x100) (capture.milli-amps 0)
  expect-equals (capture.milli-amps 0) capture.to-milli-amps.first
  expect-equals capture.size capture.to-milli-amps.size
  expect-equals (adc-milli-amps 0x100) capture.peak-milli-amps
  // A quarter of full scale of the 3.25 A the 1 kOhm RSNS puts it at.
  expect ((capture.milli-amps 0) - 812.0).abs < 2.0
