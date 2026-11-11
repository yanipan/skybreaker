extends "res://scripts/OnlineUI.gd"
## CO-OP lobby screens (docs/MULTIPLAYER_PLAN.md, "Finding a partner"), opened
## from the CO-OP button on the start screen. Same look and helpers as the
## leaderboard screens (this script extends OnlineUI).
##
##   PLAY NOW            -> the lobby service looks for another pilot on the
##                          same game version for about 10 s
##   PLAY WITH A FRIEND  -> a room with a 6-character code and a QR to share
##   JOIN WITH CODE      -> type the friend's code
## In a room: both names, then STARTING IN 3-2-1, then the normal game scene.
## Leaving any of these screens leaves the room and puts the solo run back.

## The invite page (docs/join/index.html, served by GitHub Pages with the
## privacy policy). The code travels as ?c=ABC123.
const INVITE_URL: String = "https://yanipan.github.io/skybreaker/join/?c="
const MAIN_SCENE: String = "res://scenes/main/Main.tscn"
const CONNECT_SECS: float = 8.0
const PARTNER_WAIT_SECS: float = 15.0   ## A matched room whose partner never shows up
const START_COUNT: int = 3
const COL_VIOLET := Color(0.80, 0.62, 1.00)

var api: LobbyApi
## Bumped on every screen change: an await that comes back to an older number
## belongs to a screen the player already left, and stops.
var _gen: int = 0
var _code: String = ""
var _in_room: bool = false
var _starting: bool = false
var _matched_room: bool = false
var _names: Label = null
## (_status, the one-line status label, is inherited from OnlineUI.)
## DEV (debug builds): "friend" / "join" / "quick" run that flow by themselves;
## "friend" writes its code to user://coop_dev_code.txt and "join" reads it.
var dev_auto_action: String = ""


func _ready() -> void:
	super._ready()
	layer = 31
	api = LobbyApi.new()
	add_child(api)


func _screen(title: String) -> VBoxContainer:
	_gen += 1
	_stop_camera()
	_names = null
	_status = null
	return _open(title)


# --- Menu ---

func open_menu() -> void:
	_leave_room()
	var box := _screen("CO-OP")
	box.add_child(_label("Fly the whole run with a partner.\nYour solo run is kept as it is.", _font(), COL_MUTED))
	box.add_child(_spacer(_vh * 0.02))
	box.add_child(_button("PLAY NOW", COL_GREEN, _play_now))
	box.add_child(_button("PLAY WITH A FRIEND", COL_CYAN, _play_friend))
	box.add_child(_button("JOIN WITH CODE", COL_GOLD, _join_screen))
	box.add_child(_spacer(_vh * 0.02))
	box.add_child(_button("BACK", COL_RED, close_lobby))


func close_lobby() -> void:
	_gen += 1
	_leave_room()
	close()


func _leave_room() -> void:
	_starting = false
	_matched_room = false
	_code = ""
	if _in_room or Net.is_client():
		Net.leave_coop()   # also puts the solo run, money and lives back
	_in_room = false


func _error(text: String) -> void:
	_leave_room()
	var box := _screen("CO-OP")
	box.add_child(_spacer(_vh * 0.04))
	box.add_child(_label(text, _font() * 1.2, COL_RED))
	box.add_child(_spacer(_vh * 0.04))
	box.add_child(_button("BACK", COL_CYAN, open_menu))


static func _api_error(r: Dictionary) -> String:
	if r.is_empty():
		return "Could not reach the co-op service.\nCheck your connection."
	match str(r.get("error", "")):
		"not_found": return "No room with that code."
		"started": return "That run has already started."
		"version": return "Update the game to play co-op\nwith this pilot."
		"busy": return "The co-op servers are full right now.\nTry again in a minute."
		"rate_limited": return "Too many tries. Wait a minute."
	return "Something went wrong. Try again."


# --- Play with a friend ---

