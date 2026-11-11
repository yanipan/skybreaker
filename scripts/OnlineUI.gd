extends CanvasLayer
## Start-screen overlays for 1.0.1 online features: leaderboard, pilot name,
## challenge code entry, and the end-of-run result panel. Built in code like
## the rest of the menus; buttons come from the host StartScreen so the look
## matches. One overlay at a time; every network wait shows a status line and
## degrades to an "offline" message instead of blocking.

const COL_CYAN := Color(0.55, 0.95, 1.00)
const COL_GOLD := Color(1.00, 0.85, 0.40)
const COL_GREEN := Color(0.55, 1.00, 0.65)
const COL_RED := Color(1.00, 0.45, 0.45)
const COL_MUTED := Color(0.78, 0.80, 0.92, 0.9)

var host: Node            ## StartScreen: provides _make_button() and start_challenge()
var _root: Control = null
var _vw: float
var _vh: float
var _status: Label
var _list: VBoxContainer
var _board_kind: String = "all"


func _ready() -> void:
	layer = 30
	var vp: Vector2 = get_viewport().get_visible_rect().size
	_vw = vp.x
	_vh = vp.y


# --- shared building blocks ---

func is_open() -> bool:
	return _root != null


func close() -> void:
	if _root != null:
		_root.queue_free()
		_root = null


func _open(title: String) -> VBoxContainer:
	close()
	_root = Control.new()
	_root.size = Vector2(_vw, _vh)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)
	var dim := ColorRect.new()
	dim.color = Color(0.01, 0.02, 0.05, 0.96)
	dim.size = Vector2(_vw, _vh)
	_root.add_child(dim)
	var box := VBoxContainer.new()
	box.position = Vector2(_vw * 0.07, _vh * 0.07)
	box.size = Vector2(_vw * 0.86, _vh * 0.86)
	box.add_theme_constant_override("separation", int(clamp(_vh * 0.014, 8, 18)))
	_root.add_child(box)
	box.add_child(_label(title, _font() * 1.5, COL_CYAN, Fonts.HEADLINE))
	return box


func _font() -> int:
	return int(clamp(_vh * 0.022, 16, 30))


func _btn_h() -> float:
	return clamp(_vh * 0.06, 50, 80)


func _label(text: String, size: float, col: Color, font: Font = null) -> Label:
	var l := Label.new()
	l.text = text
	if font != null:
		l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", int(size))
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 4)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(_vw * 0.86, 0)
	return l


func _button(text: String, col: Color, cb: Callable) -> Button:
	var b: Button = host._make_button(text, _vw * 0.86, _btn_h(), col, int(_font() * 1.1))
	b.custom_minimum_size = Vector2(_vw * 0.86, _btn_h())
	b.pressed.connect(cb)
	return b


func _row(buttons: Array) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 12)
	var w: float = (_vw * 0.86 - 12.0 * (buttons.size() - 1)) / buttons.size()
	for b in buttons:
		b.custom_minimum_size = Vector2(w, _btn_h())
		b.size = Vector2(w, _btn_h())
		h.add_child(b)
	return h


