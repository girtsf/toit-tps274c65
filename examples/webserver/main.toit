/**
Serves a web UI for driving a TPS274C65.

The page shows the switch state and the fault byte, decoded, and lets you flip
  channels, run the ADC and read what it converted, and read or write any
  documented register. It is split up as:

- `main.toit`: the wiring, here.
- `api.toit`: the JSON API the page talks to.
- `page.toit`, `style.toit`, `script.toit`: the page itself.
*/

import net
import spi
import tps274c65

import .api

// Pin mapping.
SCK ::= 12
MOSI ::= 11
MISO ::= 13
CS ::= 10

/** The port the UI is served on. */
PORT ::= 80

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
    // A fresh device latches power-on reset and undervoltage. Read twice so
    // the page starts out reporting what is wrong now.
    driver.read-global-faults
    driver.read-global-faults
    network := net.open
    try:
      print "TPS274C65 UI on http://$network.address:$PORT/"
      (Ui driver).listen network PORT
    finally:
      network.close
  finally:
    driver.close
    device.close
    bus.close
