/**
Capturing the current a channel draws as it switches on.

$capture-turn-on trims the ADC round robin to the one conversion, so a
  reading lands every 128 us rather than every 1.7 ms, and streams read
  frames back to back for a conversion per frame.

The switching edge is not capturable -- `tON` is 33 us against 128 us for a
  conversion -- and the first $ADC-CURRENT-SETTLING-TIME after the write is
  the device's own sense settling. What it is for is the inrush window, which
  `ILIM_DURATION` sets between 2 ms and 64 ms.

A stretch of zero may be the device declining to sense rather than a channel
  drawing nothing; $Capture.faults tells the two apart.
*/

import ..driver
import ..registers

/** How long a capture watches the channel before it switches on. */
DEFAULT-CAPTURE-PRE ::= Duration --ms=5
/**
How long a capture watches the channel after it switches on.

An inrush window can be set as long as 64 ms; a capture of one wants at least
  that.
*/
DEFAULT-CAPTURE-POST ::= Duration --ms=45
/** Room $default-capture-points leaves for fault byte changes. */
CAPTURE-POINT-MARGIN ::= 64

/**
How many points a capture over $pre and $post needs at most.

A point is a change, and nothing changes faster than $ADC-CONVERSION-TIME, so
  the window divided by that bounds the trace.
*/
default-capture-points --pre/Duration --post/Duration -> int:
  window := pre.in-us + post.in-us
  return window / ADC-CONVERSION-TIME.in-us + CAPTURE-POINT-MARGIN
/**
How long a capture waits for a load to discharge before capturing it.

Only spent when the channel was already on. Raise it for a large capacitive
  load, which would otherwise still be part charged when the capture starts.
*/
DEFAULT-CAPTURE-SETTLE ::= Duration --ms=200

/**
How long after a channel switches on before the current sense means anything.

`tON` at most, plus the four conversions the device averages. SLVSFZ2C puts
  no number on `ISNS_DELAY`, so this is a lower bound rather than a spec.
*/
ADC-CURRENT-SETTLING-TIME ::= Duration --us=(42 + 4 * ADC-CONVERSION-TIME.in-us)

