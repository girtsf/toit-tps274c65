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
