extends Node
class_name LobbyApi
## Client of the co-op lobby service (server/lobby/lobby.js): room codes and
## Play-now matching. Requests are signed like the leaderboard ones
## (X-SB-Ts + X-SB-Sig = HMAC-SHA256(key, ts + "." + body)).
## Returns {} when the service cannot be reached.

const KEYS := preload("res://config/online_keys.gd")
## Where the lobby lives. Empty until the service is on a public server
## (phase 5); debug builds fall back to a lobby on this machine.
const PROD_URL: String = ""
const DEV_URL: String = "http://127.0.0.1:24600"
const TIMEOUT: float = 6.0
## Set from the command line (--lobby=http://host:port) on desktop.
static var url_override: String = ""
## DEV: two game windows on one Mac are the same installation and share one
## player id, and the lobby (rightly) never matches a player with themselves.
## --pid=<uuid> on the command line gives a window its own id. Debug builds only.
static var player_id_override: String = ""


static func base_url() -> String:
	if url_override != "":
		return url_override
	if PROD_URL != "":
		return PROD_URL
	return DEV_URL if OS.is_debug_build() else ""


## Co-op is offered only when there is a lobby to talk to.
static func available() -> bool:
	return base_url() != ""


static func _sign(ts: int, body: String) -> String:
	var h := HMACContext.new()
	h.start(HashingContext.HASH_SHA256, KEYS.SIG_KEY.to_utf8_buffer())
	h.update((str(ts) + "." + body).to_utf8_buffer())
	return h.finish().hex_encode()


func call_api(path: String, body: Dictionary) -> Dictionary:
	var base: String = base_url()
	if base == "":
		return {}
	body["proto"] = Net.PROTO
	body["player_id"] = player_id_override if (player_id_override != "" and OS.is_debug_build()) else Telemetry.player_id
	var raw: String = JSON.stringify(body)
	var ts: int = int(Time.get_unix_time_from_system())
	var http := HTTPRequest.new()
	http.timeout = TIMEOUT
	add_child(http)
	var err: int = http.request(base + path, [
		"Content-Type: application/json",
		"X-SB-Ts: " + str(ts),
		"X-SB-Sig: " + _sign(ts, raw),
	], HTTPClient.METHOD_POST, raw)
	if err != OK:
		http.queue_free()
		return {}
	var res: Array = await http.request_completed
	http.queue_free()
	if res[0] != HTTPRequest.RESULT_SUCCESS:
		return {}
	var j: Variant = JSON.parse_string((res[3] as PackedByteArray).get_string_from_utf8())
	return j if j is Dictionary else {}