func _play_friend() -> void:
	_leave_room()
	var box := _screen("PLAY WITH A FRIEND")
	var gen: int = _gen
	box.add_child(_spacer(_vh * 0.05))
	box.add_child(_label("CREATING YOUR ROOM...", _font() * 1.2, COL_MUTED))
	box.add_child(_spacer(_vh * 0.05))
	box.add_child(_button("CANCEL", COL_RED, open_menu))
	var r: Dictionary = await api.call_api("/v1/room/create", {})
	if gen != _gen:
		return
	if not r.get("ok", false):
		_error(_api_error(r))
		return
	_code = str(r.get("code", ""))
	_friend_screen()
	_connect(str(r.get("host", "")), int(r.get("port", 0)))


func _friend_screen() -> void:
	var code: String = _code
	var box := _screen("PLAY WITH A FRIEND")
	box.add_child(_label("YOUR ROOM CODE", _font(), COL_MUTED))
	var code_label := _label(code.left(3) + " " + code.substr(3), _font() * 3.0, COL_GOLD, Fonts.HEADLINE)
	code_label.name = "RoomCode"
	box.add_child(code_label)
	var matrix: Array = QRCode.encode(INVITE_URL + code)
	if not matrix.is_empty():
		var side: float = minf(_vw * 0.46, _vh * 0.26)
		var tex := TextureRect.new()
		tex.name = "InviteQR"
		tex.texture = ImageTexture.create_from_image(QRCode.to_image(matrix, 6, 4))
		tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tex.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		tex.custom_minimum_size = Vector2(side, side)
		# Branded: the code itself stays plain black on white (it has to scan
		# from any phone), the frame and caption carry the game's look.
		var card := PanelContainer.new()
		card.name = "InviteCard"
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(1, 1, 1)
		sb.border_color = COL_GOLD
		sb.set_border_width_all(maxi(3, int(side * 0.022)))
		sb.set_corner_radius_all(int(side * 0.06))
		sb.set_content_margin_all(side * 0.03)
		card.add_theme_stylebox_override("panel", sb)
		card.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		var inner := VBoxContainer.new()
		inner.add_theme_constant_override("separation", 0)
		inner.add_child(tex)
		var cap := _label("SKYBREAKER CO-OP", _font() * 0.75, Color(0.10, 0.12, 0.20), Fonts.HEADLINE)
		inner.add_child(cap)
		card.add_child(inner)
		box.add_child(card)
	box.add_child(_label("Your friend scans this with the phone camera,\nor opens CO-OP > JOIN WITH CODE and types the code.", _font() * 0.9, COL_MUTED))
	_names = _label("", _font() * 1.2, COL_CYAN)
	box.add_child(_names)
	_status = _label("WAITING FOR YOUR FRIEND...", _font(), COL_GREEN)
	box.add_child(_status)
	var copy := _button("COPY INVITE", COL_GOLD, func() -> void:
		DisplayServer.clipboard_set("Join my Skybreaker co-op run! Room code: %s  %s%s" % [code, INVITE_URL, code])
		if _status != null and is_instance_valid(_status) and not _starting:
			_status.text = "INVITE COPIED. SEND IT TO YOUR FRIEND!")
	var cancel := _button("CANCEL", COL_RED, open_menu)
	box.add_child(_row([copy, cancel]))
	if dev_auto_action == "friend":
		var f := FileAccess.open("user://coop_dev_code.txt", FileAccess.WRITE)
		if f != null:
			f.store_string(code)


# --- Join with a code ---

func _join_screen() -> void:
	_leave_room()
	var box := _screen("JOIN WITH CODE")
	box.add_child(_label("Type the 6-character code\nyour friend sees on their screen.", _font(), COL_MUTED))
	var edit := _line_edit("ROOM CODE", 7)
	edit.name = "CodeEdit"
	box.add_child(edit)
	var msg := _label("", _font(), COL_RED)
	box.add_child(msg)
	var go_join := func() -> void:
		var code: String = edit.text.to_upper().replace(" ", "").replace("-", "")
		if code.length() != 6:
			msg.text = "The code has 6 characters."
			return
		_join(code)
	edit.text_submitted.connect(func(_t: String) -> void: go_join.call())
	box.add_child(_button("JOIN", COL_GREEN, go_join))
	if camera_available():
		box.add_child(_button("SCAN QR CODE", COL_CYAN, _scan_screen))
	box.add_child(_button("BACK", COL_RED, open_menu))
	if not camera_available():
		edit.grab_focus.call_deferred()   # on a phone the keyboard would cover SCAN


