/**
The JSON API the page talks to, and the page itself.

Every handler answers with the full device state, so any action the page takes
  also refreshes what it shows.
*/

import encoding.json
import http
import monitor
import net
import tps274c65

import .page

/** How many requests may be in flight at once. */
MAX-TASKS ::= 4

/** The web UI and the JSON API behind it. */
class Ui:
  driver_/tps274c65.Driver
  /** Serializes the bus: several request tasks share the one driver. */
  mutex_/monitor.Mutex ::= monitor.Mutex
  /** The contents of the most recent global fault read, or null. */
  global-faults_/int? := null

  constructor .driver_:

  /** Serves the UI on $port until the network goes away. */
  listen network/net.Client port/int -> none:
    server := http.Server --max-tasks=MAX-TASKS
    server.listen network port:: | request/http.RequestIncoming writer/http.ResponseWriter |
      handle_ request writer

  handle_ request/http.RequestIncoming writer/http.ResponseWriter -> none:
    resource := request.query.resource
    // Every handler builds its whole answer before anything is written, so
    // the error path below can still pick the status code.
    error := catch --trace:
      response := route_ resource request
      if response == null:
        writer.headers.set "Content-Type" "text/plain"
        writer.write-headers 404
        writer.out.write "no such resource: $resource\n"
      else if response is string:
        writer.headers.set "Content-Type" "text/html; charset=utf-8"
        writer.out.write response
      else:
        writer.headers.set "Content-Type" "application/json"
        writer.out.write (json.encode response)
    if error:
      writer.headers.set "Content-Type" "application/json"
      writer.write-headers 500
      writer.out.write (json.encode {"error": "$error"})
    writer.close

  /**
  Returns the answer to $resource: the page as a string, a map to encode as
    JSON, or null when there is nothing at $resource.
  */
  route_ resource/string request/http.RequestIncoming -> any:
    if resource == "/": return PAGE
    if resource == "/api/registers": return {"registers": registers-payload}
    if resource == "/api/options": return options-payload
    if resource == "/api/limits":
      if request.method == http.GET: return read-limits_
      return write-limits_ (json.decode-stream request.body)
    if resource == "/api/state": return state_
    if resource == "/api/global-faults":
      json.decode-stream request.body  // Drain the empty body.
      return read-global-faults_
    if resource == "/api/switch":
      return set-switch_ (json.decode-stream request.body)["state"]
    if resource == "/api/register":
      payload := json.decode-stream request.body
      if payload.contains "value":
        return write-register_ payload["address"] payload["value"]
      return read-register_ payload["address"]
    return null

  /**
  Returns the switch state and the decoded fault byte.

  Costs one register read. `SW_STATE` is plain `RW`, so polling it is free of
    side effects, and the fault byte rides along on the same frames.

  Reads nothing else. Every other fault register is read-to-clear, so a poll
    that touched one would wipe latched faults as fast as they arrived; they
    are read only when asked for.
  */
  state_ -> Map:
    switch-state := 0
    faults := 0
    mutex_.do:
      // Reserved bits read back as ones, so mask down to the four channels.
      switch-state = 0x0f & (driver_.read-register tps274c65.REG-SW-STATE)
      // Read under the same lock, so it belongs to the frames just sent.
      faults = driver_.faults
    result := {
      "switchState": switch-state,
      "faults": faults,
      "faultBits": bits-payload (tps274c65.decode-faults faults),
      "globalFaults": null,
      "globalFaultBits": null,
    }
    global := global-faults_
    if global != null:
      result["globalFaults"] = global
      result["globalFaultBits"] = bits-payload (tps274c65.decode-global-faults global)
    return result

  /**
  Reads and clears `FAULT_GLOBAL_TYPE`, and remembers what it said.

  The page does not poll this one: it is read-to-clear, so polling would wipe
    latched faults as fast as they arrived. $state_ keeps reporting the value
    from here until the next read.
  */
  read-global-faults_ -> Map:
    global-faults_ = mutex_.do: driver_.read-global-faults
    return state_

  /** Sets all four channels at once from the mask in $state. */
  set-switch_ state/int -> Map:
    mutex_.do: driver_.switch-state = state
    return state_

  read-register_ address/int -> Map:
    value/int := mutex_.do: driver_.read-register address
    return with-register_ address value --no-written

  write-register_ address/int value/int -> Map:
    mutex_.do: driver_.write-register address value
    return with-register_ address value --written

  /**
  Reads the three registers behind the current-limit box.

  All three are plain `RW`, so this has no side effects. Costs six frames,
    two per read, which is why the page asks for it rather than polling it.
  */
  read-limits_ -> Map:
    config1 := 0
    config2 := 0
    config3 := 0
    mutex_.do:
      config1 = driver_.read-register tps274c65.REG-DEV-CONFIG1
      config2 = driver_.read-register tps274c65.REG-DEV-CONFIG2
      config3 = driver_.read-register tps274c65.REG-DEV-CONFIG3
    return with-limits_ config1 config2 config3 --no-written

  /**
  Puts the current limits in $payload back on the device.

  Goes through the driver rather than writing the three registers directly,
    so `DEV_CONFIG3` keeps the bits this box is not about -- `RCB_DIS`,
    `ISNS_RANGE` and the paralleling bits -- and so `ILIM_SET` is set only
    after the register it switches to has been written.

  `DEV_CONFIG2` is left alone unless the limits are split. It is what
    `ILIM_SET` selects, and nothing reads it while that bit is clear.

  Answers with a fresh read, so the page shows what the device took rather
    than what it was sent.
  */
  write-limits_ payload/Map -> Map:
    ilim-12 := tps274c65.IlimCode.ALL[payload["ilim12"]]
    ilim-34 := tps274c65.IlimCode.ALL[payload["ilim34"]]
    inrush-12 := tps274c65.InrushWindow.ALL[payload["inrush12"]]
    inrush-34 := tps274c65.InrushWindow.ALL[payload["inrush34"]]
    split/bool := payload["split"]
    mutex_.do:
      driver_.set-inrush-mode
          --limit=payload["inrushLimit"]
          --timeout=payload["timeout"]
      if split:
        driver_.set-current-limit-split
            --channels-1-2=ilim-12
            --channels-3-4=ilim-34
            --inrush-1-2=inrush-12
            --inrush-3-4=inrush-34
      else:
        driver_.set-current-limit ilim-12 --inrush=inrush-12
    result := read-limits_
    result["limits"]["written"] = true
    return result

  /** Returns $state_ with the decoded current-limit configuration attached. */
  with-limits_ config1/int config2/int config3/int --written/bool -> Map:
    result := state_
    result["limits"] = {
      "config1": config1,
      "config2": config2,
      "config3": config3,
      "ilim12": config1 & tps274c65.ILIM-REG-MASK,
      "ilim34": config2 & tps274c65.ILIM-REG-MASK,
      "inrush12": (config1 & tps274c65.ILIM-DURATION-MASK) >> tps274c65.ILIM-DURATION-SHIFT,
      "inrush34": (config2 & tps274c65.ILIM-DURATION-MASK) >> tps274c65.ILIM-DURATION-SHIFT,
      "split": (config3 & tps274c65.CONFIG3-ILIM-SET) != 0,
      "timeout": (config3 & tps274c65.CONFIG3-ILIM-CONFIG) != 0,
      "inrushLimit": config3 & tps274c65.CONFIG3-INRUSH-LIMIT-MASK,
      "written": written,
    }
    return result

  /** Returns $state_ with the result of a register access attached. */
  with-register_ address/int value/int --written/bool -> Map:
    result := state_
    register/tps274c65.Register? := tps274c65.register-for address
    result["register"] = {
      "address": address,
      "name": register == null ? "reserved" : register.name,
      "value": value,
      "written": written,
    }
    return result

