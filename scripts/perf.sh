#!/usr/bin/env bash
# Measures Islet's CPU use in each island state (isolated config, own API port). Two states are
# measured while a client keeps reporting, which is how the app really runs; see `feeding`.
# Budgets: idle ≤ 0.5%, any compact state ≤ 1.5%.   Usage: scripts/perf.sh [seconds]
set -uo pipefail
cd "$(dirname "$0")/.."
SECS="${1:-10}"
T=$(mktemp -d)
mkdir -p "$T/cfg/islet"
echo '{"apiPort":47933,"pluginsEnabled":false}' > "$T/cfg/islet/config.json"
export ISLET_SUPPORT_DIR="$T/s" XDG_CONFIG_HOME="$T/cfg"
build/Islet.app/Contents/MacOS/Islet >/dev/null 2>&1 &
PID=$!
FEED=
trap 'kill $PID $FEED 2>/dev/null; rm -rf "$T"' EXIT
ctl() { build/Islet.app/Contents/MacOS/isletctl "$@" >/dev/null; }
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
        ctl set agent --source claude-code --title 'Claude · islet' --subtitle 'Running swift build' \
            --progress -1 --sneak false
        sleep 0.6
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
ctl rm agent; api POST /v1/media '{"title":"Perf","artist":"Bench","isPlaying":true,"duration":200,"elapsed":1}'
ctl open;                                          measure "expanded: now playing" 3
api DELETE /v1/media; ctl close;                   measure "idle again" 0.5
echo "RSS: $(( $(ps -o rss= -p $PID) / 1024 )) MB"
exit $FAIL
