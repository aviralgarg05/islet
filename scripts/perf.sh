#!/usr/bin/env bash
# Measures Casement's CPU use in each island state (isolated config, own API port). Two states are
# measured while a client keeps reporting, which is how the app really runs; see `feeding`.
# Budgets: idle ≤ 0.5%, any compact state ≤ 1.5%.   Usage: scripts/perf.sh [seconds]
set -uo pipefail
cd "$(dirname "$0")/.."
SECS="${1:-10}"
T=$(mktemp -d)
mkdir -p "$T/cfg/casement"
echo '{"apiPort":47933,"pluginsEnabled":false}' > "$T/cfg/casement/config.json"
export CASEMENT_SUPPORT_DIR="$T/s" XDG_CONFIG_HOME="$T/cfg"
build/Casement.app/Contents/MacOS/Casement >/dev/null 2>&1 &
PID=$!
FEED=
trap 'kill $PID $FEED 2>/dev/null; rm -rf "$T"' EXIT
ctl() { build/Casement.app/Contents/MacOS/casementctl "$@" >/dev/null; }
for _ in $(seq 50); do [ -f "$T/s/api.json" ] && break; sleep 0.2; done
TOKEN=$(python3 -c "import json;print(json.load(open('$T/s/api.json'))['token'])")
api() { curl -s -o /dev/null -X "$1" -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' ${3:+-d "$3"} "http://127.0.0.1:47933$2"; }
secs() { ps -o time= -p "$PID" | awk -F: '{ s=0; for (i=1;i<=NF;i++) s=s*60+$i; print s }'; }
FAIL=0
measure() { # name budget%
    # Let the change settle first: a transition (a peek, the island opening) is a moment's work,
    # not the state's cost.
    sleep 6
    local a b pct
    a=$(secs); sleep "$SECS"; b=$(secs)
    pct=$(python3 -c "print(round(($b-$a)/$SECS*100, 2))")
    local ok; ok=$(python3 -c "print('ok' if $pct <= $2 else 'OVER')")
    [ "$ok" = ok ] || FAIL=1
    printf '  %-32s %6s%%   (budget %s%%) %s\n' "$1" "$pct" "$2" "$ok"
}
# A state measured while a client keeps reporting, which is how the app really runs: the
# MediaRemote helper reports a playing track about once a second and a coding agent's hooks fire a
# couple of times a second. None of it says anything new, so none of it should cost anything; a
# redraw per report is what put the installed build over this budget while a single static
# snapshot stayed inside it. The feed runs through the settle and the whole measurement.
feeding() { # name budget% feeder
    "$3" & FEED=$!
    measure "$1" "$2"
    kill $FEED 2>/dev/null
    wait $FEED 2>/dev/null
    FEED=
}
# A playing track whose position advances with the clock, as the helper reports it.
media_feed() {
    local elapsed=1
    while :; do
        api POST /v1/media "{\"title\":\"Perf\",\"artist\":\"Bench\",\"isPlaying\":true,\"duration\":600,\"elapsed\":$elapsed}"
        elapsed=$((elapsed + 1))
        sleep 1
    done
}
# An agent's hook posting the same activity again, as Claude Code's hooks do between tool calls.
activity_feed() {
    while :; do
        ctl set agent --source claude-code --title 'Claude · casement' --subtitle 'Running swift build' \
            --progress -1 --sneak false
        sleep 0.6
    done
}
# A delivery or a ride reporting the same arrival time again, which is what a mirrored Live
# Activity, a ride and a timer all look like. The end doesn't move, so the island has nothing to
# draw: the track's span used to be worked out a float ulp above the span already in hand, and
# every report then read as a change and had the island sort and draw again.
countdown_feed() {
    local ends=$(( $(date +%s) + 600 ))
    while :; do
        api POST /v1/activities \
            "{\"id\":\"eta\",\"source\":\"perf\",\"title\":\"Order\",\"subtitle\":\"Arriving\",\"endsAt\":$ends,\"sneak\":false}"
        sleep 1
    done
}
# Launch work (loading, the first drawing of blurs and glass) isn't the idle cost either.
sleep 10
echo "CPU over ${SECS}s per state:"
measure "idle" 0.5
ctl timer 5m --title Tea;                          measure "compact: live countdown" 1.5
ctl clear --source timer; ctl set p --title Progress --progress 0.4 --sneak false; measure "compact: static progress" 1.5
ctl rm p; ctl set s --title Spinner --progress -1 --sneak false; measure "compact: indeterminate spinner" 1.5
ctl rm s; api POST /v1/media '{"title":"Perf","artist":"Bench","isPlaying":true,"duration":200,"elapsed":1}'; measure "compact: music playing" 1.5
api DELETE /v1/media;                              feeding "compact: music reported each second" 1.5 media_feed
api DELETE /v1/media;                              feeding "compact: agent hooks reporting" 1.5 activity_feed
ctl rm agent;                                      feeding "compact: same countdown each second" 1.5 countdown_feed
ctl rm eta; api POST /v1/media '{"title":"Perf","artist":"Bench","isPlaying":true,"duration":200,"elapsed":1}'
ctl open;                                          measure "expanded: now playing" 3
api DELETE /v1/media; ctl close;                   measure "idle again" 0.5
echo "RSS: $(( $(ps -o rss= -p $PID) / 1024 )) MB"
exit $FAIL
