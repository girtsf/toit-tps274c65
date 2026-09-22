/** The stylesheet of the page in `page.toit`. */

/** The stylesheet the page is rendered with. */
STYLE ::= """
body { font: 15px/1.5 system-ui, sans-serif; margin: 0 auto; padding: 1.5rem;
       max-width: 46rem; color: #222; background: #fafafa; }
h1 { font-size: 1.4rem; margin: 0; }
h2 { font-size: 1rem; margin: 0 0 .6rem; text-transform: uppercase;
     letter-spacing: .06em; color: #666; }
section { background: #fff; border: 1px solid #ddd; border-radius: 6px;
          padding: 1rem; margin-top: 1rem; }
.row { display: flex; flex-wrap: wrap; gap: .5rem; align-items: center; }
.mono, pre, select, input { font-family: ui-monospace, Menlo, monospace; }
button { font: inherit; padding: .35rem .7rem; border: 1px solid #bbb;
         border-radius: 4px; background: #f0f0f0; cursor: pointer; }
button:disabled { opacity: .4; cursor: not-allowed; }
button.chan { min-width: 6rem; font-family: ui-monospace, Menlo, monospace; }
button.chan.on { background: #1a7f37; border-color: #1a7f37; color: #fff; }
button.link { border: none; background: none; color: #0969da; padding: 0 .3rem;
              text-decoration: underline; }
select, input { font-size: inherit; padding: .3rem; border: 1px solid #bbb;
                border-radius: 4px; }
ul { list-style: none; padding: 0; margin: .6rem 0 0; }
li { padding: .3rem .5rem; border-radius: 4px; margin-bottom: .25rem; }
li.bad { background: #fff1f0; border-left: 3px solid #cf222e; }
li.ok { background: #f2fbf4; border-left: 3px solid #1a7f37; color: #555; }
table { border-collapse: collapse; margin-top: .8rem; font-variant-numeric: tabular-nums; }
th, td { text-align: right; padding: .3rem .8rem .3rem 0; border-bottom: 1px solid #eee; }
th { color: #666; font-size: .85rem; font-weight: normal; text-transform: uppercase;
     letter-spacing: .06em; }
td { font-family: ui-monospace, Menlo, monospace; }
td.off { color: #999; }
td > input { margin: 0 .3rem 0 0; }
td:first-child, th:first-child { text-align: left; }
.raw { color: #999; font-size: .8rem; margin-left: .4rem; }
summary { cursor: pointer; }
summary h2 { display: inline; margin: 0; }
.field { color: #666; font-size: .85rem; min-width: 9.5rem; }
.note { color: #666; font-size: .85rem; margin: .6rem 0 0; }
.sub { color: #666; margin: .2rem 0 0; font-size: .85rem; }
.sub.bad { color: #cf222e; }
pre { background: #f6f6f6; border-radius: 4px; padding: .6rem; margin: .6rem 0 0;
      min-height: 1.5rem; overflow-x: auto; font-size: .85rem; }
.chart { display: block; width: 100%; height: auto; margin-top: .8rem;
         border: 1px solid #eee; border-radius: 4px; }
.chart text { font: 10px ui-monospace, Menlo, monospace; fill: #888; }
.chart .grid { stroke: #eee; }
.chart .dead { fill: #f2f2f2; }
.chart .trace { fill: none; stroke: #0969da; stroke-width: 1.5; }
.chart .trace.dim { stroke: #bbb; stroke-width: 1; stroke-dasharray: 3 3; }
.chart .trigger { stroke: #1a7f37; }
.chart .limit { stroke: #cf222e; stroke-dasharray: 5 3; }
.chart .window { stroke: #8250df; stroke-dasharray: 2 3; }
.chart .key { fill: #666; }
.chart .lane { fill: #f0f0f0; }
.chart .lane.hit { fill: #cf222e; }
.warn { color: #cf222e; }
"""
