#!/bin/sh
# Runs the demo sequence on a timer so you can film the keyboard with both hands free.
# Usage: scripts/demo.sh [image-or-gif]   (keyboard on USB, wired mode)
cd "$(dirname "$0")/.."
A=.build/release/aula
[ -x "$A" ] || swift build -c release --product aula >/dev/null
MEDIA="${1:-}"

say_step() { printf '\n\033[1m%s\033[0m\n' "$1"; }
countdown() { i=$1; while [ $i -gt 0 ]; do printf '  %d...\r' $i; sleep 1; i=$((i-1)); done; printf '        \r'; }

say_step "Resetting keyboard to a dull state (lights off, black screen)"
$A light off >/dev/null
$A screen --color 000000 >/dev/null
say_step "Start recording, then press Enter. You'll get 5 seconds to frame the shot."
read -r _
countdown 5

say_step "Sending to the screen"
if [ -n "$MEDIA" ]; then $A screen "$MEDIA" fill >/dev/null; else $A screen --color FF2D95 >/dev/null; fi
sleep 3

say_step "Rainbow keys"
$A keys --rainbow >/dev/null
sleep 3

say_step "Breath effect"
$A light breath 00E5FF --speed 3 >/dev/null
say_step "Done. Stop recording."
