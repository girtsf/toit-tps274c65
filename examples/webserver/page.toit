/** The single page the UI is made of. */

import .script
import .style

/** The whole page, with $STYLE and $SCRIPT inlined. */
PAGE ::= """
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>TPS274C65</title>
<link rel="icon" href="data:,">  <!-- No favicon, and no 404 asking for one. -->
<style>
$STYLE</style>
</head>
<body>
<h1>TPS274C65</h1>
<p class="sub" id="status">connecting</p>

<section>
<h2>Switches</h2>
<div class="row" id="channels"></div>
<p class="note">SW_STATE reads back <span class="mono" id="sw-state">--</span></p>
<div class="row">
<button onclick="setAll(true)">all on</button>
<button onclick="setAll(false)">all off</button>
</div>
</section>

<section>
<h2>Faults</h2>
<p class="mono">FAULT_TYPE_STAT = <span id="fault-hex">--</span></p>
<ul id="fault-list"></ul>
<div class="row" style="margin-top:.8rem">
<button onclick="readGlobal()">read FAULT_GLOBAL_TYPE</button>
<span class="mono" id="global-hex">not read</span>
</div>
<ul id="global-list"></ul>
<p class="note">FAULT_GLOBAL_TYPE is read-to-clear, so the page reads it only
when you ask. Everything else here refreshes once a second.</p>
</section>

<section>
<details id="adc" ontoggle="adcToggled()">
<summary><h2>ADC</h2></summary>

<div class="row">
<label><input type="checkbox" id="adc-en" onchange="setAdc(this.checked)"> run
the ADC</label>
<span class="mono" id="adc-vs">--</span>
</div>

<table>
<thead>
<tr><th></th><th>current</th><th>temperature</th><th>output</th></tr>
</thead>
<tbody id="adc-rows"></tbody>
</table>

<p class="note">The current assumes the 1 kOhm RSNS the datasheet recommends,
which puts full scale at 3.25 A; a board with another one reads proportionally
wrong. Temperature is the junction of each FET, and the only reading that means
anything while a channel is off -- current and output voltage both sit near
zero there. A round of the ADC takes 1.7 ms, so a reading is at most that
stale, and it costs 38 frames to collect the lot, which is why this box is
polled only while it is open.</p>
</details>
</section>

<section>
<details id="capture">
<summary><h2>Turn-on capture</h2></summary>

<div class="row">
<span class="field">channel</span>
<select id="cap-channel"></select>
<span class="field">ms before / after</span>
<input id="cap-pre" size="3" value="5" title="milliseconds of baseline">
<input id="cap-post" size="3" value="45" title="milliseconds after the switch write">
<button id="cap-run" onclick="runCapture()">capture</button>
</div>

<div id="cap-chart"></div>
<p class="mono" id="cap-stats">not captured</p>

<p class="note">Switches the channel on and records its current sense across
the event, with the whole ADC round robin trimmed down to that one conversion
so a reading lands every 128 us instead of every 1.7 ms. The switching edge is
not in the trace and cannot be -- the FET is fully on inside 42 us -- and the
first half millisecond after the write, shaded, is the device's own sense
settling and is not a measurement. What the trace is for is the inrush window,
which runs 2 ms to 64 ms. The red line is the limit; do not expect the trace
to sit on it, because a channel being held at the limit reads zero rather
than reading the limit -- see the ILIMIT lane below. A channel that is already on is switched off first and given
200 ms to discharge, and is left on at the end.</p>

<p class="note">The ILIMIT lane under the plot is the fault byte, which every
frame carries for free. Read it before reading a flat stretch of zero as no
current: the sense is gated on the switch being fully on, and a channel held
at the limit is regulating rather than fully on, so its conversion register
sits on whatever it last held. Zero with ILIMIT under it is the device
declining to sense, not a channel drawing nothing.</p>

<p class="note">For the length of the capture the device is put on the
real-time fault path (FLT_LTCH_DIS in DEV_CONFIG5, restored afterwards). The
fault bits latch by default and clear only when the read-to-clear register
behind them is read, which a capture will not do -- so on the latched path the
lane could turn red and never turn back, and a fault latched before the
capture would cover the whole trace. On the real-time path it follows the
condition, so both its edges mean something.</p>
</details>
</section>

<section>
<h2>Registers</h2>
<div class="row">
<select id="reg"></select>
<input id="val" size="4" value="00" title="hex">
<button onclick="doRead()">read</button>
<button id="write" onclick="doWrite()">write</button>
</div>
<p class="note" id="reg-note"></p>
<pre id="log"></pre>
</section>

<section>
<details id="limits" ontoggle="if (this.open) readLimits()">
<summary><h2>Current limits</h2></summary>

<div class="row">
<button onclick="readLimits()">read current values</button>
<span class="mono" id="limits-raw">not read</span>
</div>

<div class="row">
<span class="field">channels 1 and 2</span>
<select id="ilim12"></select>
<select id="inrush12"></select>
</div>

<div class="row">
<span class="field"><label><input type="checkbox" id="split"> split 3 and 4</label></span>
<select id="ilim34"></select>
<select id="inrush34"></select>
</div>

<div class="row">
<span class="field">the window is</span>
<select id="timeout">
<option value="0">an inrush period, fault hidden</option>
<option value="1">time allowed in limit, fault reported</option>
</select>
</div>

<div class="row">
<span class="field">limit in the window</span>
<select id="inrush-limit"></select>
</div>

<div class="row" style="margin-top:.8rem">
<button id="limits-write" onclick="writeLimits()" disabled>write</button>
<span class="note" id="limits-locked" style="margin:0"></span>
</div>

<p class="note">Every output has to be off to write any of this. DEV_CONFIG1,
DEV_CONFIG2, DEV_CONFIG3 and DEV_CONFIG6 -- the current limits, the inrush
behaviour, the sense range and the reverse-blocking gates -- stop accepting
writes while any channel is on, and the device drops them without saying so:
no SPI_ERR, nothing in the fault byte. One channel up locks all four, even the
ones that govern the other pair, so switching off just the channel being
changed is not enough. The driver throws rather than let such a write go out.
The datasheet says this of the two PARALLEL bits only.</p>

<p class="note">Split gives channels 3 and 4 a limit of their own, in
DEV_CONFIG2; without it DEV_CONFIG1 governs all four and DEV_CONFIG2 is left
alone. Writing goes through the driver, so the DEV_CONFIG3 bits this box does
not show -- RCB_DIS, ISNS_RANGE, paralleling -- survive it. The limits are the
ones an AS or BS part selects; an ASH part codes them differently.</p>
</details>
</section>

<script>
$SCRIPT</script>
</body>
</html>
"""
