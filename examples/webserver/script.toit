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

function hex3(value) { return "0x" + ("00" + value.toString(16)).slice(-3); }

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
  if (data.adc) applyAdc(data.adc);
  if (data.capture) applyCapture(data.capture);
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
  // The limits box is gated on the switch state, so it has to be revisited
  // whenever that moves and not only when the form does.
  limitsChanged();
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

// The ADC box. Its results are plain `R`, so unlike the fault registers they
// can be polled -- but a full set costs 26 frames, so the poll only asks for
// them while the box is open. Nothing is read at all while the ADC is off:
// every result register would read zero, and zero is a real temperature.
function adcOpen() { return document.getElementById("adc").open; }

function adcToggled() { if (adcOpen()) act(api("/api/adc")); }

function setAdc(enabled) { act(api("/api/adc", {enabled: enabled})); }

function applyAdc(data) {
  document.getElementById("adc-en").checked = data.enabled;
  // The message beside the checkbox is only there to explain an empty table.
  document.getElementById("adc-vs").textContent =
      data.enabled ? "" : "off, so nothing is converted";
  adcConversions = data.conversions;
  document.querySelectorAll("input.adc-kind").forEach(function (box) {
    var mask = adcConversions[box.dataset.kind];
    box.checked = mask === ALL_CHANNELS;
    box.indeterminate = mask !== 0 && mask !== ALL_CHANNELS;
  });
  var rows = document.getElementById("adc-rows");
  rows.innerHTML = "";
  if (!data.enabled) return;
  data.channels.forEach(function (entry) {
    var channel = entry.channel;
    // Current and output voltage only mean something while the channel is on.
    var off = (state.switchState & (1 << (channel - 1))) === 0;
    var row = document.createElement("tr");
    row.appendChild(channelCell(channel));
    row.appendChild(readingCell(channel, "current",
        entry.milliAmps.toFixed(0) + " mA", hex3(entry.current), off));
    row.appendChild(readingCell(channel, "temperature",
        entry.celsius.toFixed(1) + " C", hex2(entry.temperature), false));
    row.appendChild(readingCell(channel, "output",
        entry.volts.toFixed(1) + " V", hex2(entry.voltage), off));
    rows.appendChild(row);
  });
  // The supply is not a channel, but it is a voltage, so it goes in the
  // voltage column under the four outputs it feeds.
  var supply = document.createElement("tr");
  supply.appendChild(checkCell("VS", adcConversions.supply, function () {
    setAdcConversions({supply: this.checked});
  }));
  supply.appendChild(cell(""));
  supply.appendChild(cell(""));
  supply.appendChild(adcConversions.supply
      ? cell(data.supplyVolts.toFixed(2) + " V", hex3(data.supply))
      : cell("skipped", undefined, true));
  rows.appendChild(supply);
}

var ALL_CHANNELS = 0x0f;
var ADC_KINDS = ["current", "temperature", "output"];
// Which conversions the ADC makes: a channel mask per kind, and the supply.
var adcConversions = {current: ALL_CHANNELS, temperature: ALL_CHANNELS,
                      output: ALL_CHANNELS, supply: true};

// Sends the conversions with the ones in changes replaced.
function setAdcConversions(changes) {
  var body = {};
  Object.keys(adcConversions).forEach(function (key) {
    body[key] = key in changes ? changes[key] : adcConversions[key];
  });
  act(api("/api/adc-conversions", body));
}

// Turns the given kinds of conversion on or off for the channels in mask.
function setAdcChannels(kinds, mask, enabled) {
  var changes = {};
  kinds.forEach(function (kind) {
    var current = adcConversions[kind];
    changes[kind] = enabled ? current | mask : current & ~mask;
  });
  setAdcConversions(changes);
}

// The column headers turn a conversion on or off for all four channels.
function buildAdcKinds() {
  document.querySelectorAll("input.adc-kind").forEach(function (box) {
    box.onchange = function () { setAdcChannels([this.dataset.kind], ALL_CHANNELS, this.checked); };
  });
}

function channelConverted(channel, kind) {
  return (adcConversions[kind] & (1 << (channel - 1))) !== 0;
}

