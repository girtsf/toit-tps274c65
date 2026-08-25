/** Chases a lit LED across all eight LED drivers. */

import spi
import tps274c65

// Pin mapping.
SCK ::= 12
MOSI ::= 11
MISO ::= 13
CS ::= 10

/** How long each LED stays lit during the chase. */
CHASE-MS ::= 120

/** How many times the chase runs around the eight LEDs. */
CHASE-ROUNDS ::= 10

main:
  bus := spi.Bus --clock=SCK --mosi=MOSI --miso=MISO
  device := bus.device
      --cs=CS
      --frequency=1_000_000
      --mode=tps274c65.SPI-MODE
  driver := tps274c65.Driver device
  try:
    CHASE-ROUNDS.repeat:
      tps274c65.LED-COUNT.repeat:
        led := it + 1
        driver.set-leds led --on
        sleep --ms=CHASE-MS
        driver.set-leds led --no-on
  finally:
    driver.close
    device.close
    bus.close
