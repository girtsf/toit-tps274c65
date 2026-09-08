/**
Driver for the TI TPS274C65, a quad-channel 72 mOhm smart high-side switch
  with SPI control and diagnostics.

The driver speaks the 16-bit daisy-chain frame format (DSPI tied high) and
  assumes one device per chip select.

Usage:
```
import spi
import tps274c65

main:
  bus := spi.Bus --clock=12 --mosi=11 --miso=13
  device := bus.device --cs=10 --frequency=1_000_000 --mode=tps274c65.SPI-MODE
  driver := tps274c65.Driver device
  driver.set-channel 1 --on
  print "faults: 0x$(%02x driver.faults)"
  driver.close
```

See $Driver for the full API, and the `registers.toit` library for the
  register map.
*/

import .adc
import .driver
import .misc.capture
import .registers

export *
