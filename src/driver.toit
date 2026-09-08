import spi

import .adc
import .registers

/** The SPI mode of the device: CPOL = 0, CPHA = 1. */
SPI-MODE ::= 1

/** The number of switch channels the device has. */
CHANNEL-COUNT ::= 4

/** The number of LEDs the device drives. */
LED-COUNT ::= 8

/** Returns the bit mask for $channel. */
channel-mask channel/int -> int:
  check-channel_ channel
  return 1 << (channel - 1)

check-channel_ channel/int -> none:
  if not 1 <= channel <= CHANNEL-COUNT: throw "INVALID_ARGUMENT"

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
  /// The one buffer every frame goes out in. See $transfer_.
  frame_/ByteArray ::= ByteArray 2
  /// `RSNS`, in ohms, that currents are decoded with. See $adc-milli-amps.
  sense-resistor/float
  /// `KSNS` that currents are decoded with. See $adc-milli-amps.
  sense-ratio/int

  constructor .spi_device_
      --.sense-resistor=DEFAULT-SENSE-RESISTOR-OHMS
      --.sense-ratio=SENSE-RATIO:

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
  Reads every register in $registers, in one pipelined burst.

  Returns their contents in the order they were asked for. Costs one frame
    more than $registers has entries (vs two per register $read-register
    spends).

  These are separate frames, one CS pulse each. Several frames in a pulse do
    not work: the device executes the last of them and shifts the rest straight
    back out on SDO, unchanged.

  Naming a register twice reads it twice, which matters for the read-to-clear
    ones.

  Refreshes $faults, and resends $switch-state on every frame the way
    $read-register does.
  */
  read-registers registers/List -> ByteArray:
    values := ByteArray registers.size
    if registers.is-empty: return values
    // Check the lot before any of it goes out, rather than halfway through.
    registers.do: check-register_ it
    // Discard the first answer: it belongs to whatever was asked for before.
    transfer_ (build-read-frame registers.first --switch-state=switch-state_)
    registers.size.repeat: | index/int |
      next := index + 1 < registers.size
          ? registers[index + 1]
          : REG-FAULT-TYPE-STAT
      values[index] = transfer_ (build-read-frame next --switch-state=switch-state_)
    return values

  /**
  Writes $value into the register at $register.

  Takes one frame. Only reads pay for the pipeline.

  Refreshes $faults from the fault byte returned in the same frame, and
    tracks $switch-state and $leds when $register is one of theirs, keeping
    only the bits those registers document.

  A write fills the read pipeline the same way a read does: the frame after
    this one carries the new contents of $register. $read-register does not
    rely on that, and always sends its own two frames.

  Throws $POWER-CONFIG-LOCKED-ERROR if a write to $POWER-CONFIG-REGISTERS is 
    attempted while any channel is on.
  */
  write-register register/int value/int -> none:
    if switch-state_ != 0 and POWER-CONFIG-REGISTERS.contains register:
      throw POWER-CONFIG-LOCKED-ERROR
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

  Throws $POWER-CONFIG-LOCKED-ERROR if any channel is on.
  */
  set-current-limit code/IlimCode --inrush/InrushWindow=InrushWindow.MS-0 -> none:
    write-register REG-DEV-CONFIG1 (build-ilim-config code --inrush=inrush)
    update-register_ REG-DEV-CONFIG3 --clear=CONFIG3-ILIM-SET

  /**
  Sets the overcurrent limit of channels 1 and 2 apart from channels 3 and 4.

  Takes the same arguments as $set-current-limit, twice: $channels-1-2 and
    $inrush-1-2 go to $REG-DEV-CONFIG1 and cover channels 1 and 2, and
    $channels-3-4 and $inrush-3-4 go to $REG-DEV-CONFIG2 and cover channels
    3 and 4.

  Writes both registers before setting $CONFIG3-ILIM-SET, so channels 3 and
    4 never run against a stale DEV_CONFIG2. Costs five frames: two for the
    writes, three for the read-modify-write of $REG-DEV-CONFIG3.

  Throws $POWER-CONFIG-LOCKED-ERROR if any channel is on.
  */
  set-current-limit-split -> none
      --channels-1-2/IlimCode
      --channels-3-4/IlimCode
      --inrush-1-2/InrushWindow=InrushWindow.MS-0
      --inrush-3-4/InrushWindow=InrushWindow.MS-0:
    write-register REG-DEV-CONFIG1 (build-ilim-config channels-1-2 --inrush=inrush-1-2)
    write-register REG-DEV-CONFIG2 (build-ilim-config channels-3-4 --inrush=inrush-3-4)
    update-register_ REG-DEV-CONFIG3 --set=CONFIG3-ILIM-SET

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

  Throws $POWER-CONFIG-LOCKED-ERROR if any channel is on.
  */
  set-inrush-mode --limit/int=INRUSH-LIMIT-1X --timeout/bool=false -> none:
    if not 0 <= limit <= CONFIG3-INRUSH-LIMIT-MASK: throw "INVALID_ARGUMENT"
    update-register_ REG-DEV-CONFIG3
        --set=(limit | (timeout ? CONFIG3-ILIM-CONFIG : 0))
        --clear=(CONFIG3-INRUSH-LIMIT-MASK | (timeout ? 0 : CONFIG3-ILIM-CONFIG))

  /**
  Enables or disables reverse current blocking on all four channels.

  Reverse current blocking needs an external NMOS FET per channel, driven
    from the `RCBx` pins. With $enabled false, $CONFIG3-RCB-DIS is set and
    those pins stop driving, which is what a board with no external FETs
    wants. Leave the pins floating there. Out of reset blocking is on.

  Leaves $REG-DEV-CONFIG6, which turns the blocking FETs off channel by
    channel, alone. That register only has an effect while blocking is
    enabled here.

  Does nothing useful on the BS part, which has no reverse current blocking
    at all. Costs three frames, being a read-modify-write of
    $REG-DEV-CONFIG3.

  Throws $POWER-CONFIG-LOCKED-ERROR if any channel is on.
  */
  set-reverse-blocking --enabled/bool -> none:
    update-register_ REG-DEV-CONFIG3
        --set=(enabled ? 0 : CONFIG3-RCB-DIS)
        --clear=(enabled ? CONFIG3-RCB-DIS : 0)

  /**
  Whether reverse current blocking is enabled.

  Costs two frames. See $set-reverse-blocking.
  */
  reverse-blocking-enabled -> bool:
    return ((read-register REG-DEV-CONFIG3) & CONFIG3-RCB-DIS) == 0

  /**
  Runs or stops the SPI watchdog.

  With $enabled true the device wants a write to $REG-SW-STATE within every
    $timeout, and raises $GLOBAL-WD-ERR when one does not arrive. It also
    puts the outputs wherever $set-fail-safe-state last left them, which
    this method does not touch; out of reset they hold.

  $feed-watchdog is that write, and so is every other frame carrying a
    switch state: $switch-state=, $set-channel, $close, and reads as well,
    a read frame carrying one too. Only a write to some register other than
    $REG-SW-STATE leaves the watchdog hungry. See $feed-watchdog.

  $timeout has no default on purpose. The reset code is
    $WatchdogTimeout.US-400, and enabling the watchdog on it by accident
    gives four hundred microseconds to answer in.

  Costs three frames, being a read-modify-write of $REG-DEV-CONFIG4. That
    register also holds the wire-break pull-up current and on-state
    threshold, which are read back and written out again untouched.

  The timeout starts running as this frame lands, so feed the watchdog
    within one $timeout of enabling it.
  */
  set-watchdog --enabled/bool --timeout/WatchdogTimeout -> none:
    update-register_ REG-DEV-CONFIG4
        --set=((enabled ? CONFIG4-WD-EN : 0) | (timeout.value << CONFIG4-WD-TO-SHIFT))
        --clear=(CONFIG4-WD-TO-MASK | (enabled ? 0 : CONFIG4-WD-EN))

  /** Whether the SPI watchdog is running. Costs two frames. See $set-watchdog. */
  watchdog-enabled -> bool:
    return ((read-register REG-DEV-CONFIG4) & CONFIG4-WD-EN) != 0

  /**
  The timeout the SPI watchdog is set to.

  Says nothing about whether the watchdog is running: `WD_TO` keeps its code
    either way. See $watchdog-enabled. Costs two frames.
  */
  watchdog-timeout -> WatchdogTimeout:
    value := (read-register REG-DEV-CONFIG4) & CONFIG4-WD-TO-MASK
    return WatchdogTimeout.ALL[value >> CONFIG4-WD-TO-SHIFT]

  /**
  Feeds the SPI watchdog.
  */
  feed-watchdog -> none:
    write-register REG-SW-STATE switch-state_

  /**
  Sets where the outputs go when the watchdog trips.

  $state is a switch state, laid out as $switch-state: bit 0 is channel 1,
    and a set bit means that FET is driven on once the error hits. Null
    holds instead, leaving every output where it was, which is how the
    device comes out of reset.

  Covers `SPI_ERR` as well as $GLOBAL-WD-ERR: the two share the mechanism.

  Writes $REG-FS-SW-STATE before turning it on, so an error landing in
    between never finds a stale state. See $CONFIG5-SW-FS-CFG for the
    contradiction in the datasheet about which way that bit runs, and how it
    was settled.
  */
  set-fail-safe-state state/int? -> none:
    if state != null:
      check-switch-state_ state
      write-register REG-FS-SW-STATE state
    update-register_ REG-DEV-CONFIG5
        --set=(state != null ? CONFIG5-SW-FS-CFG : 0)
        --clear=(state != null ? 0 : CONFIG5-SW-FS-CFG)
        --mask=CONFIG5-WRITABLE-MASK

  /**
  The state the outputs go to when the watchdog trips, or null if they hold.
  */
  fail-safe-state -> int?:
    if ((read-register REG-DEV-CONFIG5) & CONFIG5-SW-FS-CFG) == 0: return null
    return (read-register REG-FS-SW-STATE) & 0x0f

  /**
  Runs or stops the ADC.

  Nothing is converted until this is on: out of reset $CONFIG5-ADC-EN is
    clear and every result register reads 0. Wait $ADC-ROUND-ROBIN-TIME after
    switching it on before believing the first readings.

  Costs three frames, being a read-modify-write of $REG-DEV-CONFIG5. That
    register also holds the fault latching and auto retry settings, which are
    read back and written out again untouched.
  */
  set-adc --enabled/bool -> none:
    update-register_ REG-DEV-CONFIG5
        --set=(enabled ? CONFIG5-ADC-EN : 0)
        --clear=(enabled ? 0 : CONFIG5-ADC-EN)
        --mask=CONFIG5-WRITABLE-MASK

  /** Whether the ADC is running. Costs two frames. See $set-adc. */
  adc-enabled -> bool:
    return ((read-register REG-DEV-CONFIG5) & CONFIG5-ADC-EN) != 0

  /**
  Reads the raw current sense conversion of $channel.

  Returns a 10-bit result, running to $ADC-FULL-SCALE-10-BIT. Pass it to
    $adc-milli-amps for a current. Costs three frames: the top eight bits and
    the bottom two live in registers of their own, which $read-registers
    collects back to back.

  A conversion this method assembles can straddle two rounds of the ADC, the
    low bits having been replaced between the two reads. That moves the
    result by less than one step of the eight bits above them, which is
    13 mA with a 1 kOhm `RSNS`. Read the register in $ADC-CURRENT-REGISTERS
    yourself for those eight bits alone, in two frames, if that matters more
    than the resolution.
  */
  read-current-raw channel/int -> int:
    check-channel_ channel
    values := read-registers [
      ADC-CURRENT-REGISTERS[channel - 1],
      ADC-CURRENT-LSB-REGISTERS[channel - 1],
    ]
    return (values[0] << 2) | (values[1] & 0x03)

  /**
  Reads the current through $channel, in milliamps.

  Converts what $read-current-raw returns; see there for what it costs and
    when it holds. Decoded with the $sense-resistor and $sense-ratio the
    driver was constructed with.
  */
  read-current channel/int -> float:
    return adc-milli-amps (read-current-raw channel)
        --sense-resistor=sense-resistor
        --sense-ratio=sense-ratio

  /**
  Reads the raw temperature conversion of $channel.

  Returns an 8-bit result, running to $ADC-FULL-SCALE-8-BIT. Pass it to
    $adc-celsius for a temperature. Costs two frames.
  */
  read-temperature-raw channel/int -> int:
    check-channel_ channel
    return read-register ADC-TEMPERATURE-REGISTERS[channel - 1]

  /**
  Reads the junction temperature of $channel, in degrees Celsius.

  Measured in the FET, so it reads high on a channel carrying current. Unlike
    the current and the output voltage it means something whether the channel
    is on or off.
  */
  read-temperature channel/int -> float:
    return adc-celsius (read-temperature-raw channel)

  /**
  Reads the raw output voltage conversion of $channel.

  Returns an 8-bit result, running to $ADC-FULL-SCALE-8-BIT. Pass it to
    $adc-volts for a voltage. Costs two frames.
  */
  read-output-voltage-raw channel/int -> int:
    check-channel_ channel
    return read-register ADC-OUTPUT-VOLTAGE-REGISTERS[channel - 1]

  /**
  Reads the output voltage of $channel, in volts.

  Reads near the supply voltage on a channel that is on and near zero on one
    that is off, so an output sitting between the two is a load pulling
    against a switch that is not fully on.
  */
  read-output-voltage channel/int -> float:
    return adc-volts (read-output-voltage-raw channel) --full-scale=ADC-FULL-SCALE-8-BIT

  /**
  Reads the raw supply voltage conversion.

  Returns a 10-bit result, running to $ADC-FULL-SCALE-10-BIT. Pass it to
    $adc-volts for a voltage. Costs three frames, and can straddle two rounds
    of the ADC the way $read-current-raw can.
  */
  read-supply-voltage-raw -> int:
    values := read-registers [REG-ADC-RESULT-VS, REG-ADC-RESULT-VS-LSB]
    return (values[0] << 2) | (values[1] & 0x03)

  /**
  Reads the supply voltage, in volts.

  This is VS as the device sees it, which is what $GLOBAL-VS-UV-WRN and
    $GLOBAL-VS-UV are raised against.
  */
  read-supply-voltage -> float:
    return adc-volts read-supply-voltage-raw --full-scale=ADC-FULL-SCALE-10-BIT

  /**
  Reads every result the ADC holds, in one pipelined burst.

  Costs 19 frames. The $sense-resistor and $sense-ratio the driver was
    constructed with go into the $AdcReadings, which decodes the currents
    with them.

  Every result reads zero while the ADC is off, which decodes to no current,
    no output voltage and 373 degrees. See $set-adc, and $adc-enabled to tell
    a stopped ADC from a cold one.

  The eighteen results are not from one instant and will likely see data
    spanning multiple ADC cycles, including for current that gets assembled from
    two registers (see $read-current-raw).
  */
  read-adc-all -> AdcReadings:
    values := read-registers ADC-RESULT-REGISTERS
    // The results are one unbroken run of addresses, so a register names its
    // own place in the answer.
    base := ADC-RESULT-REGISTERS.first
    current := List CHANNEL-COUNT: | index/int |
      msb := values[ADC-CURRENT-REGISTERS[index] - base]
      lsb := values[ADC-CURRENT-LSB-REGISTERS[index] - base]
      (msb << 2) | (lsb & 0x03)
    temperature := List CHANNEL-COUNT: values[ADC-TEMPERATURE-REGISTERS[it] - base]
    output-voltage := List CHANNEL-COUNT: values[ADC-OUTPUT-VOLTAGE-REGISTERS[it] - base]
    supply := (values[REG-ADC-RESULT-VS - base] << 2)
        | (values[REG-ADC-RESULT-VS-LSB - base] & 0x03)
    return AdcReadings.private_
        current
        temperature
        output-voltage
        supply
        faults_
        sense-resistor
        sense-ratio

  /**
  Sets the bits of $set in $register and clears those of $clear.

  Costs three frames: two to read the register and one to write it back.

  $mask says which bits of the value read are worth keeping, and defaults to
    all of them. Reserved bits read back as ones, so a register that has any
    must name the ones it does not -- $CONFIG5-WRITABLE-MASK, say -- or the
    write hands the device a value it never gave.

  Setting wins over clearing where the two overlap.
  */
  update-register_ register/int --set/int=0 --clear/int=0 --mask/int=0xff -> none:
    value := (read-register register) & mask
    write-register register ((value & ~clear) | set)

  /**
  Reads and clears the global fault register, $REG-FAULT-GLOBAL-TYPE.

  A fresh device reports $GLOBAL-POR, $GLOBAL-VDD-UVLO, $GLOBAL-VS-UV-WRN
    and $GLOBAL-VS-UV. Read this twice during bring-up and expect the second
    read to come back clean. $GLOBAL-POR appearing later means the device
    reset and lost its configuration.

  Masked with $GLOBAL-FAULT-MASK, so clean really is zero. The register
    itself does not read that way: bit 7 comes back set on a healthy device
    whatever the datasheet says about it being reserved, and a caller
    comparing the raw byte against zero would never see a device it was
    happy with. Read the register through $read-register for the raw byte.
  */
  read-global-faults -> int:
    return (read-register REG-FAULT-GLOBAL-TYPE) & GLOBAL-FAULT-MASK

  /**
  Turns all channels off.

  Does not close the SPI device, since the caller owns it.
  */
  close -> none:
    write-register REG-SW-STATE 0

  /**
  Sends $frame and returns its data byte, refreshing $faults from its fault
    byte.

  Reuses one buffer rather than allocating a frame each time. A tight read
    loop sends thousands of these back to back, and the garbage would show up
    as scheduler jitter. Safe because the transfer is synchronous and the
    answer is read out of the buffer before the next call, and because a
    $Driver is not safe to share between tasks anyway.
  */
  transfer_ frame/int -> int:
    frame_[0] = frame >> 8
    frame_[1] = frame & 0xff
    spi_device_.transfer frame_ --read
    faults_ = frame_[0]
    return frame_[1]