// The first cell of a channel row: its name, and a checkbox covering all
// three of its conversions, part-checked when only some of them are made.
function channelCell(channel) {
  var converted = ADC_KINDS.filter(function (kind) { return channelConverted(channel, kind); });
  var td = checkCell("CH" + channel, converted.length === ADC_KINDS.length, function () {
    setAdcChannels(ADC_KINDS, 1 << (channel - 1), this.checked);
  });
  td.querySelector("input").indeterminate =
      converted.length > 0 && converted.length < ADC_KINDS.length;
  return td;
}

// A reading, with a checkbox for whether its conversion is made. Reads
// "skipped" when it is not: the register keeps whatever the last conversion
// left there.
function readingCell(channel, kind, text, raw, dim) {
  var converted = channelConverted(channel, kind);
  var td = converted ? cell(text, raw, dim) : cell("skipped", undefined, true);
  var box = document.createElement("input");
  box.type = "checkbox";
  box.checked = converted;
  box.onchange = function () { setAdcChannels([kind], 1 << (channel - 1), this.checked); };
  td.insertBefore(box, td.firstChild);
  return td;
}

// A table cell holding a labelled checkbox.
function checkCell(text, checked, onchange) {
  var td = document.createElement("td");
  var label = document.createElement("label");
  var box = document.createElement("input");
  box.type = "checkbox";
  box.checked = checked;
  box.onchange = onchange;
  label.appendChild(box);
  label.appendChild(document.createTextNode(" " + text));
  td.appendChild(label);
  return td;
}

// A table cell holding a converted value, the conversion it came from beside
// it, and greyed out when the reading does not apply.
function cell(text, raw, dim) {
  var td = document.createElement("td");
  td.textContent = text;
  if (raw !== undefined) {
    var span = document.createElement("span");
    span.className = "raw";
    span.textContent = raw;
    td.appendChild(span);
  }
  if (dim) td.className = "off";
  return td;
}

// The turn-on capture box. Nothing here is polled: a capture holds the bus
// for its whole length and switches a channel on, so it only ever happens
// because the button was pressed.
var CHART = {w: 720, h: 280, left: 56, right: 16, top: 14, bottom: 58};
// The fault lane, between the plot and the time axis.
var LANE = {gap: 8, height: 8};

function buildCaptureChannels() {
  var select = document.getElementById("cap-channel");
  for (var channel = 1; channel <= 4; channel++) {
    var option = document.createElement("option");
    option.value = channel;
    option.textContent = "CH" + channel;
    select.appendChild(option);
  }
}

function runCapture() {
  var button = document.getElementById("cap-run");
  button.disabled = true;
  document.getElementById("cap-stats").textContent = "capturing...";
  var body = {
    channel: Number(document.getElementById("cap-channel").value),
    preMs: Number(document.getElementById("cap-pre").value),
    postMs: Number(document.getElementById("cap-post").value)
  };
  // The device is off the air for the length of the capture plus the
  // discharge wait, so the poll behind act() queues behind it.
  act(api("/api/capture", body)).then(function () { button.disabled = false; });
}

function applyCapture(data) {
  var line = "CH" + data.channel + "  " + data.micros.length + " points  peak " +
      data.peakMilliAmps.toFixed(0) + " mA  " + data.frames + " frames in " +
      (data.spanMicros / 1000).toFixed(1) + " ms, " +
      data.frameMicros.toFixed(1) + " us each";
  line += "  --  faults seen: " + bitNames(data.faultsSeenBits);
  var bad = false;
  // The bus is meant to outrun the device. If it stops doing that the trace
  // is missing conversions and the shape is no longer trustworthy.
  if (data.frameMicros > data.conversionMicros) {
    line += "  --  BUS SLOWER THAN THE ADC, points are being missed";
    bad = true;
  }
  // The point bound is derived from the window, so this should not happen
  // at all -- and if it does, the tail of the trace is simply gone.
  if (data.truncated) {
    line += "  --  TRUNCATED, the trace ends early";
    bad = true;
  }
  var stats = document.getElementById("cap-stats");
  stats.textContent = line;
  stats.className = bad ? "mono warn" : "mono";
  drawCapture(data);
}

function svgEl(name, attrs) {
  var node = document.createElementNS("http://www.w3.org/2000/svg", name);
  for (var key in attrs) node.setAttribute(key, attrs[key]);
  return node;
}

