#!/bin/sh
# Renders the App Store frames from build/app-store/render with headless Chrome.
set -eu
cd "$(dirname "$0")/render"
port=$(python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1",0)); print(s.getsockname()[1])')
python3 -m http.server "$port" --bind 127.0.0.1 >/dev/null 2>&1 &
server=$!
trap 'kill $server' EXIT
sleep 1
out=../out33; mkdir -p "$out"
for id in "$@"; do
  case "$id" in *ipad*) size=2064,2752;; *) size=1320,2868;; esac
  "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" --headless=new --disable-gpu --hide-scrollbars \
    --force-device-scale-factor=1 --window-size=$size --virtual-time-budget=4000 \
    --screenshot="$out/$id.png" "http://127.0.0.1:$port/index.html?frame=$id" >/dev/null 2>&1
  echo "$out/$id.png"
done
