/**
The script that drives the page in `page.toit`.

It fetches from the JSON API in `api.toit` and renders whatever comes back,
  so the page holds no state the device does not.

Watch out for dollar signs when editing: they start a string interpolation in
  Toit, so the script sticks to plain concatenation.
*/

/** The script the page runs. */
SCRIPT ::= """
var state = null;
var registers = [];
// The current-limit configuration the last read returned, or null before
// there has been one. What the write button diffs against.
var limits = null;

function hex2(value) { return "0x" + pad2(value.toString(16)); }

function bits4(value) {
  var out = "";
  for (var i = 3; i >= 0; i--) out += (value >> i) & 1;
  return out;
}

function api(path, body) {
  var options = {method: "GET"};
  if (body !== undefined) {
    options = {method: "POST", headers: {"Content-Type": "application/json"},
               body: JSON.stringify(body)};
  }
  return fetch(path, options).then(function (response) {
    return response.json().then(function (data) {
      if (!response.ok) throw new Error(data.error || response.statusText);
      return data;
    });
  });
}

function setStatus(text, bad) {
  var element = document.getElementById("status");
  element.textContent = text;
  element.className = bad ? "sub bad" : "sub";
}

function fail(error) { setStatus(error.message, true); }

function pad2(value) { return ("0" + value).slice(-2); }

function timestamp() {
  var now = new Date();
  return pad2(now.getHours()) + ":" + pad2(now.getMinutes()) + ":" +
      pad2(now.getSeconds());
}

// Newest line first, so the last thing you did is the one under the cursor.
function logLine(text) {
  var log = document.getElementById("log");
  var lines = log.textContent.split("\\n").filter(function (line) {
    return line !== "";
  });
  lines.unshift(timestamp() + "  " + text);
  log.textContent = lines.slice(0, 12).join("\\n") + "\\n";
}

function bitNames(bits) {
  if (!bits || bits.length === 0) return "clean";
  return bits.map(function (bit) { return bit.name; }).join(" ");
}

// A switch state that moved on a poll is one nobody asked for: either a bad
// frame came back in place of SW_STATE, or the device dropped the outputs on
// its own. Either way it belongs in the log with a time on it.
function update(data, source) {
  var before = state === null ? null : state.switchState;
  state = data;
  render();
  setStatus("connected", false);
  if (before !== null && before !== data.switchState) {
    logLine("sw    " + hex2(before) + " -> " + hex2(data.switchState) +
            "  " + source);
  }
  // The server collects FAULT_GLOBAL_TYPE whenever the fault byte says there
  // is something in it, so this line is the only record of a global fault
  // that came and went between two polls.
  if (data.globalRead) {
    logLine("global " + hex2(data.globalFaults) + "  " +
            bitNames(data.globalFaultBits));
  }
  if (data.limits) applyLimits(data.limits);
  var access = data.register;
  if (access) {
    logLine((access.written ? "write " : "read  ") + hex2(access.address) + " " +
            access.name + " = " + hex2(access.value));
    if (!access.written) document.getElementById("val").value =
        pad2(access.value.toString(16));
  }
}

function render() {
  document.getElementById("sw-state").textContent =
      hex2(state.switchState) + " / " + bits4(state.switchState) + "b";
  for (var channel = 1; channel <= 4; channel++) {
    var on = (state.switchState & (1 << (channel - 1))) !== 0;
    var button = document.getElementById("chan" + channel);
    button.textContent = "CH" + channel + (on ? " on" : " off");
    button.className = on ? "chan on" : "chan";
  }
  document.getElementById("fault-hex").textContent = hex2(state.faults);
  renderBits("fault-list", state.faultBits, "no faults");
  document.getElementById("global-hex").textContent =
      state.globalFaults === null ? "not read" : hex2(state.globalFaults);
  renderBits("global-list", state.globalFaultBits,
             state.globalFaults === null ? null : "no global faults");
}

function renderBits(id, bits, emptyText) {
  var list = document.getElementById(id);
  list.innerHTML = "";
  if (!bits || bits.length === 0) {
    if (emptyText) {
      var empty = document.createElement("li");
      empty.className = "ok";
      empty.textContent = emptyText;
      list.appendChild(empty);
    }
    return;
  }
  bits.forEach(function (bit) {
    var item = document.createElement("li");
    item.className = "bad";
    var name = document.createElement("b");
    name.textContent = bit.name;
    item.appendChild(name);
    item.appendChild(document.createTextNode(" " + bit.description + " "));
    if (bit.detailRegister !== null) {
      var jump = document.createElement("button");
      jump.className = "link";
      jump.textContent = "read " + bit.detailRegisterName;
      jump.onclick = function () { selectRegister(bit.detailRegister); doRead(); };
      item.appendChild(jump);
    }
    list.appendChild(item);
  });
}

// The current-limit box. Its selects are built once from the tables the
// device driver knows, and stay empty of values until a read fills them in:
// nothing here is polled, so the page cannot show a limit it has not read.
function buildLimitOptions(data) {
  fillSelect("ilim12", data.ilimCodes);
  fillSelect("ilim34", data.ilimCodes);
  fillSelect("inrush12", data.inrushWindows);
  fillSelect("inrush34", data.inrushWindows);
  fillSelect("inrush-limit", data.inrushLimits);
  limitFields().forEach(function (id) {
    document.getElementById(id).onchange = limitsChanged;
  });
  limitsChanged();
}

function fillSelect(id, entries) {
  var select = document.getElementById(id);
  entries.forEach(function (entry) {
    var option = document.createElement("option");
    option.value = entry.value;
    option.textContent = entry.label;
    select.appendChild(option);
  });
}

function limitFields() {
  return ["ilim12", "inrush12", "ilim34", "inrush34", "split", "timeout",
          "inrush-limit"];
}

// What the controls currently say, in the shape the API takes.
function limitsForm() {
  function value(id) { return Number(document.getElementById(id).value); }
  return {
    ilim12: value("ilim12"),
    inrush12: value("inrush12"),
    ilim34: value("ilim34"),
    inrush34: value("inrush34"),
    split: document.getElementById("split").checked,
    timeout: value("timeout") === 1,
    inrushLimit: value("inrush-limit")
  };
}

function applyLimits(data) {
  limits = data;
  document.getElementById("ilim12").value = data.ilim12;
  document.getElementById("inrush12").value = data.inrush12;
  document.getElementById("ilim34").value = data.ilim34;
  document.getElementById("inrush34").value = data.inrush34;
  document.getElementById("split").checked = data.split;
  document.getElementById("timeout").value = data.timeout ? 1 : 0;
  document.getElementById("inrush-limit").value = data.inrushLimit;
  document.getElementById("limits-raw").textContent =
      "DEV_CONFIG1 " + hex2(data.config1) + "  DEV_CONFIG2 " + hex2(data.config2) +
      "  DEV_CONFIG3 " + hex2(data.config3);
  limitsChanged();
  logLine((data.written ? "write " : "read  ") + "limits  " +
          document.getElementById("ilim12").selectedOptions[0].textContent +
          (data.split ? " / " +
              document.getElementById("ilim34").selectedOptions[0].textContent : ""));
}

// Greys out what does not apply, and offers the write button only once the
// form says something other than what was read back.
function limitsChanged() {
  var form = limitsForm();
  document.getElementById("ilim34").disabled = !form.split;
  document.getElementById("inrush34").disabled = !form.split;
  document.getElementById("inrush-limit").disabled = form.timeout;
  var dirty = limits !== null && Object.keys(form).some(function (key) {
    // A field that does not apply is not a change worth a write.
    if (!form.split && (key === "ilim34" || key === "inrush34")) return false;
    if (form.timeout && key === "inrushLimit") return false;
    return form[key] !== limits[key];
  });
  document.getElementById("limits-write").disabled = !dirty;
}

// Opening the box reads, and that can happen before the pickers have been
// built -- so wait for them. Setting a select that has no options yet would
// leave the form saying something the device never said.
function readLimits() {
  optionsReady.then(function () { act(api("/api/limits")); });
}

function writeLimits() { act(api("/api/limits", limitsForm())); }

function buildChannels() {
  var row = document.getElementById("channels");
  for (var channel = 1; channel <= 4; channel++) {
    var button = document.createElement("button");
    button.className = "chan";
    button.id = "chan" + channel;
    button.dataset.channel = channel;
    button.onclick = function () { toggle(Number(this.dataset.channel)); };
    row.appendChild(button);
  }
}

function buildRegisters(list) {
  registers = list;
  var select = document.getElementById("reg");
  list.forEach(function (register) {
    var option = document.createElement("option");
    option.value = register.address;
    option.textContent = hex2(register.address) + "  " + register.name +
        "  (" + register.access + ")";
    select.appendChild(option);
  });
  select.onchange = describeRegister;
  describeRegister();
}

function currentRegister() {
  var address = Number(document.getElementById("reg").value);
  return registers.filter(function (r) { return r.address === address; })[0];
}

function describeRegister() {
  var register = currentRegister();
  var note = register.description + ".";
  if (register.access === "RC") note += " Reading it clears the bits it returns.";
  if (register.access !== "RW") note += " Not writable.";
  document.getElementById("reg-note").textContent = note;
  document.getElementById("write").disabled = register.access !== "RW";
}

function selectRegister(address) {
  document.getElementById("reg").value = address;
  describeRegister();
}

function parseValue() {
  var text = document.getElementById("val").value.trim();
  if (text.slice(0, 2).toLowerCase() === "0x") text = text.slice(2);
  var value = parseInt(text, 16);
  if (isNaN(value) || value < 0 || value > 255) throw new Error("not a byte: " + text);
  return value;
}

// Polls and actions race. A poll sent before an action can answer after it,
// and painting that answer shows the state from before the action until the
// next poll puts it back -- which is what makes the channels flicker. So
// actions win: a poll answer is dropped if an action started while it was in
// flight. Only one poll is in flight at a time, so a slow device cannot make
// them pile up either.
var actions = 0;
var polling = false;

/** Runs an action request, whose answer always wins over a poll's. */
function act(request) {
  actions++;
  return request.then(function (data) {
    actions--;
    update(data, "click");
  }, function (error) {
    actions--;
    fail(error);
  });
}

// The switch state the last unanswered request asked for, or null when there
// is none. Two quick clicks have to build on what the first one asked for and
// not on the state the page was last painted with, or the second click undoes
// the first.
var wanted = null;

function doRead() {
  act(api("/api/register", {address: currentRegister().address}));
}

function doWrite() {
  var value;
  try {
    value = parseValue();
  } catch (error) {
    fail(error);
    return;
  }
  act(api("/api/register", {address: currentRegister().address, value: value}));
}

function setSwitch(value) {
  wanted = value;
  act(api("/api/switch", {state: value})).then(function () {
    if (actions === 0) wanted = null;
  });
}

function toggle(channel) {
  var base = wanted === null ? state.switchState : wanted;
  setSwitch(base ^ (1 << (channel - 1)));
}

function setAll(on) { setSwitch(on ? 0x0f : 0x00); }

function readGlobal() { act(api("/api/global-faults", {})); }

function poll() {
  if (polling || actions > 0) return;
  polling = true;
  api("/api/state").then(function (data) {
    polling = false;
    // An action started while this was in flight, so its answer is the newer
    // one. Drop this.
    if (actions === 0) update(data, "poll");
  }, function (error) {
    polling = false;
    fail(error);
  });
}

buildChannels();
api("/api/registers").then(function (data) { buildRegisters(data.registers); }).catch(fail);
var optionsReady = api("/api/options").then(buildLimitOptions);
optionsReady.catch(fail);
poll();
setInterval(poll, 1000);
"""