/**
A recording of one channel's current sense across a turn-on.

A step function, not a series of samples: a point is recorded when the
  conversion changes, and holds until the next one. So $frames is usually
  many times $size, and the gaps in $micros show how fast the device really
  converts.
*/
class Capture:
  /** The channel the trace was taken on. */
  channel/int
  /** When each point in $raw started, in microseconds from the switch write. */
  micros/List
  /**
  The 8-bit current conversions, one per entry of $micros. See $milli-amps.

  `ADC_RESULT_CHn_I` alone: collecting the two low bits from the register
    beside it would have halved the frame rate for a quarter of a step.
  */
  raw/ByteArray
  /**
  `FAULT_TYPE_STAT` at each point of $raw, free on every frame.

  Tells a current the device declined to sense from a current that was not
    there: a channel in current limit is regulating rather than fully on, and
    the sense is gated on being fully on. The capture selects the real-time
    fault path so both edges show; see $CONFIG5-FLT-LTCH-DIS.
  */
  faults/ByteArray
  /** How many SPI frames the capture spent. See $frame-micros. */
  frames/int
  /** How long the capture ran, in microseconds, from first frame to last. */
  span-micros/int
  /** Whether the capture ran out of room and lost the tail of the trace. */
  truncated/bool

  constructor.private_ .channel .micros .raw .faults .frames .span-micros .truncated:

  /** How many points the trace holds. */
  size -> int: return raw.size

  /**
  The average time one SPI frame took, in microseconds.

  What the bus managed, not what the device converted at. While it is under
    $ADC-CONVERSION-TIME the trace is limited by the device, not the bus.
  */
  frame-micros -> float:
    if frames == 0: return 0.0
    return span-micros.to-float / frames

  /** The index of the first point at or after the switch write. */
  trigger-index -> int:
    size.repeat: if micros[it] >= 0: return it
    return size

  /**
  The index of the first point whose current is a measurement.

  Everything before it is inside $ADC-CURRENT-SETTLING-TIME and is not
    current at all.
  */
  valid-index -> int:
    settling := ADC-CURRENT-SETTLING-TIME.in-us
    size.repeat: if micros[it] >= settling: return it
    return size

  /** The current at point $index, in milliamps. See $adc-milli-amps. */
  milli-amps index/int
      --sense-resistor/float=DEFAULT-SENSE-RESISTOR-OHMS
      --sense-ratio/int=SENSE-RATIO -> float:
    return adc-milli-amps (raw[index] << 2)
        --sense-resistor=sense-resistor
        --sense-ratio=sense-ratio

  /** Every point of $raw as a current, in milliamps. See $milli-amps. */
  to-milli-amps
      --sense-resistor/float=DEFAULT-SENSE-RESISTOR-OHMS
      --sense-ratio/int=SENSE-RATIO -> List:
    return List size: milli-amps it
        --sense-resistor=sense-resistor
        --sense-ratio=sense-ratio

  /** The largest current in the trace, in milliamps. Zero for an empty one. */
  peak-milli-amps
      --sense-resistor/float=DEFAULT-SENSE-RESISTOR-OHMS
      --sense-ratio/int=SENSE-RATIO -> float:
    peak := 0
    size.repeat: peak = max peak raw[it]
    return adc-milli-amps (peak << 2)
        --sense-resistor=sense-resistor
        --sense-ratio=sense-ratio

  /** Every fault bit set at any point of the trace. See $decode-faults. */
  faults-seen -> int:
    seen := 0
    size.repeat: seen |= faults[it]
    return seen

  /** Whether $bits are set in the fault byte at $index. See $faults. */
  faulted index/int bits/int -> bool:
    return (faults[index] & bits) != 0

  stringify -> string:
    return "Capture CH$channel: $size points over $(span-micros / 1000) ms, " +
        "$frames frames$(truncated ? ", truncated" : "")"

/**
Captures the current of $channel across its turn-on.

Switches $channel on and records what `ADC_RESULT_CHn_I` says on either
  side of it. Leaves the channel on.

$pre is how long to watch before the switch write and $post how long after;
  the write lands at time zero of $Capture.micros. $max-points defaults to
  $default-capture-points. Blocks for $pre + $post with the bus to itself,
  and $settle longer when $channel was already on, so the load can
  discharge.

Trims the ADC round robin to this one conversion for the duration, so a
  round is $ADC-CONVERSION-TIME rather than $ADC-ROUND-ROBIN-TIME, and
  selects the real-time fault path so $Capture.faults follows the
  condition. `ADC_CONFIG1`, `ADC_ISNS_DIS` and `DEV_CONFIG5` are restored
  afterwards.

The switching edge is not in the trace -- `tON` is 33 us typical against
  128 us for a conversion -- and neither are the first points after the
  write, which are settling rather than measurement. See
  $ADC-CURRENT-SETTLING-TIME. What it is for is the inrush window, which
  `ILIM_DURATION` sets between 2 ms and 64 ms.

Expect zero while the device is limiting, not a plateau at the limit: a
  channel held at the limit is regulating rather than fully on, and the sense
  is gated on being fully on. $Capture.faults is what separates that from a
  channel drawing nothing.
*/
capture-turn-on driver/Driver channel/int
    --pre/Duration=DEFAULT-CAPTURE-PRE
    --post/Duration=DEFAULT-CAPTURE-POST
    --max-points/int?=null
    --settle/Duration=DEFAULT-CAPTURE-SETTLE -> Capture:
  check-channel_ channel
  if pre < Duration.ZERO or post <= Duration.ZERO: throw "INVALID_ARGUMENT"
  points := max-points or (default-capture-points --pre=pre --post=post)
  if points < 1: throw "INVALID_ARGUMENT"

  if driver.channel-on channel:
    driver.set-channel channel --on=false
    sleep settle

  // Reserved bits read back as ones in all three, so mask before saving:
  // handing them back on the restore would write a value the device never
  // gave.
  config5 := (driver.read-register REG-DEV-CONFIG5) & CONFIG5-WRITABLE-MASK
  adc-config1 := (driver.read-register REG-ADC-CONFIG1) & ADC-CONFIG1-WRITABLE-MASK
  isns-dis := (driver.read-register REG-ADC-ISNS-DIS) & ADC-CHANNEL-DIS-MASK
  try:
    // Everything but this one channel's current comes out of the round, so
    // the round is one conversion long.
    driver.write-register REG-ADC-CONFIG1 (ADC1-TSNS-DIS | ADC1-VSNS-DIS | ADC1-VS-DIS)
    driver.write-register REG-ADC-ISNS-DIS
        (ADC-CHANNEL-DIS-MASK & ~(channel-mask channel))
    driver.write-register REG-DEV-CONFIG5 (config5 | CONFIG5-ADC-EN | CONFIG5-FLT-LTCH-DIS)
    // Let the trimmed round land one conversion in the result register, so
    // the baseline is a reading and not whatever the ADC last left there.
    sleep --ms=1
    return capture_ driver channel --pre=pre --post=post --max-points=points
  finally:
    driver.write-register REG-DEV-CONFIG5 config5
    driver.write-register REG-ADC-ISNS-DIS isns-dis
    driver.write-register REG-ADC-CONFIG1 adc-config1

