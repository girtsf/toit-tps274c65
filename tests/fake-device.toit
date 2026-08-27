import io
import spi

import tps274c65 show FAULT-TYPE-BITS FaultBit REG-SW-STATE

/**
A stand-in for a TPS274C65 on the SPI bus, for testing without hardware.

Models the behaviours that reading depends on, all confirmed against a real
  device or documented by TI:

- Reads are pipelined. The data byte of a frame carries the register that the
  *previous* frame asked for, not this one's. The fault byte is not delayed.
- A write frame updates the register straight away, and its data byte still
  carries the pipelined read.
- Addressing one of $read-to-clear captures its value and zeroes it, so a
  test can tell whether the driver read it once or twice. Clearing one also
  drops the $FAULT-TYPE-BITS bit that names it out of $faults, the way the
  device drops a fault type once the register behind it has been read.

$frames records every frame the driver sent, so a test can check how many
  went out and what was in them. $contents holds the register file; it is not
  called `registers` because $spi.Device already uses that name.
*/
class FakeDevice implements spi.Device:
  /** Register contents, by address. Missing addresses read as zero. */
  contents/Map ::= {:}

  /** The byte returned in the fault position of every frame. */
  faults/int := 0

  /** The frames sent so far, as two-byte arrays, oldest first. */
  frames/List ::= []

  /** Addresses that clear themselves when addressed. */
  read-to-clear/Set ::= {}

  /**
  Bits that read back as ones however they were written, by address.

  The device does that for the reserved bits of a register, so SW_STATE reads
    back as 0xf5 rather than 0x05.
  */
  reserved-ones/Map ::= {REG-SW-STATE: 0xf0}

  /** How many times each address has been addressed by a frame. */
  accesses/Map ::= {:}

  /**
  Called with the address of every frame, before its value is captured.

  A hook for registers that move on their own. A test of a capture uses it to
    walk a conversion result along while the driver reads it.
  */
  on-frame/Lambda? := null

  /** The register whose contents the next frame will return. */
  pending_/int := 0

  /** The value captured for $pending_, before any clear. */
  captured_/int := 0

  /** Whether $close has been called. */
  closed/bool := false

  transfer data/ByteArray
      --from/int=0
      --to/int=data.size
      --read/bool=false
      --dc/int=0
      --command/int=0
      --address/int=0
      --keep-cs-active/bool=false -> none:
    if to - from != 2: throw "expected a 16-bit frame"
    frame := data.copy from to
    frames.add frame
    is-write := frame[0] & 0x80 != 0
    register := frame[0] & 0x7f
    if is-write:
      contents[register] = frame[1]
    else:
      contents[REG-SW-STATE] = frame[1] & 0x0f
    if read:
      data[from] = faults
      data[from + 1] = captured_
    // The device captures the addressed register for the next frame to
    // return, and a read-to-clear register empties as it is captured.
    accesses.update register --init=0: it + 1
    if on-frame: on-frame.call register
    captured_ = (contents.get register --if-absent=: 0)
        | (reserved-ones.get register --if-absent=: 0)
    if read-to-clear.contains register:
      contents[register] = 0
      FAULT-TYPE-BITS.do: | bit/FaultBit |
        if bit.detail-register == register: faults &= ~bit.mask
    pending_ = register

  registers --byte-size/int=1 --byte-order/io.ByteOrder=io.BIG-ENDIAN -> spi.Registers:
    throw "UNIMPLEMENTED"

  read amount/int -> ByteArray:
    throw "UNIMPLEMENTED"

  write bytes/ByteArray --keep-cs-active/bool=false -> none:
    transfer bytes --keep-cs-active=keep-cs-active

  with-reserved-bus [block]:
    return block.call

  close -> none:
    closed = true