# --- Scan a friend's QR with this phone's camera ---
# NOT YET TRIED ON A REAL PHONE (11/11). The decoder (QRScan) is tested with
# synthetic camera frames; the camera plumbing below (permission, feed
# format, CameraTexture.get_image, preview orientation) needs a device.

const SCAN_EVERY: float = 0.25
## DEV: --scan on the command line offers the scanner on desktop too.
static var scan_on_desktop: bool = false
var _cam_feed: CameraFeed = null


static func camera_available() -> bool:
	return OS.has_feature("mobile") or scan_on_desktop


func _stop_camera() -> void:
	if _cam_feed != null:
		_cam_feed.feed_is_active = false
	_cam_feed = null


func _scan_screen() -> void:
	_leave_room()
	var box := _screen("SCAN QR CODE")
	var gen: int = _gen
	box.add_child(_label("Point the camera at the QR code\non your friend's screen.", _font(), COL_MUTED))
	var side: float = minf(_vw * 0.78, _vh * 0.42)
	var view := TextureRect.new()
	view.name = "ScanView"
	view.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	view.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	view.custom_minimum_size = Vector2(side, side)
	view.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	view.clip_contents = true
	# The viewfinder is drawn from brightness only, tinted like the HUD: it
	# works for every camera format and is all the decoder needs anyway.
	var sh := Shader.new()
	sh.code = "shader_type canvas_item;\nuniform bool y_only = false;\nvoid fragment() {\n\tvec4 c = texture(TEXTURE, UV);\n\tfloat l = y_only ? c.r : dot(c.rgb, vec3(0.299, 0.587, 0.114));\n\tCOLOR = vec4(l * 0.55, l * 0.95, l, 1.0);\n}\n"
	var mat := ShaderMaterial.new()
	mat.shader = sh
	view.material = mat
	var frame := ScanFrame.new()
	frame.set_anchors_preset(Control.PRESET_FULL_RECT)
	view.add_child(frame)
	box.add_child(view)
	_status = _label("STARTING THE CAMERA...", _font(), COL_GREEN)
	box.add_child(_status)
	box.add_child(_button("TYPE THE CODE INSTEAD", COL_GOLD, _join_screen))
	box.add_child(_button("BACK", COL_RED, open_menu))
	if OS.get_name() == "Android" and not ("android.permission.CAMERA" in OS.get_granted_permissions()):
		OS.request_permission("android.permission.CAMERA")
		var waited: float = 0.0
		while not ("android.permission.CAMERA" in OS.get_granted_permissions()) and waited < 30.0:
			await get_tree().create_timer(0.5).timeout
			waited += 0.5
			if gen != _gen:
				return
	if "monitoring_feeds" in CameraServer:
		CameraServer.set("monitoring_feeds", true)   # Godot 4.5+: feeds are listed only while monitoring
	await get_tree().create_timer(0.6).timeout
	if gen != _gen:
		return
	var feed: CameraFeed = null
	for f in CameraServer.feeds():
		if feed == null or (f as CameraFeed).get_position() == CameraFeed.FEED_BACK:
			feed = f
	if feed == null:
		_status.text = "NO CAMERA. TYPE THE CODE INSTEAD."
		_status.add_theme_color_override("font_color", COL_RED)
		return
	# Android lists formats and needs one chosen; take the one nearest 640x480.
	if feed.has_method("get_formats") and feed.has_method("set_format"):
		var formats: Array = feed.get_formats()
		var pick: int = -1
		var best: float = INF
		for i in formats.size():
			var fm: Dictionary = formats[i]
			var d: float = absf(float(fm.get("width", 0)) - 640.0) + absf(float(fm.get("height", 0)) - 480.0)
			if d < best:
				best = d
				pick = i
		if pick >= 0:
			feed.set_format(pick, {})
	feed.feed_is_active = true
	_cam_feed = feed
	var tex := CameraTexture.new()
	tex.camera_feed_id = feed.get_id()
	var y_only: bool = feed.get_datatype() == CameraFeed.FEED_YCBCR_SEP
	tex.which_feed = CameraServer.FEED_Y_IMAGE if y_only else CameraServer.FEED_RGBA_IMAGE
	mat.set_shader_parameter("y_only", y_only)
	view.texture = tex
	_status.text = "LOOKING FOR A CODE..."
	while gen == _gen:
		await get_tree().create_timer(SCAN_EVERY).timeout
		if gen != _gen:
			return
		var img: Image = tex.get_image()
		if img == null or img.is_empty():
			continue
		var code: String = QRScan.room_code(QRScan.decode_image(img))
		if code != "":
			Input.vibrate_handheld(60)
			_join(code)   # opens a new screen, which stops the camera
			return


