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

<script>
$SCRIPT</script>
</body>
</html>
"""