/** Returns the register table the page fills its picker from. */
registers-payload -> List:
  return tps274c65.REGISTERS.map: | register/tps274c65.Register |
    {
      "address": register.address,
      "name": register.name,
      "description": register.description,
      "access": register.access,
    }

/**
The `INRUSH_LIMIT` codes, by code, as the current-limit box labels them.

The driver has the codes as constants but nothing to render them with, these
  four being the only place they show up.
*/
INRUSH-LIMIT-LABELS ::= [
  "1x the limit",
  "2x the limit",
  "0.5x the limit",
  "fixed 2.2 A",
]

/** Returns the tables the current-limit box fills its pickers from. */
options-payload -> Map:
  ilim-codes := tps274c65.IlimCode.ALL.map: | code/tps274c65.IlimCode |
    {"value": code.value, "label": "$code"}
  windows := tps274c65.InrushWindow.ALL.map: | window/tps274c65.InrushWindow |
    {"value": window.value, "label": window.value == 0 ? "no window" : "$window"}
  inrush-limits := []
  INRUSH-LIMIT-LABELS.size.repeat:
    entry := {"value": it, "label": INRUSH-LIMIT-LABELS[it]}
    inrush-limits.add entry
  return {
    "ilimCodes": ilim-codes,
    "inrushWindows": windows,
    "inrushLimits": inrush-limits,
  }

/** Returns the JSON form of the $tps274c65.FaultBit entries in $bits. */
bits-payload bits/List -> List:
  return bits.map: | bit/tps274c65.FaultBit |
    detail := bit.detail-register
    {
      "name": bit.name,
      "description": bit.description,
      "detailRegister": detail,
      "detailRegisterName": detail == null ? null : (tps274c65.register-for detail).name,
    }
