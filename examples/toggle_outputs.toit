/** Toggles each output on and off. */

import spi
import tps274c65

// Pin mapping.
SCK ::= 12
MOSI ::= 11
MISO ::= 13
CS ::= 10

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
    // A fresh device reports power-on reset and undervoltage. Read twice to
    // clear the latches.
    print "global faults: 0x$(%02x driver.read-global-faults)"
    print "global faults: 0x$(%02x driver.read-global-faults)"

    tps274c65.CHANNEL-COUNT.repeat:
      channel := it + 1
      driver.set-channel channel --on
      sleep --ms=500
      print "channel $channel on, faults 0x$(%02x driver.faults)"
      driver.set-channel channel --no-on
  finally:
    driver.close
    device.close
    bus.close
