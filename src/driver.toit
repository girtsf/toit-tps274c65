import spi

import .registers

/** The SPI mode of the device: CPOL = 0, CPHA = 1. */
SPI-MODE ::= 1

/** The number of switch channels the device has. */
CHANNEL-COUNT ::= 4

/** The number of LEDs the device drives. */
LED-COUNT ::= 8

/** Returns the bit mask for $channel. */
channel-mask channel/int -> int:
  if not 1 <= channel <= CHANNEL-COUNT: throw "INVALID_ARGUMENT"
  return 1 << (channel - 1)

/** Returns the bit mask for $led. See $Driver.leds. */
led-mask led/int -> int:
  if not 1 <= led <= LED-COUNT: throw "INVALID_ARGUMENT"
  return 1 << (led - 1)

/**
Builds a 16-bit daisy-chain read frame for $register.

The read frame carries a switch-state field, so $switch-state must be the
  state the outputs should have after the frame. See $Driver.read-register.
*/
build-read-frame register/int --switch-state/int -> int:
  check-register_ register
  check-switch-state_ switch-state
  return (register << 8) | switch-state

/**
Builds a 16-bit daisy-chain write frame putting $value into $register.

The write frame has no switch-state field, so it leaves the outputs alone
  unless $register is $REG-SW-STATE.
*/
build-write-frame register/int value/int -> int:
  check-register_ register
  if not 0 <= value <= 0xff: throw "INVALID_ARGUMENT"
  return 0x8000 | (register << 8) | value

check-register_ register/int -> none:
  if not 0 <= register <= 0x7f: throw "INVALID_ARGUMENT"

check-switch-state_ state/int -> none:
  if not 0 <= state < (1 << CHANNEL-COUNT): throw "INVALID_ARGUMENT"

