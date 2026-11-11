#!/bin/bash
# Co-op loop test: one headless room server + two headless bots on this Mac.
#   scripts/net/run_loop_test.sh [sector] [duration_mul] [lag_ms] [loss] [port] [expected_shops]
# expected_shops: when given, the run must have exactly that many shared shop
# visits (a sector right before a boss sector always has one starbase).
# Environment: EXTRA_S / EXTRA_A / EXTRA_B = extra user args for the server and
# each bot (e.g. EXTRA_A="--die_at=12"); EXPECT_REVIVES=n; EXPECT_CLEARED=0 when
# the run is meant to end before the sector does (both ships down).
# Passes when the sector is cleared by both bots, every kill and every pickup
# grant is counted once (bot totals == server totals), and nobody logged a
# script error.
set -u
SECTOR=${1:-13}; MUL=${2:-0.8}; LAG=${3:-80}; LOSS=${4:-0.03}; PORT=${5:-24640}; SHOPS=${6:-}
G=${GODOT:-/Applications/Godot.app/Contents/MacOS/Godot}
L=$(mktemp -d)
"$G" --headless --path . res://scenes/net/ServerWorld.tscn -- --port=$PORT --sector=$SECTOR --sectors=1 --duration_mul=$MUL --seed=77 --lag=$LAG --loss=$LOSS ${EXTRA_S:-} > "$L/server.log" 2>&1 &
SPID=$!
sleep 2
"$G" --headless --path . res://scenes/net/NetBot.tscn -- --port=$PORT --name=botA --lag=$LAG --loss=$LOSS --dmg=6 ${EXTRA_A:-} > "$L/botA.log" 2>&1 &
APID=$!
"$G" --headless --path . res://scenes/net/NetBot.tscn -- --port=$PORT --name=botB --lag=$LAG --loss=$LOSS --dmg=6 ${EXTRA_B:-} > "$L/botB.log" 2>&1
wait $APID; sleep 2; kill $SPID 2>/dev/null
python3 - "$L" "$SECTOR" "$SHOPS" "${EXPECT_REVIVES:-}" "${EXPECT_CLEARED:-1}" <<'PY'
import sys, json, re
L, sector = sys.argv[1], int(sys.argv[2])
want_shops = sys.argv[3] if len(sys.argv) > 3 else ""
want_revives = sys.argv[4] if len(sys.argv) > 4 else ""
want_cleared = (sys.argv[5] if len(sys.argv) > 5 else "1") != "0"
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
    if want_cleared:
        check(all(b["cleared"] == [sector] for b in bots), f"both bots saw sector {sector} cleared")
    else:
        check(all(b["cleared"] == [] for b in bots) and st["sectors"] == 0, "run ended before the sector did (nobody left flying)")
        check(all(b["won"] is False for b in bots), "both bots were told the run is over (lost)")
    if want_revives != "":
        n = int(want_revives)
        check(st.get("revives", -1) == n, f"server recorded {n} rescue(s) ({st.get('revives')}), downs {st.get('downs')}")
        check(sum(b.get("revived", 0) for b in bots) == n and sum(b.get("rescues", 0) for b in bots) == n, f"bots: revived {[b.get('revived') for b in bots]}, rescued {[b.get('rescues') for b in bots]}")
    check(st["kills"] > 0 and sum(b["my_kills"] for b in bots) == st["kills"], f"kills credited once each: {[b['my_kills'] for b in bots]} = {st['kills']}")
    check(sum(b["my_grants"] for b in bots) == st["grants"], f"pickups granted once each: {[b['my_grants'] for b in bots]} = {st['grants']}")
    check(all(b["spawns"] == st["spawns"] for b in bots), f"both bots got all {st['spawns']} spawns")
    # Every enemy shot the server sent is either flown or still waiting for the
    # phone's render clock (the last ~0.2 s before game over). None may vanish.
    pend = [b.get("pending_shots", 0) for b in bots]
    check(all(b["shots"] + b.get("pending_shots", 0) == st["shots"] for b in bots), f"no enemy shot lost: {st['shots']} sent, flown {[b['shots'] for b in bots]}, still queued at game over {pend}")
    check(all(x <= 12 for x in pend), f"at most a few shots still queued at the end ({pend})")
    if want_shops != "":
        n = int(want_shops)
        check(st.get("shops", -1) == n, f"server ran {n} shared shop visit(s) ({st.get('shops')})")
        check(all(b.get("shops", -1) == n for b in bots), f"both bots were in the shop {n} time(s) ({[b.get('shops') for b in bots]})")
        check(srv.count("world frozen") == n and srv.count("world running again") == n, f"world frozen and released {n} time(s)")
    print(f"traffic: server out {int(m.group(2))//1024} KB, in {int(m.group(3))//1024} KB; bots in {[b['bytes_in']//1024 for b in bots]} KB")
print(f"NetLoopTest: {'FAILED ' + str(len(fails)) if fails else 'all passed'}  (logs {L})")
sys.exit(1 if fails else 0)
PY