// A round tick step of about a sixth of the span, so the axis reads 0, 10,
// 20 rather than 0, 8.33, 16.67.
function niceStep(span, divisions) {
  var raw = span / divisions;
  if (!(raw > 0)) return 1;
  var magnitude = Math.pow(10, Math.floor(Math.log(raw) / Math.LN10));
  var normalised = raw / magnitude;
  var step = normalised >= 5 ? 5 : normalised >= 2 ? 2 : 1;
  return step * magnitude;
}

// The trace is a step function: a point is a value and the time it started,
// and it holds until the next one. So the line goes across before it goes up,
// and never diagonally -- a slope would draw current the device never
// reported.
function stairs(data, from, X, Y) {
  var points = [];
  for (var i = from; i < data.micros.length; i++) {
    var x = X(data.micros[i] / 1000);
    if (i > from) points.push(x + "," + Y(data.milliAmps[i - 1]));
    points.push(x + "," + Y(data.milliAmps[i]));
  }
  return points.join(" ");
}

function drawCapture(data) {
  var host = document.getElementById("cap-chart");
  host.innerHTML = "";
  var count = data.micros.length;
  if (count < 2) return;

  var plotWidth = CHART.w - CHART.left - CHART.right;
  var plotHeight = CHART.h - CHART.top - CHART.bottom;
  var t0 = data.micros[0] / 1000;
  var t1 = data.micros[count - 1] / 1000;
  if (t1 <= t0) t1 = t0 + 1;
  var limit = data.limit ?
      Math.max(data.limit.inrushMilliAmps, data.limit.steadyMilliAmps) : 0;
  // Room above the taller of the trace and the limit, so the limit lines
  // stay on the chart even when the trace never reaches them.
  var full = Math.max(data.peakMilliAmps, limit) * 1.15;
  if (!(full > 0)) full = 100;

  function X(ms) {
    return CHART.left + (ms - t0) / (t1 - t0) * plotWidth;
  }
  function Y(milliAmps) {
    return CHART.top + plotHeight - Math.min(1, milliAmps / full) * plotHeight;
  }

  var svg = svgEl("svg", {"class": "chart",
                          viewBox: "0 0 " + CHART.w + " " + CHART.h});

  // The dead zone: the device is not sensing yet, so whatever the register
  // says there is left over from before the turn-on.
  var deadEnd = Math.min(X(data.settlingMicros / 1000), CHART.left + plotWidth);
  if (deadEnd > X(0)) {
    svg.appendChild(svgEl("rect", {"class": "dead", x: X(0), y: CHART.top,
                                   width: deadEnd - X(0), height: plotHeight}));
  }

  // Horizontal grid and the current axis.
  var currentStep = niceStep(full, 4);
  for (var level = 0; level <= full; level += currentStep) {
    svg.appendChild(svgEl("line", {"class": "grid", x1: CHART.left, x2: CHART.left + plotWidth,
                                   y1: Y(level), y2: Y(level)}));
    var label = svgEl("text", {x: CHART.left - 6, y: Y(level) + 3,
                               "text-anchor": "end"});
    label.textContent = level.toFixed(0);
    svg.appendChild(label);
  }
  var unit = svgEl("text", {x: CHART.left - 6, y: CHART.top - 4, "text-anchor": "end"});
  unit.textContent = "mA";
  svg.appendChild(unit);

  // Time axis, anchored on zero so the switch write is always a tick.
  var timeStep = niceStep(t1 - t0, 6);
  var first = Math.ceil(t0 / timeStep) * timeStep;
  for (var when = first; when <= t1; when += timeStep) {
    svg.appendChild(svgEl("line", {"class": "grid", x1: X(when), x2: X(when),
                                   y1: CHART.top, y2: CHART.top + plotHeight}));
    var tick = svgEl("text", {x: X(when), y: CHART.h - 22, "text-anchor": "middle"});
    tick.textContent = when.toFixed(timeStep < 1 ? 1 : 0);
    svg.appendChild(tick);
  }
  // On its own baseline under the ticks: at the right edge it would sit on
  // top of the last one.
  var axis = svgEl("text", {x: CHART.left + plotWidth / 2, y: CHART.h - 8,
                            "text-anchor": "middle"});
  axis.textContent = "milliseconds from the switch write";
  svg.appendChild(axis);

  // The limits the current is being held at. Two lines when the inrush
  // window has a limit of its own, one when it does not.
  if (data.limit) {
    drawLevel(svg, X, Y, data.limit.inrushMilliAmps, plotWidth,
              data.limit.timeout ? "limit" : "inrush limit");
    if (data.limit.inrushMilliAmps !== data.limit.steadyMilliAmps) {
      drawLevel(svg, X, Y, data.limit.steadyMilliAmps, plotWidth, "after the window");
    }
    // Where the inrush window ends and the limit changes back.
    var windowEnd = data.limit.windowMs;
    if (windowEnd > 0 && windowEnd <= t1) {
      svg.appendChild(svgEl("line", {"class": "window", x1: X(windowEnd), x2: X(windowEnd),
                                     y1: CHART.top, y2: CHART.top + plotHeight}));
      var mark = svgEl("text", {"class": "key", x: X(windowEnd) + 3, y: CHART.top + 22});
      mark.textContent = "window ends";
      svg.appendChild(mark);
    }
  }

  // The fault lane: where the device was reporting a current limit. A
  // channel being held at the limit is regulating rather than fully on, and
  // the current sense is gated on being fully on -- so the conversion sits on
  // whatever it last held, which is usually zero. Without this lane that
  // stretch reads as "no current" instead of "not sensing".
  var laneTop = CHART.top + plotHeight + LANE.gap;
  svg.appendChild(svgEl("rect", {"class": "lane", x: CHART.left, y: laneTop,
                                 width: plotWidth, height: LANE.height}));
  for (var i = 0; i < count - 1; i++) {
    if ((data.faults[i] & data.ilimitMask) === 0) continue;
    var from = X(data.micros[i] / 1000);
    var to = X(data.micros[i + 1] / 1000);
    svg.appendChild(svgEl("rect", {"class": "lane hit", x: from, y: laneTop,
                                   width: Math.max(1, to - from),
                                   height: LANE.height}));
  }
  var laneLabel = svgEl("text", {"class": "key", x: CHART.left - 6,
                                 y: laneTop + LANE.height, "text-anchor": "end"});
  laneLabel.textContent = "ILIMIT";
  svg.appendChild(laneLabel);

  // The switch write itself.
  svg.appendChild(svgEl("line", {"class": "trigger", x1: X(0), x2: X(0),
                                 y1: CHART.top, y2: CHART.top + plotHeight}));
  var trigger = svgEl("text", {"class": "key", x: X(0) + 3, y: CHART.top + 10});
  trigger.textContent = "on";
  svg.appendChild(trigger);

  // The trace twice: the whole of it faintly, then the part that is a real
  // measurement solidly on top of it.
  svg.appendChild(svgEl("polyline", {"class": "trace dim",
                                     points: stairs(data, 0, X, Y)}));
  if (data.validIndex < count - 1) {
    svg.appendChild(svgEl("polyline", {"class": "trace",
                                       points: stairs(data, data.validIndex, X, Y)}));
  }
  host.appendChild(svg);
}

