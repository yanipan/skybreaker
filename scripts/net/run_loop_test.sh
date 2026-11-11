#!/bin/bash
# Co-op loop test: one headless room server + two headless bots on this Mac.
#   scripts/net/run_loop_test.sh [sector] [duration_mul] [lag_ms] [loss] [port]
# Passes when the sector is cleared by both bots, every kill and every pickup
# grant is counted once (bot totals == server totals), and nobody logged a
# script error.
set -u
SECTOR=${1:-13}; MUL=${2:-0.8}; LAG=${3:-80}; LOSS=${4:-0.03}; PORT=${5:-24640}
G=${GODOT:-/Applications/Godot.app/Contents/MacOS/Godot}
L=$(mktemp -d)
"$G" --headless --path . res://scenes/net/ServerWorld.tscn -- --port=$PORT --sector=$SECTOR --sectors=1 --duration_mul=$MUL --seed=77 --lag=$LAG --loss=$LOSS > "$L/server.log" 2>&1 &
SPID=$!
sleep 2
"$G" --headless --path . res://scenes/net/NetBot.tscn -- --port=$PORT --name=botA --lag=$LAG --loss=$LOSS --dmg=6 > "$L/botA.log" 2>&1 &
APID=$!
"$G" --headless --path . res://scenes/net/NetBot.tscn -- --port=$PORT --name=botB --lag=$LAG --loss=$LOSS --dmg=6 > "$L/botB.log" 2>&1
wait $APID; sleep 2; kill $SPID 2>/dev/null
python3 - "$L" "$SECTOR" <<'PY'
import sys, json, re
L, sector = sys.argv[1], int(sys.argv[2])
srv = open(f"{L}/server.log").read()
m = re.search(r'game over won=\w+ stats=(\{.*?\}) out=(\d+) in=(\d+)', srv)
fails = []
def check(ok, what):
    print(("PASS  " if ok else "FAIL  ") + what)
    if not ok: fails.append(what)
check(m is not None, "server reached game over")
bots = []
for b in ("botA", "botB"):
    t = open(f"{L}/{b}.log").read()
    s = re.search(r'STATS (\{.*\})', t)
    check(s is not None, f"{b} finished with stats")
    if s: bots.append(json.loads(s.group(1)))
    check("SCRIPT ERROR" not in t, f"{b}: no script errors")
check("SCRIPT ERROR" not in srv, "server: no script errors")
if m and len(bots) == 2:
    st = json.loads(re.sub(r'(\w+):', r'\1:', m.group(1)))
    check(all(b["cleared"] == [sector] for b in bots), f"both bots saw sector {sector} cleared")
    check(st["kills"] > 0 and sum(b["my_kills"] for b in bots) == st["kills"], f"kills credited once each: {[b['my_kills'] for b in bots]} = {st['kills']}")
    check(sum(b["my_grants"] for b in bots) == st["grants"], f"pickups granted once each: {[b['my_grants'] for b in bots]} = {st['grants']}")
    check(all(b["spawns"] == st["spawns"] for b in bots), f"both bots got all {st['spawns']} spawns")
    check(all(b["shots"] == st["shots"] for b in bots), f"both bots flew all {st['shots']} enemy shots")
    print(f"traffic: server out {int(m.group(2))//1024} KB, in {int(m.group(3))//1024} KB; bots in {[b['bytes_in']//1024 for b in bots]} KB")
print(f"NetLoopTest: {'FAILED ' + str(len(fails)) if fails else 'all passed'}  (logs {L})")
sys.exit(1 if fails else 0)
PY