## Gold corner brackets and the game's name over the viewfinder.
class ScanFrame extends Control:
	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var col := Color(1.0, 0.82, 0.29)
		var m: float = size.x * 0.12
		var l: float = size.x * 0.16
		var w: float = maxf(3.0, size.x * 0.012)
		for c in [Vector2(m, m), Vector2(size.x - m, m), Vector2(m, size.y - m), Vector2(size.x - m, size.y - m)]:
			var dx: float = l if c.x < size.x * 0.5 else -l
			var dy: float = l if c.y < size.y * 0.5 else -l
			draw_line(c, c + Vector2(dx, 0), col, w)
			draw_line(c, c + Vector2(0, dy), col, w)
		var f: Font = Fonts.HEADLINE
		var fs: int = int(size.x * 0.055)
		draw_string(f, Vector2(0, size.y - m * 0.35), "SKYBREAKER CO-OP", HORIZONTAL_ALIGNMENT_CENTER, size.x, fs, Color(col, 0.9))


func _join(code: String) -> void:
	_room_screen("JOINING ROOM", "FINDING ROOM %s..." % code)
	var gen: int = _gen
	var r: Dictionary = await api.call_api("/v1/room/join", {"code": code})
	if gen != _gen:
		return
	if not r.get("ok", false):
		_error(_api_error(r))
		return
	_code = code
	_connect(str(r.get("host", "")), int(r.get("port", 0)))


# --- Play now ---

func _play_now() -> void:
	_leave_room()
	var box := _screen("PLAY NOW")
	var gen: int = _gen
	box.add_child(_spacer(_vh * 0.05))
	_status = _label("SEARCHING FOR A PILOT", _font() * 1.3, COL_GREEN)
	box.add_child(_status)
	box.add_child(_spacer(_vh * 0.05))
	box.add_child(_button("CANCEL", COL_RED, _cancel_quick))
	var dots: int = 0
	while true:
		var r: Dictionary = await api.call_api("/v1/quick", {})
		if gen != _gen:
			return
		if r.is_empty() or not r.get("ok", false):
			_error(_api_error(r))
			return
		if r.get("matched", false):
			_matched_room = true
			_room_screen("PILOT FOUND", "JOINING...")
			_connect(str(r.get("host", "")), int(r.get("port", 0)))
			return
		if float(r.get("waited_ms", 0)) >= float(r.get("give_up_ms", 10000)):
			api.call_api("/v1/quick/cancel", {})
			_not_found_screen()
			return
		dots = (dots + 1) % 4
		if _status != null and is_instance_valid(_status):
			_status.text = "SEARCHING FOR A PILOT" + ".".repeat(dots)
		await get_tree().create_timer(1.0).timeout
		if gen != _gen:
			return


func _cancel_quick() -> void:
	api.call_api("/v1/quick/cancel", {})
	open_menu()


func _not_found_screen() -> void:
	_leave_room()
	var box := _screen("PLAY NOW")
	box.add_child(_spacer(_vh * 0.03))
	box.add_child(_label("NO PILOT FOUND RIGHT NOW", _font() * 1.3, COL_GOLD))
	box.add_child(_label("Nobody else is looking for a partner at the moment.", _font(), COL_MUTED))
	box.add_child(_spacer(_vh * 0.03))
	box.add_child(_button("KEEP SEARCHING", COL_GREEN, _play_now))
	box.add_child(_button("PLAY WITH A FRIEND", COL_CYAN, _play_friend))
	box.add_child(_button("BACK", COL_RED, open_menu))


# --- In a room ---