func _spacer(h: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	return c


func _line_edit(placeholder: String, max_len: int) -> LineEdit:
	var e := LineEdit.new()
	e.placeholder_text = placeholder
	e.max_length = max_len
	e.alignment = HORIZONTAL_ALIGNMENT_CENTER
	e.custom_minimum_size = Vector2(_vw * 0.86, _btn_h())
	e.add_theme_font_size_override("font_size", int(_font() * 1.2))
	e.virtual_keyboard_enabled = true
	return e


static func fmt(n: int) -> String:
	var s: String = str(absi(n))
	var out: String = ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return ("-" if n < 0 else "") + s + out


# --- Leaderboard ---

func open_leaderboard() -> void:
	var box := _open("LEADERBOARD")
	var all_b: Button = host._make_button("ALL TIME", 10, _btn_h(), COL_GOLD, _font())
	var week_b: Button = host._make_button("THIS WEEK", 10, _btn_h(), COL_GOLD, _font())
	all_b.pressed.connect(func() -> void: _load_board("all"))
	week_b.pressed.connect(func() -> void: _load_board("week"))
	box.add_child(_row([all_b, week_b]))
	_status = _label("", _font(), COL_MUTED)
	box.add_child(_status)
	box.add_child(_label("Tap a name to report it.", _font() * 0.75, Color(COL_MUTED, 0.6)))
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(_vw * 0.86, _vh * 0.42)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
	_list = VBoxContainer.new()
	_list.custom_minimum_size = Vector2(_vw * 0.84, 0)
	scroll.add_child(_list)
	box.add_child(_button("ENTER CHALLENGE CODE", COL_GREEN, open_code_entry))
	box.add_child(_row([
		_button("PILOT NAME", COL_GOLD, func() -> void: open_name_prompt(open_leaderboard)),
		_button("BACK", COL_CYAN, close),
	]))
	_load_board(_board_kind)


func _load_board(kind: String) -> void:
	_board_kind = kind
	if _status == null or not is_instance_valid(_status):
		return
	_status.text = "Loading %s..." % ("this week" if kind == "week" else "all time")
	for c in _list.get_children():
		c.queue_free()
	var r: Dictionary = await Online.board(kind)
	if _status == null or not is_instance_valid(_status) or _board_kind != kind:
		return
	if not r.get("success", false):
		_status.text = "Leaderboard unavailable right now. Check your connection."
		return
	var rows: Array = r.get("rows", [])
	var me: Variant = r.get("me")
	if rows.is_empty():
		_status.text = "No scores yet. Finish a run to take #1!"
	else:
		var head: String = "ALL TIME" if kind == "all" else "THIS WEEK"
		if me is Dictionary:
			head += "  ·  YOU: #%d  %s" % [int(me["rank"]), fmt(int(me["score"]))]
		_status.text = head
	for row in rows:
		_list.add_child(_board_row(row))
	if me is Dictionary and not rows.any(func(x): return x.get("me", false)):
		_list.add_child(_board_row({"rank": me["rank"], "name": me["name"], "score": me["score"], "sector": 0, "me": true}))


func _board_row(row: Dictionary) -> Control:
	var mine: bool = row.get("me", false)
	var h := HBoxContainer.new()
	h.mouse_filter = Control.MOUSE_FILTER_PASS
	# Tap someone else's chosen name to report it (Apple 1.2 user content).
	var who: String = str(row["name"])
	if not mine and not who.begins_with("Pilot-"):
		h.mouse_filter = Control.MOUSE_FILTER_STOP
		h.gui_input.connect(func(ev: InputEvent) -> void:
			var tapped: bool = (ev is InputEventScreenTouch and not ev.pressed) or \
				(ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT and not ev.pressed and ev.device != InputEvent.DEVICE_ID_EMULATION)
			if tapped:
				_confirm_report(who))
	var col: Color = COL_GOLD if mine else Color(0.9, 0.93, 1.0)
	var f: int = int(_font() * 0.95)
	var parts: Array = [
		["#%d" % int(row["rank"]), 0.14, HORIZONTAL_ALIGNMENT_LEFT],
		[str(row["name"]), 0.46, HORIZONTAL_ALIGNMENT_LEFT],
		[fmt(int(row["score"])), 0.26, HORIZONTAL_ALIGNMENT_RIGHT],
		["S%d" % int(row["sector"]) if int(row.get("sector", 0)) > 0 else "", 0.12, HORIZONTAL_ALIGNMENT_RIGHT],
	]
	for p in parts:
		var l := Label.new()
		l.text = p[0]
		l.custom_minimum_size = Vector2(_vw * 0.84 * p[1], 0)
		l.horizontal_alignment = p[2]
		l.clip_text = true
		l.add_theme_font_size_override("font_size", f)
		l.add_theme_color_override("font_color", col)
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		h.add_child(l)
	return h


func _confirm_report(who: String) -> void:
	var box := _open("REPORT NAME")
	box.add_child(_label("Report the pilot name \"%s\" as offensive or inappropriate?" % who, _font() * 1.1, Color.WHITE))
	box.add_child(_label("We review every report. Names reported by several players are removed automatically.", _font() * 0.9, COL_MUTED))
	var msg := _label("", _font(), COL_GREEN)
	box.add_child(msg)
	var holder := VBoxContainer.new()
	box.add_child(holder)
	holder.add_child(_row([
		_button("REPORT", COL_RED, func() -> void:
			msg.text = "Sending..."
			var ok: bool = await Online.report_name(who)
			if not is_instance_valid(msg):
				return
			msg.text = "Thanks, we'll review it." if ok else "No connection. Try again later."
			if ok:
				for c in holder.get_children():
					c.queue_free()
				holder.add_child(_button("BACK", COL_CYAN, open_leaderboard))),
		_button("CANCEL", COL_CYAN, open_leaderboard),
	]))


# --- Pilot name ---

## `first_time` = the welcome variant shown once on first launch: different
## copy, a LATER button instead of CANCEL, and the ask is recorded so it
## never pops again on its own.
func open_name_prompt(after: Callable = Callable(), first_time: bool = false) -> void:
	if first_time:
		Online.mark_name_asked()
	var box := _open("WELCOME, PILOT" if first_time else "PILOT NAME")
	if first_time:
		box.add_child(_label("What should we call you? This is your name on the\nleaderboard. 3-16 letters, numbers or _", _font(), COL_MUTED))
	else:
		box.add_child(_label("Your name on the leaderboard. 3-16 letters, numbers or _", _font(), COL_MUTED))
	var edit := _line_edit(Online.pilot_name if Online.has_custom_name() else "Your pilot name", 16)
	box.add_child(edit)
	var msg := _label("", _font(), COL_RED)
	box.add_child(msg)
	var back := func() -> void:
		if after.is_valid():
			after.call()
		else:
			close()
	var save := func() -> void:
		var n: String = edit.text.strip_edges()
		var local: String = name_problem_local(n)
		if local != "":
			msg.text = local
			return
		msg.add_theme_color_override("font_color", COL_MUTED)
		msg.text = "Saving..."
		var r: Dictionary = await Online.set_pilot_name(n)
		if not is_instance_valid(msg):
			return
		msg.add_theme_color_override("font_color", COL_RED)
		if r.get("ok", false):
			back.call()
		elif r.is_empty():
			msg.text = "No connection. Try again later."
		else:
			msg.text = reason_text(str(r.get("reason", "")))
	edit.text_submitted.connect(func(_t: String) -> void: save.call())
	box.add_child(_row([_button("SAVE", COL_GREEN, save), _button("LATER" if first_time else "CANCEL", COL_CYAN, back)]))
	edit.call_deferred("grab_focus")


static func name_problem_local(n: String) -> String:
	if n.length() < 3 or n.length() > 16:
		return "Use 3 to 16 characters."
	var re := RegEx.new()
	re.compile("^[A-Za-z0-9_]+$")
	if re.search(n) == null:
		return "Letters, numbers and _ only."
	return ""


static func reason_text(reason: String) -> String:
	match reason:
		"length": return "Use 3 to 16 characters."
		"chars": return "Letters, numbers and _ only."
		"taken": return "That name is taken. Try another."
		"reserved": return "That name is reserved. Try another."
		"blocked": return "Please pick a different name."
	return "Could not save the name. Try again."


# --- Challenge code ---

func open_code_entry() -> void:
	var box := _open("CHALLENGE CODE")
	box.add_child(_label("Got a code from a friend? Same waves, beat their score.", _font(), COL_MUTED))
	var edit := _line_edit("ABC123", 6)
	box.add_child(edit)
	var msg := _label("", _font() * 1.05, COL_MUTED)
	box.add_child(msg)
	var start_holder := VBoxContainer.new()
	box.add_child(start_holder)
	var find := func() -> void:
		var code: String = edit.text.strip_edges().to_upper()
		if code.length() != 6:
			msg.text = "Codes have 6 characters."
			return
		msg.text = "Looking up %s..." % code
		for c in start_holder.get_children():
			c.queue_free()
		var r: Dictionary = await Online.get_challenge(code)
		if not is_instance_valid(msg):
			return
		if r.is_empty():
			msg.text = "No connection. Try again later."
			return
		if not r.get("success", false):
			msg.text = "No challenge with that code."
			return
		msg.text = "%s scored %s (reached sector %d).\nSame waves. Can you beat it?" % [r["name"], fmt(int(r["score"])), int(r["sector"])]
		start_holder.add_child(_button("START CHALLENGE", COL_GREEN, func() -> void:
			msg.text = "Starting..."
			host.start_challenge(code, int(r["score"]), str(r["name"]), msg)))
	edit.text_submitted.connect(func(_t: String) -> void: find.call())
	edit.text_changed.connect(func(t: String) -> void:
		var up: String = t.to_upper()
		if up != t:
			var caret: int = edit.caret_column
			edit.text = up
			edit.caret_column = caret)
	box.add_child(_row([_button("FIND", COL_GOLD, find), _button("BACK", COL_CYAN, open_leaderboard)]))
	edit.call_deferred("grab_focus")


# --- End of run ---

func open_last_run() -> void:
	var lr: Dictionary = GameState.last_run
	if lr.is_empty():
		return
	var box := _open("VICTORY!" if lr.get("won", false) else "RUN OVER")
	box.add_child(_label("SCORE  %s" % fmt(int(lr["score"])), _font() * 1.6, COL_GOLD, Fonts.HEADLINE))
	box.add_child(_label("Reached sector %d" % int(lr["sector"]), _font(), COL_MUTED))
	var rank := _label("", _font() * 1.1, Color.WHITE)
	box.add_child(rank)
	var ch := _label("", _font() * 1.1, COL_GREEN)
	box.add_child(ch)
	var code_lbl := _label("", _font() * 1.8, COL_GREEN, Fonts.HEADLINE)
	box.add_child(code_lbl)
	var actions := VBoxContainer.new()
	actions.add_theme_constant_override("separation", 12)
	box.add_child(actions)
	var refresh := func() -> void:
		if not is_instance_valid(rank):
			return
		var r: Dictionary = GameState.last_run
		if str(r.get("token", "")) == "":
			rank.text = "Not ranked: this run started offline."
		elif r.get("ranked", false):
			rank.text = "Rank #%d all time  ·  #%d this week" % [int(r.get("rank_all", 0)), int(r.get("rank_week", 0))]
		elif r.get("queued", false):
			rank.text = "Offline: score saved, it will be sent when you're back online."
		elif r.get("refused", false) or r.has("rank_all") or r.has("challenge_beat"):
			rank.text = "Not ranked."
		else:
			rank.text = "Sending your score..."
		if str(r.get("challenge_name", "")) != "":
			var target: int = int(r.get("challenge_target", 0))
			var diff: int = int(r["score"]) - target
			ch.text = ("You beat %s by %s!" % [r["challenge_name"], fmt(diff)]) if diff > 0 else ("%s short of %s's %s." % [fmt(-diff), r["challenge_name"], fmt(target)])
			ch.add_theme_color_override("font_color", COL_GREEN if diff > 0 else COL_RED)
		for c in actions.get_children():
			c.queue_free()
		if r.get("ranked", false):
			if not Online.has_custom_name():
				actions.add_child(_button("PICK PILOT NAME", COL_GOLD, func() -> void: open_name_prompt(open_last_run)))
			actions.add_child(_button("CHALLENGE A FRIEND", COL_GREEN, func() -> void:
				code_lbl.text = "..."
				var code: String = await Online.create_challenge(str(GameState.last_run.get("token", "")))
				if not is_instance_valid(code_lbl):
					return
				if code == "":
					code_lbl.text = ""
					rank.text = "Could not create a code. Try again."
					return
				DisplayServer.clipboard_set("Beat my Skybreaker score of %s! Challenge code: %s" % [fmt(int(GameState.last_run["score"])), code])
				code_lbl.text = code
				rank.text = "Code copied. Send it to a friend!"))
		actions.add_child(_button("LEADERBOARD", COL_GOLD, func() -> void:
			GameState.last_run = {}
			open_leaderboard()))
		actions.add_child(_button("CLOSE", COL_CYAN, func() -> void:
			GameState.last_run = {}
			close()))
	refresh.call()
	if not Online.run_finished.is_connected(_on_run_finished):
		Online.run_finished.connect(_on_run_finished)
	_root.set_meta("refresh", refresh)


func _on_run_finished(_r: Dictionary) -> void:
	if _root != null and _root.has_meta("refresh"):
		(_root.get_meta("refresh") as Callable).call()
