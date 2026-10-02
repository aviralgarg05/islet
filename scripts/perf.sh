#!/usr/bin/env bash
# Measures Islet's CPU use in each island state (isolated config, own API port).
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
trap 'kill $PID 2>/dev/null; rm -rf "$T"' EXIT
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
# Launch work (loading, the first drawing of blurs and glass) isn't the idle cost either.
sleep 10
echo "CPU over ${SECS}s per state:"
measure "idle" 0.5
ctl timer 5m --title Tea;                          measure "compact: live countdown" 1.5
ctl clear --source timer; ctl set p --title Progress --progress 0.4 --sneak false; measure "compact: static progress" 1.5
ctl rm p; ctl set s --title Spinner --progress -1 --sneak false; measure "compact: indeterminate spinner" 1.5
ctl rm s; api POST /v1/media '{"title":"Perf","artist":"Bench","isPlaying":true,"duration":200,"elapsed":1}'; measure "compact: music playing" 1.5
ctl open;                                          measure "expanded: now playing" 3
api DELETE /v1/media; ctl close;                   measure "idle again" 0.5
echo "RSS: $(( $(ps -o rss= -p $PID) / 1024 )) MB"
exit $FAIL