func _room_screen(title: String, status: String) -> void:
	var box := _screen(title)
	box.add_child(_spacer(_vh * 0.04))
	_names = _label("", _font() * 1.3, COL_CYAN)
	box.add_child(_names)
	box.add_child(_spacer(_vh * 0.02))
	_status = _label(status, _font() * 1.1, COL_GREEN)
	box.add_child(_status)
	box.add_child(_spacer(_vh * 0.04))
	box.add_child(_button("CANCEL", COL_RED, open_menu))


## Join the room server (ENet). The names and the start come from the room.
func _connect(host_addr: String, port: int) -> void:
	var gen: int = _gen
	if host_addr == "" or port <= 0 or Net.start_coop(host_addr, port, CoopSession.pilot_name()) != OK:
		_error("Could not reach the room.")
		return
	_in_room = true
	var c: Node = Net.client
	c.lobby_changed.connect(_on_lobby)
	c.go.connect(_on_go)
	c.refused.connect(_on_refused)
	if not Net.disconnected.is_connected(_on_room_lost):
		Net.disconnected.connect(_on_room_lost)
	var waited: float = 0.0
	while Net.my_peer == 0:
		await get_tree().process_frame
		if gen != _gen:
			return
		waited += get_process_delta_time()
		if waited > CONNECT_SECS:
			_error("Could not reach the room.")
			return
	if _matched_room:
		# The other pilot must turn up; otherwise back to "not found".
		await get_tree().create_timer(PARTNER_WAIT_SECS).timeout
		if gen == _gen and _in_room and not _starting:
			_not_found_screen()


func _on_lobby(players: Array, needed: int) -> void:
	if not _in_room or _starting:
		return
	var lines: Array = []
	for p in players:
		var n: String = str(p[2]) if (p as Array).size() > 2 and str(p[2]) != "" else "PILOT"
		lines.append(n + ("  (YOU)" if int(p[0]) == Net.my_peer else ""))
	while lines.size() < needed:
		lines.append("...")
	if _names != null and is_instance_valid(_names):
		_names.text = "\n".join(lines)
	if _status != null and is_instance_valid(_status):
		_status.text = "YOUR PARTNER IS HERE" if players.size() >= needed else ("WAITING FOR YOUR FRIEND..." if _code != "" and not _matched_room else "WAITING FOR YOUR PARTNER...")


func _on_go(sector: int, _seed: int) -> void:
	if not _in_room or _starting:
		return
	_starting = true
	var gen: int = _gen
	for n in range(START_COUNT, 0, -1):
		if _status != null and is_instance_valid(_status):
			_status.text = "STARTING IN %d" % n
		await get_tree().create_timer(1.0).timeout
		if gen != _gen or not _in_room:
			return
	# From here the game scene owns the session.
	_in_room = false
	if Net.disconnected.is_connected(_on_room_lost):
		Net.disconnected.disconnect(_on_room_lost)
	CoopSession.begin_run(sector)
	# pk = partner kind (0 human, 1 labelled AI, 2 disguised AI): the bot experiment.
	Telemetry.track("coop_start", {"pk": int(Net.client.partner_kind) if Net.client != null else 0, "via": "quick" if _matched_room else "friend"})
	get_tree().change_scene_to_file(MAIN_SCENE)


func _on_refused(reason: String) -> void:
	_error(_api_error({"error": reason}))


func _on_room_lost() -> void:
	if _in_room:
		_error("Lost the connection to the room.")


# --- DEV ---

func dev_auto(action: String) -> void:
	dev_auto_action = action
	match action:
		"menu":
			open_menu()
		"friend":
			_play_friend()
		"quick":
			_play_now()
		"scan":
			_scan_screen()
		"joinscreen":
			_join_screen()
		"join":
			_screen("JOIN WITH CODE")
			var gen: int = _gen
			for i in 60:   # wait for the other window to write a fresh code
				if FileAccess.file_exists("user://coop_dev_code.txt") and Time.get_unix_time_from_system() - float(FileAccess.get_modified_time("user://coop_dev_code.txt")) < 30.0:
					break
				await get_tree().create_timer(0.5).timeout
				if gen != _gen:
					return
			_join(FileAccess.get_file_as_string("user://coop_dev_code.txt").strip_edges())
