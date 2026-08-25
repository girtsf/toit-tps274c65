import expect show *
import tps274c65 show *

main:
  test-channel-mask
  test-read-frame
  test-write-frame

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