/**
Runs the capture loop of $capture-turn-on, the ADC already trimmed for it.

Sends nothing but read frames aimed at the one result register. The device
  answers a read one frame late, so a stream of identical ones yields a
  conversion per frame rather than the two $Driver.read-register spends -- safe
  only because the ADC results are plain `R`.

Records a point when the conversion or the fault byte changes. Nothing is
  allocated inside the loop.
*/
capture_ driver/Driver channel/int --pre/Duration --post/Duration --max-points/int -> Capture:
  register := ADC-CURRENT-REGISTERS[channel - 1]
  frame := build-read-frame register --switch-state=driver.switch-state_
  stamps := List max-points
  values := ByteArray max-points
  // The fault byte rides along on every frame, so recording it costs no
  // frames at all. See $Capture.faults for what it is worth.
  flags := ByteArray max-points
  count := 0
  frames := 1
  truncated := false

  // The first answer belongs to whatever was asked for before the capture.
  driver.transfer_ frame
  start := Time.monotonic-us
  fire-at := start + pre.in-us
  trigger := -1
  stop-at := -1
  last := -1
  last-faults := -1
  now := start
  while true:
    value := driver.transfer_ frame
    now = Time.monotonic-us
    faults := driver.faults
    frames++
    if count == 0 or value != last or faults != last-faults:
      if count == max-points:
        truncated = true
      else:
        stamps[count] = now
        values[count] = value
        flags[count] = faults
        count++
        last = value
        last-faults = faults
    if trigger < 0:
      if now >= fire-at:
        driver.set-channel channel --on=true
        trigger = Time.monotonic-us
        stop-at = trigger + post.in-us
        frames++
        // Two things changed with that write. The read frames have to
        // carry the new switch state from here on, or the next one turns
        // the channel back off. And the write put SW_STATE in the read
        // pipeline, so the frame after it answers with SW_STATE and not a
        // conversion -- send it and drop what it says.
        frame = build-read-frame register --switch-state=driver.switch-state_
        driver.transfer_ frame
        frames++
    else if now >= stop-at:
      break

  // Close the trace off at the moment it stopped, so the last point has an
  // end and not just a beginning.
  if count > 0 and count < max-points and stamps[count - 1] != now:
    stamps[count] = now
    values[count] = last
    flags[count] = last-faults
    count++

  micros := List count: stamps[it] - trigger
  raw := values.copy 0 count
  recorded := flags.copy 0 count
  span := now - start
  return Capture.private_ channel micros raw recorded frames span truncated
