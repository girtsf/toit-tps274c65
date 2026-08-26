import expect show *
import tps274c65 show *

main:
  test-channel-mask
  test-read-frame
  test-write-frame
  test-ilim-config
  test-ilim-at-least

test-channel-mask:
  expect-equals 0b0001 (channel-mask 1)
  expect-equals 0b1000 (channel-mask 4)
  expect-throw "INVALID_ARGUMENT": channel-mask 0
  expect-throw "INVALID_ARGUMENT": channel-mask 5

test-read-frame:
  // Read bit clear, register in bits 14..8, switch state in bits 3..0.
  expect-equals 0x0000 (build-read-frame 0x00 --switch-state=0)
  expect-equals 0x1d00 (build-read-frame REG-SW-STATE --switch-state=0)
  expect-equals 0x0205 (build-read-frame REG-FAULT-GLOBAL-TYPE --switch-state=0b0101)
  expect-throw "INVALID_ARGUMENT": build-read-frame 0x80 --switch-state=0
  expect-throw "INVALID_ARGUMENT": build-read-frame 0x00 --switch-state=0b10000

test-write-frame:
  // Write bit set, register in bits 14..8, data in bits 7..0.
  expect-equals 0x9d0f (build-write-frame REG-SW-STATE 0x0f)
  expect-equals 0xaf02 (build-write-frame REG-CRC-CONFIG 0x02)
  expect-throw "INVALID_ARGUMENT": build-write-frame 0x80 0x00
  expect-throw "INVALID_ARGUMENT": build-write-frame 0x00 0x100

test-ilim-config:
  // Current limit code in bits [3:0], inrush duration code in bits [7:4].
  expect-equals 0x0a (build-ilim-config IlimCode.MA-1250)
  expect-equals 0x3f (build-ilim-config IlimCode.MA-2200 --inrush=InrushWindow.MS-6)

  // There is nothing to range check: every instance of either type fits its
  // field, and the two types cannot be swapped for each other.
  IlimCode.ALL.do: | code/IlimCode |
    expect-equals code.value (code.value & ILIM-REG-MASK)
    expect-equals code (IlimCode.ALL[code.value])
  InrushWindow.ALL.do: | window/InrushWindow |
    expect-equals window.value (window.value & (ILIM-DURATION-MASK >> ILIM-DURATION-SHIFT))
    expect-equals window (InrushWindow.ALL[window.value])

  expect-equals "1.25 A" "$IlimCode.MA-1250"
  expect-equals "6 ms" "$InrushWindow.MS-6"

/** Looking up by current or duration rounds up, never below what was asked for. */
test-ilim-at-least:
  expect-identical IlimCode.MA-1250 (IlimCode.at-least 1250)
  expect-identical IlimCode.MA-1500 (IlimCode.at-least 1251)
  expect-identical IlimCode.MA-250 (IlimCode.at-least 0)
  expect-identical IlimCode.MA-2200 (IlimCode.at-least 2200)
  expect-throw "INVALID_ARGUMENT": IlimCode.at-least 2201

  expect-identical InrushWindow.MS-10 (InrushWindow.at-least 10)
  expect-identical InrushWindow.MS-16 (InrushWindow.at-least 13)
  expect-identical InrushWindow.MS-0 (InrushWindow.at-least 0)
  expect-throw "INVALID_ARGUMENT": InrushWindow.at-least 65
