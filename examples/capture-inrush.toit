/**
Captures the current channel 1 draws as it switches on, and prints the trace.

Two columns: microseconds from the switch write, and milliamps. Points before
  `Capture.valid-index` are sense settling, not measurement.
*/

import spi
import tps274c65

// Pin mapping.
SCK ::= 12
MOSI ::= 11
MISO ::= 13
CS ::= 10

/** The channel with the load on it. */
CHANNEL ::= 1

main:
  bus := spi.Bus --clock=SCK --mosi=MOSI --miso=MISO
  device := bus.device
      --cs=CS
      --frequency=1_000_000
      --mode=tps274c65.SPI-MODE
  driver := tps274c65.Driver device
  try:
    // A fresh device reports power-on reset and undervoltage. Read twice to
    // clear the latches.
    driver.read-global-faults
    driver.read-global-faults

    // A 1.25 A limit with a 16 ms window at twice that, which is the shape
    // an incandescent lamp or a big capacitor wants. Expect zero while the
    // device is limiting rather than a plateau at the limit; the fault byte
    // of each point says when that was.
    driver.set-current-limit tps274c65.IlimCode.MA-1250
        --inrush=tps274c65.InrushWindow.MS-16
    driver.set-inrush-mode --limit=tps274c65.INRUSH-LIMIT-2X

    capture := tps274c65.capture-turn-on driver CHANNEL
        --pre=(Duration --ms=5)
        --post=(Duration --ms=45)
    print capture
    print "peak $(%.0f capture.peak-milli-amps) mA"
    // While this is well under the 128 us a conversion takes, the trace is
    // limited by the device rather than by the bus, which is where it wants
    // to be.
    print "$(%.1f capture.frame-micros) us per frame"
    print "faults after the turn-on: 0x$(%02x driver.faults)"

    print "us,mA"
    capture.size.repeat:
      // The first points after the write are not current; mark them rather
      // than dropping them, so the trace still says when they were.
      settling := it < capture.valid-index ? "  (settling)" : ""
      print "$capture.micros[it],$(%.0f (capture.milli-amps it))$settling"
  finally:
    driver.close
    device.close
    bus.close
