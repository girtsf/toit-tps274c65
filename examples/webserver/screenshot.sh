#!/bin/sh
# Retakes screenshot.png, the picture of the UI in the top-level README.
#
# Serves the UI on the fake device in demo-server.toit, drives it with
# shot-scraper, and shoots the result. shot-scraper runs through uvx, so the
# only thing to install first is the headless browser it drives:
#
#     uvx shot-scraper install
#
# Then, from anywhere:
#
#     examples/webserver/screenshot.sh
#
# The page is 46rem wide, so 820 pixels leaves it a small margin.

set -eu

TOIT="${TOIT:-$(command -v toit > /dev/null && echo toit || echo 'jag toit')}"
DIR="$(cd "$(dirname "$0")" && pwd)"
URL="http://localhost:8099/"

# Never shoot a server this script did not start: it could be an older one
# left holding the port, showing something else entirely.
if curl -sf -o /dev/null "$URL"; then
  echo "something is already serving $URL" >&2
  exit 1
fi

# `toit run` runs the program in a grandchild, which survives a kill aimed at
# the process this script starts. Put the server in its own process group so
# the whole tree can be signalled at once.
if command -v setsid > /dev/null 2>&1; then
  setsid $TOIT run "$DIR/demo-server.toit" &
  SERVER=$!
  STOP="kill -- -$SERVER"
else
  $TOIT run "$DIR/demo-server.toit" &
  SERVER=$!
  STOP="kill $SERVER"
fi
trap '$STOP 2> /dev/null || true' EXIT

# The server is up once it answers; give it a few seconds to get there.
i=0
until curl -sf -o /dev/null "$URL"; do
  i=$((i + 1))
  [ "$i" -lt 30 ] || { echo "server did not come up" >&2; exit 1; }
  sleep 1
done

# Turn two channels on, then read a few registers, so the page has both a
# switch state and a readout to show. Everything called here is a function the
# page itself defines, so this drives the real UI rather than faking its
# output. The registers read here are plain `RW`, on purpose: reading
# ILIMIT_CH_STAT would clear the ILIMIT fault the picture is meant to show.
uvx shot-scraper shot "$URL" \
  --width 820 \
  --wait-for 'state !== null' \
  --javascript "$(cat <<'JS'
(async () => {
  const settle = () => new Promise(done => setTimeout(done, 400));
  setSwitch(0b0101);                             await settle();
  readGlobal();                                  await settle();
  selectRegister(0x24); doRead();                await settle();
  selectRegister(0x25); doRead();                await settle();
  selectRegister(0x21);
  document.getElementById("val").value = "0a";
  doWrite();                                     await settle();
})()
JS
)" \
  --output "$DIR/screenshot.png"
