# toit-tps274c65

A minimal Toit driver for the TI
[TPS274C65](https://www.ti.com/product/TPS274C65), a quad-channel 72 mOhm smart
high-side switch with SPI control and diagnostics.

The driver speaks only the **16-bit daisy-chain** frame format (`DSPI` tied
high). It assumes **one device per chip select**, so one frame per chip-select
pulse. It also assumes the **AS** part where the variants differ
(current-limits table).

## Installation

```sh
toit pkg install github.com/girtsf/toit-tps274c65
```

Then:

```
import tps274c65
```

## Web Server

You can `jag run examples/webserver/main.toit` to start a web UI that shows the
switch state, decoded faults and the ADC readings, lets you poke at registers,
and plots the current a channel draws as it switches on.

![The web UI](examples/webserver/screenshot.png)

## Development

```sh
make test      # Run the unit tests.
make analyze   # Type-check src, tests and examples.
```

The screenshot above is taken by `examples/webserver/screenshot.sh`, which
serves the UI on the fake device the driver tests use, drives it with
[shot-scraper](https://shot-scraper.datasette.io/) and shoots the result. Run
it after changing the UI. It runs shot-scraper through `uvx`, so only the
headless browser has to be installed first:

```sh
uvx shot-scraper install
```

## Notes on TPS274C65

Some gotchas to watch out for:
* One frame lag for register reads in daisy chained mode. Never mentioned in
  the datasheet, with misleading frame diagrams.
* LEDs can only be turned on/off and cannot be configured to convey any device
  state.
* TPS274C65EVM has its SDI and SCLK test point labels swapped.
* Undocumented: `DEV_CONFIG1`, `DEV_CONFIG2`, `DEV_CONFIG3` and `DEV_CONFIG6`
  silently ignore writes while any channel is on.
* `DEV_CONFIG5` (25h) bit 1 `SW_FS_CFG` is documented both ways: the prose
  above table 8-50 says setting it holds the outputs, the field description
  below says setting it takes them from `FS_SW_STATE`. The field description
  is the right one, confirmed on the bench: with `FS_SW_STATE` asking for a
  channel the outputs did not have, tripping the watchdog switched that
  channel on with the bit set and left it alone with the bit clear.
* Undocumented: the SPI watchdog is fed by any frame carrying a switch state,
  which in 16-bit daisy chain means every *read* frame as well as a write to
  `SW_STATE`. A write to any other register does not feed it. Bench-confirmed,
  so a polling loop keeps the watchdog happy on its own and a
  configuration-only loop does not.
* Several frames in one chip-select pulse do not work in daisy chain: the
  device runs the last frame of the pulse and shifts the earlier ones straight
  back out on SDO, unchanged, without raising `SPI_ERR`.
* `FAULT_GLOBAL_TYPE` (02h) bit 7 reads back as one though the datasheet calls
  it reserved with reset 0, so a clean device reads 80h rather than 00h.
  `Driver.read-global-faults` masks it off; `read-register` does not.
* Pass `--cs-setup-cycles=1` to `bus.device`, otherwise there is no delay
  between CS dropping and first SCLK rising, vs datasheet wants 45ns.

## AI Disclosure

Robots wrote most of this.