function drawLevel(svg, X, Y, milliAmps, plotWidth, text) {
  svg.appendChild(svgEl("line", {"class": "limit", x1: CHART.left,
                                 x2: CHART.left + plotWidth,
                                 y1: Y(milliAmps), y2: Y(milliAmps)}));
  var label = svgEl("text", {"class": "key", x: CHART.left + plotWidth - 2,
                             y: Y(milliAmps) - 4, "text-anchor": "end"});
  label.textContent = text + " " + milliAmps + " mA";
  svg.appendChild(label);
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
// form says something other than what was read back -- and only while every
// output is off. The four registers behind this box stop accepting writes
// while any channel is on and the device drops them in silence, so the button
// has to go away rather than send one. The selects stay live: staging a
// change, switching the outputs off and then writing is a reasonable way
// round.
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
  var live = state !== null && state.switchState !== 0;
  document.getElementById("limits-write").disabled = !dirty || live;
  document.getElementById("limits-locked").textContent = live ?
      "locked: switch every output off first" : "";
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
  // While the ADC box is open the poll collects the readings too, so the two
  // never have a request in flight at the same time.
  api(adcOpen() ? "/api/adc" : "/api/state").then(function (data) {
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
buildCaptureChannels();
buildAdcKinds();
api("/api/registers").then(function (data) { buildRegisters(data.registers); }).catch(fail);
var optionsReady = api("/api/options").then(buildLimitOptions);
optionsReady.catch(fail);
poll();
setInterval(poll, 1000);
"""