/**
A minimal driver for the TI TPS274C65 quad-channel smart high-side switch.

This driver speaks the 16-bit daisy-chain frame format, which is what the
  device uses out of reset when its DSPI pin is high. It assumes a single
  device per chip select, so one frame per chip-select pulse.

Reads are pipelined by the device and come back one frame late, so
  $read-register spends two frames on each read. See its description.

Reserved bits read back as ones rather than zeros, so a register that the
  datasheet gives a reset value of 0Fh can read FFh. Mask register contents
  down to the documented field width before comparing them.
*/
class Driver:
  spi_device_/spi.Device
  switch-state_/int := 0
  leds_/int := 0
  faults_/int := 0

  /**
  Constructs a driver talking to given SPI device.

  The device must be configured for $SPI-MODE.
  */
  constructor .spi_device_:

  /**
  The fault byte the device returned on the most recent frame.

  Every frame carries $REG-FAULT-TYPE-STAT for free, so this is up to date
    as of the last call that touched the bus. Test it against the `FAULT-*`
    constants, and read the matching per-channel register to find out which
    channel is at fault and to clear the latch.

  Returns 0 before the first frame.
  */
  faults -> int: return faults_

  /**
  The switch state most recently sent to the device.

  Bit 0 is channel 1, bit 3 is channel 4. A set bit means the FET is on,
    provided the DO_EN pin is also high.
  */
  switch-state -> int: return switch-state_

  /** Sets the switch state to $value. See $switch-state. */
  switch-state= value/int -> none:
    check-switch-state_ value
    write-register REG-SW-STATE value

  /**
  Turns $channel on or off, leaving the other channels alone.

  Channels are numbered 1 to $CHANNEL-COUNT.
  */
  set-channel channel/int --on/bool -> none:
    mask := channel-mask channel
    updated := on ? switch-state_ | mask : switch-state_ & ~mask
    write-register REG-SW-STATE updated

  /** Whether $channel was last set on. See $switch-state. */
  channel-on channel/int -> bool:
    return (switch-state_ & (channel-mask channel)) != 0

  /**
  The LED state most recently sent to the device.

  Returns 0 before the first LED write, which matches the reset state.
  */
  leds -> int: return leds_

  /**
  Turns the LED numbered $num on or off, leaving the other LEDs alone.

  LEDs are numbered 1 to $LED-COUNT. Costs one frame: the two control
    registers hold four LEDs each, and only the one holding $num is written.

  See $leds.
  */
  set-leds num/int --on/bool -> none:
    mask := led-mask num
    updated := on ? leds_ | mask : leds_ & ~mask
    if num <= 4: write-register REG-LED1-4-CTL (updated & 0x0f)
    else: write-register REG-LED5-8-CTL (updated >> 4)

  /**
  Reads the register at $register.

  Costs two frames. The device answers a read one frame late: the data byte
    of a frame carries whatever register the *previous* frame asked for, so
    the address has to go out in one frame and be collected in the next.
    The fault byte is not delayed, and is current in both frames.

  Only the first frame carries $register. The second one addresses
    $REG-FAULT-TYPE-STAT instead, because the address it carries is
    irrelevant to the value collected and addressing $register twice would
    read it twice. That matters for the read-to-clear registers: a second
    read would clear anything that latched in between, losing a fault that
    arrived during the pair. $REG-FAULT-TYPE-STAT is safe to point at,
    being plain `R` -- its bits clear when the matching detail register is
    read, not when it is read itself -- and its contents come back for free
    in the fault byte anyway. TI gives the same advice on E2E: the address
    in the collecting frame "can be anything (that isn't read-clear, to
    avoid unintentional read-clear-ing)".

  Refreshes $faults.

  A read frame also carries the switch state, so both frames resend
    $switch-state and leave the outputs as they are.

  This is how the part is meant to work, not a defect. TI states it on E2E:
    "In daisy chain mode, the read output is delayed from the read request by
    one SPI frame", and "you essentially have to do a double transaction: one
    write transaction to specify which address to read and a second
    transaction to read payload". The sibling TPS2HCS10-Q1 says so in its
    datasheet outright: "the 16-bit wide Data Out in the SDO output is always
    for the previous SPI command frame (Read or Write)".

  SLVSFZ2C itself does not. Figures 8-11 and 8-13 draw DATA OUT starting one
    clock after the address ends, which would be a same-frame answer; those
    figures are wrong. Section 8.3.2 gives the hint, calling addressable SPI
    faster "as the direct data transmission will happen immediately once the
    address is transmitted" -- addressable mode really does answer in-frame,
    and daisy chain does not.

  Confirmed on the bench: bit-banging the identical frames shows the same
    shift, so it is the device and not the controller, and setting `D24BIT`
    for 24-bit daisy-chain frames does not change it.
  */
  read-register register/int -> int:
    // Discard the first answer: it belongs to whatever was asked for before.
    transfer_ (build-read-frame register --switch-state=switch-state_)
    return transfer_
        build-read-frame REG-FAULT-TYPE-STAT --switch-state=switch-state_

  /**
  Writes $value into the register at $register.

  Takes one frame. Only reads pay for the pipeline.

  Refreshes $faults from the fault byte returned in the same frame, and
    tracks $switch-state and $leds when $register is one of theirs, keeping
    only the bits those registers document.

  A write fills the read pipeline the same way a read does: the frame after
    this one carries the new contents of $register. $read-register does not
    rely on that, and always sends its own two frames.
  */
  write-register register/int value/int -> none:
    transfer_ (build-write-frame register value)
    // Mask the cached copies down to the bits the registers really have. The
    // switch state goes back out in the data byte of every read frame, so a
    // raw write of a value with reserved bits set would otherwise poison
    // every later read.
    if register == REG-SW-STATE: switch-state_ = value & 0x0f
    else if register == REG-LED1-4-CTL: leds_ = (leds_ & 0xf0) | (value & 0x0f)
    else if register == REG-LED5-8-CTL: leds_ = (leds_ & 0x0f) | ((value & 0x0f) << 4)

  /**
  Sets the overcurrent limit of all four channels to $code.

  A channel that draws more than $code is held at the limit and reports
    $FAULT-ILIMIT, which names itself in $REG-ILIMIT-CH-STAT.

  $inrush gives how long the inrush window lasts. It defaults to
    $InrushWindow.MS-0, no window, which is the reset state. What the window
    does is decided by $set-inrush-mode, which this method leaves alone.

  Writes $REG-DEV-CONFIG1 and clears $CONFIG3-ILIM-SET, so that DEV_CONFIG1
    governs all four channels. Costs four frames: one for the write, three
    for the read-modify-write of $REG-DEV-CONFIG3. See
    $set-current-limit-split to give channels 3 and 4 a limit of their own.
  */
  set-current-limit code/IlimCode --inrush/InrushWindow=InrushWindow.MS-0 -> none:
    write-register REG-DEV-CONFIG1 (build-ilim-config code --inrush=inrush)
    update-config3_ --clear=CONFIG3-ILIM-SET

  /**
  Sets the overcurrent limit of channels 1 and 2 apart from channels 3 and 4.

  Takes the same arguments as $set-current-limit, twice: $channels-1-2 and
    $inrush-1-2 go to $REG-DEV-CONFIG1 and cover channels 1 and 2, and
    $channels-3-4 and $inrush-3-4 go to $REG-DEV-CONFIG2 and cover channels
    3 and 4.

  Writes both registers before setting $CONFIG3-ILIM-SET, so channels 3 and
    4 never run against a stale DEV_CONFIG2. Costs five frames: two for the
    writes, three for the read-modify-write of $REG-DEV-CONFIG3.
  */
  set-current-limit-split -> none
      --channels-1-2/IlimCode
      --channels-3-4/IlimCode
      --inrush-1-2/InrushWindow=InrushWindow.MS-0
      --inrush-3-4/InrushWindow=InrushWindow.MS-0:
    write-register REG-DEV-CONFIG1 (build-ilim-config channels-1-2 --inrush=inrush-1-2)
    write-register REG-DEV-CONFIG2 (build-ilim-config channels-3-4 --inrush=inrush-3-4)
    update-config3_ --set=CONFIG3-ILIM-SET

  /**
  Sets what the inrush window of $set-current-limit does.

  $limit is one of the `INRUSH-LIMIT-*` constants. Each names a limit that
    applies during the window only, given as a multiple of the code
    $set-current-limit was given, except $INRUSH-LIMIT-FIXED which is an
    absolute 2.2 A. It defaults to $INRUSH-LIMIT-1X, the reset state, which
    is the same limit inside the window as outside.

  With $timeout false, the default, the window is an inrush period: $limit
    applies while it lasts and the code afterwards, and $FAULT-ILIMIT is not
    reported during it. With $timeout true the code applies throughout and
    $limit is ignored, and the window becomes how long a channel may sit in
    current limit before its FET switches off, with the fault reported.

  Applies to every channel: $REG-DEV-CONFIG3 has no per-channel fields. Only
    the duration is per channel pair. Costs three frames, being a
    read-modify-write of $REG-DEV-CONFIG3.
  */
  set-inrush-mode --limit/int=INRUSH-LIMIT-1X --timeout/bool=false -> none:
    if not 0 <= limit <= CONFIG3-INRUSH-LIMIT-MASK: throw "INVALID_ARGUMENT"
    update-config3_
        --set=(limit | (timeout ? CONFIG3-ILIM-CONFIG : 0))
        --clear=(CONFIG3-INRUSH-LIMIT-MASK | (timeout ? 0 : CONFIG3-ILIM-CONFIG))

  /**
  Sets the bits of $set in $REG-DEV-CONFIG3 and clears those of $clear.

  Costs three frames: two to read the register and one to write it back.
    Every bit of DEV_CONFIG3 is in use, so there are no reserved ones to
    mask off the value read.

  Setting wins over clearing where the two overlap.
  */
  update-config3_ --set/int=0 --clear/int=0 -> none:
    config3 := read-register REG-DEV-CONFIG3
    write-register REG-DEV-CONFIG3 ((config3 & ~clear) | set)

  /**
  Reads and clears the global fault register, $REG-FAULT-GLOBAL-TYPE.

  A fresh device reports $GLOBAL-POR, $GLOBAL-VDD-UVLO, $GLOBAL-VS-UV-WRN
    and $GLOBAL-VS-UV. Read this twice during bring-up and expect the second
    read to come back clean. $GLOBAL-POR appearing later means the device
    reset and lost its configuration.
  */
  read-global-faults -> int:
    return read-register REG-FAULT-GLOBAL-TYPE

  /**
  Turns all channels off.

  Does not close the SPI device, since the caller owns it.
  */
  close -> none:
    write-register REG-SW-STATE 0

  transfer_ frame/int -> int:
    bytes := #[frame >> 8, frame & 0xff]
    spi_device_.transfer bytes --read
    faults_ = bytes[0]
    return bytes[1]
