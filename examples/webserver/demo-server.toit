/**
Serves the UI on a fake device, for taking screenshots without hardware.

Backed by the $FakeDevice the driver tests use, wound up with a fault
  scenario worth looking at: a channel in current limit while VS sags.

See `screenshot.sh`.
*/

import log
import net
import tps274c65

import ...tests.fake-device
import .api

/** The port the demo is served on. */
PORT ::= 8099

main:
  // The http package logs every request at debug level, which buries the one
  // line worth reading here.
  log.set-default (log.default.with-level log.WARN-LEVEL)
  device := FakeDevice
  // SUPPLY, ILIMIT and GLOBAL, the three the scenario below explains.
  device.faults = tps274c65.FAULT-SUPPLY | tps274c65.FAULT-ILIMIT | tps274c65.FAULT-GLOBAL
  device.contents[tps274c65.REG-FAULT-GLOBAL-TYPE] = tps274c65.GLOBAL-VS-UV
  device.contents[tps274c65.REG-ILIMIT-CH-STAT] = 0b0010  // Channel 2.
  device.read-to-clear.add tps274c65.REG-FAULT-GLOBAL-TYPE
  device.read-to-clear.add tps274c65.REG-ILIMIT-CH-STAT
  driver := tps274c65.Driver device
  network := net.open
  try:
    print "demo UI on http://localhost:$PORT/"
    (Ui driver).listen network PORT
  finally:
    network.close
