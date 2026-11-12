#!/bin/bash
# AI partner test: a room server with --bots=1 and ONE headless bot as the human.
#   scripts/net/run_ai_test.sh [port]
# 1. play:   two sectors with a shop: the AI fights, shops, the run goes on.
# 2. rescue: the human goes down, the AI flies to the pod and brings it back.
# 3. frail:  the AI goes down at its first hit, the human rescues it.
# 4. alone:  the human disappears for good: the AI does not play on by itself.
set -u
PORT=${1:-24720}
G=${GODOT:-/Applications/Godot.app/Contents/MacOS/Godot}
FAILS=0
run() {  # name sector sectors server_args human_args
  local L; L=$(mktemp -d)
  "$G" --headless --path . res://scenes/net/ServerWorld.tscn -- --port=$PORT --sector=$2 --sectors=$3 --duration_mul=0.5 --seed=41 --bots=1 $4 > "$L/server.log" 2>&1 &
  local SPID=$!
  sleep 2
  "$G" --headless --path . res://scenes/net/NetBot.tscn -- --port=$PORT --name=human --dmg=3 --timeout=300 $5 > "$L/human.log" 2>&1
  sleep 2; kill $SPID 2>/dev/null
  python3 - "$L" "$1" <<'PY'
import sys, json, re
L, name = sys.argv[1], sys.argv[2]
srv = open(f"{L}/server.log").read(); hum = open(f"{L}/human.log").read()
fails = []
def check(ok, what):
    print(("PASS  " if ok else "FAIL  ") + f"[{name}] " + what)
    if not ok: fails.append(what)
check("SCRIPT ERROR" not in srv and "SCRIPT ERROR" not in hum, "no script errors")
m = re.search(r'game over won=(\w+) stats=(\{.*?\}) out=', srv)
check(m is not None, "server reached game over")
st = json.loads(m.group(2)) if m else {}
a = re.search(r'ServerWorld: AI (.+?) score (\d+) level (\d+) money (-?\d+) lives (-?\d+) (\{.*\})', srv)
check(a is not None and "took seat" in srv, "an AI partner took a seat")
ai = json.loads(a.group(6)) if a else {}
s = re.search(r'STATS (\{.*\})', hum)
H = json.loads(s.group(1)) if s else {}
check(s is not None, "the human finished with stats")
if name == "play":
    check(H.get("cleared") == [2, 3], f"both sectors cleared ({H.get('cleared')})")
    check(ai.get("kills", 0) >= 5 and int(a.group(2)) > 0, f"the AI made kills and scored ({ai.get('kills')}, {a.group(2)})")
    check(H.get("my_kills", 0) + ai.get("kills", 0) == st.get("kills"), f"every kill credited once ({H.get('my_kills')} + {ai.get('kills')} = {st.get('kills')})")
    check(ai.get("pickups", 0) >= 5 and H.get("my_grants", 0) + ai.get("pickups", 0) == st.get("grants"), f"the AI collected pickups, each granted once ({H.get('my_grants')} + {ai.get('pickups')} = {st.get('grants')})")
    check(ai.get("bought", 0) >= 1, f"the AI bought something with its own money (bought {ai.get('bought')}, weapon level {a.group(3)})")
    check(ai.get("swaps", 0) >= 2, f"the AI switched weapons during the run ({ai.get('swaps')} times)")
    check(ai.get("overheats", 0) >= 2, f"the AI ran out of weapon energy and had to hold fire ({ai.get('overheats')} times)")
    check(H.get("shared_money", 0) > 0, f"money the AI picked up was shared with the human (+{H.get('shared_money')})")
    check(st.get("shops") == 1 and srv.count("world running again") == 1, "one shared shop visit, the AI left it")
elif name == "rescue":
    check(st.get("downs") == 1 and st.get("revives") == 1 and ai.get("rescues") == 1, f"the AI rescued the human (downs {st.get('downs')}, revives {st.get('revives')}, AI rescues {ai.get('rescues')})")
    check(H.get("revived") == 1 and H.get("cleared") == [2], "the human was revived and finished the sector")
elif name == "frail":
    check(st.get("downs", 0) >= 1 and ai.get("deaths", 0) >= 1, f"the AI went down ({st.get('downs')})")
    check(st.get("revives", 0) >= 1 and H.get("rescues", 0) >= 1, f"the human rescued it ({st.get('revives')})")
    check(H.get("cleared") == [5], "sector finished")
elif name == "alone":
    check("gone for good" in srv, "the human's seat expired")
    check(m is not None and m.group(1) == "false" and st.get("sectors") == 0, "the run ended at once, the AI did not play on alone")
print(f"[{name}] logs {L}")
sys.exit(1 if fails else 0)
PY
  [ $? -ne 0 ] && FAILS=$((FAILS+1))
}
run play 2 2 "--duration_mul=0.8" "--shop_secs=2 --no_pickups"
run rescue 2 1 "" "--die_at=6"
run frail 5 1 "--bot_frail" ""
run alone 2 1 "--reconnect_secs=3" "--drop_at=5 --drop_secs=999 --give_up=5"
echo "AiTest: $([ $FAILS -eq 0 ] && echo 'all passed' || echo "FAILED $FAILS run(s)")"
exit $FAILS
