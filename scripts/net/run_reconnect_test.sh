#!/bin/bash
# Co-op reconnect test: one headless room server + two headless bots, three runs.
#   scripts/net/run_reconnect_test.sh [port]
# 1. botA loses its link for 4 s mid-sector and comes back into the same seat.
# 2. botA never comes back: its seat expires, and when botB then goes down the run ends.
# 3. botA loses its link while the shared shop is open: the shop does not wait
#    for it, and it is back in the fight afterwards.
set -u
PORT=${1:-24660}
G=${GODOT:-/Applications/Godot.app/Contents/MacOS/Godot}
FAILS=0
run() {  # name sector server_args botA_args botB_args
  local L; L=$(mktemp -d)
  "$G" --headless --path . res://scenes/net/ServerWorld.tscn -- --port=$PORT --sector=$2 --sectors=1 --duration_mul=0.5 --seed=77 --lag=40 $3 > "$L/server.log" 2>&1 &
  local SPID=$!
  sleep 2
  "$G" --headless --path . res://scenes/net/NetBot.tscn -- --port=$PORT --name=botA --lag=40 --dmg=6 --timeout=240 $4 > "$L/botA.log" 2>&1 &
  local APID=$!
  "$G" --headless --path . res://scenes/net/NetBot.tscn -- --port=$PORT --name=botB --lag=40 --dmg=6 --timeout=240 $5 > "$L/botB.log" 2>&1
  wait $APID; sleep 2; kill $SPID 2>/dev/null
  python3 - "$L" "$1" "$2" <<'PY'
import sys, json, re
L, name, sector = sys.argv[1], sys.argv[2], int(sys.argv[3])
srv = open(f"{L}/server.log").read()
fails = []
def check(ok, what):
    print(("PASS  " if ok else "FAIL  ") + f"[{name}] " + what)
    if not ok: fails.append(what)
bots = {}
for b in ("botA", "botB"):
    t = open(f"{L}/{b}.log").read()
    s = re.search(r'STATS (\{.*\})', t)
    check(s is not None, f"{b} finished with stats")
    bots[b] = json.loads(s.group(1)) if s else {}
    check("SCRIPT ERROR" not in t, f"{b}: no script errors")
check("SCRIPT ERROR" not in srv, "server: no script errors")
m = re.search(r'game over won=(\w+) stats=(\{.*?\}) out=', srv)
check(m is not None, "server reached game over")
st = json.loads(re.sub(r'(\w+):', r'\1:', m.group(2))) if m else {}
A, B = bots["botA"], bots["botB"]
if name == "return":
    check("lost its link, seat kept" in srv and "resumed its seat" in srv, "server kept the seat and gave it back")
    check(st.get("resumes") == 1 and A.get("reconnects") == 1, f"one reconnect (server {st.get('resumes')}, botA {A.get('reconnects')})")
    check(A.get("peer") in (1, 2) and A.get("link_failed") is False, f"botA is still the same player (peer {A.get('peer')})")
    check(B.get("links") == [0, 1], f"botB was told its partner dropped and came back ({B.get('links')})")
    check(A.get("cleared") == [sector] and B.get("cleared") == [sector], f"both finished sector {sector} ({A.get('cleared')}, {B.get('cleared')})")
    check(A.get("my_kills", 0) > 0 and A.get("my_kills", 0) + B.get("my_kills", 0) == st.get("kills"), f"kills still credited once each ({A.get('my_kills')} + {B.get('my_kills')} = {st.get('kills')})")
    check("gone for good" not in srv, "seat did not expire")
elif name == "expire":
    check("did not come back, gone for good" in srv, "the seat expired")
    check(st.get("resumes") == 0, "nobody resumed")
    check(B.get("links") == [0, 2], f"botB was told: dropped, then gone ({B.get('links')})")
    check(m is not None and m.group(1) == "false" and B.get("won") is False, "run over once the last ship went down")
    check(st.get("downs") == 1 and "is down" in srv, "botB went down after the seat expired, no pod wait")
    check(A.get("link_failed") is True, "botA gave up and ended its run")
elif name == "shop":
    check(st.get("shops") == 1 and srv.count("world frozen") == 1 and srv.count("world running again") == 1, "one shop visit, frozen and released once")
    check(st.get("resumes") == 1 and A.get("reconnects") == 1, f"botA came back ({A.get('reconnects')})")
    check(srv.index("shop closed") < srv.index("resumed its seat"), "the shop closed without waiting for the lost phone")
    check(A.get("cleared") == [sector] and B.get("cleared") == [sector], f"both finished sector {sector}")
print(f"[{name}] logs {L}")
sys.exit(1 if fails else 0)
PY
  [ $? -ne 0 ] && FAILS=$((FAILS+1))
}
run return 2 "" "--drop_at=8 --drop_secs=4" ""
run expire 2 "--reconnect_secs=5" "--drop_at=5 --drop_secs=999 --give_up=9" "--die_at=14 --no_rescue"
run shop 3 "" "--drop_in_shop --drop_secs=3 --shop_secs=1" "--shop_secs=1"
echo "ReconnectTest: $([ $FAILS -eq 0 ] && echo 'all passed' || echo "FAILED $FAILS run(s)")"
exit $FAILS
