extends CanvasLayer
class_name StarbaseShop
## Modal shop overlay opened by Starbase.gd. The player browses and buys multiple
## items in one visit, then hits LEAVE which closes the shop and emits `closed`.
## Each Starbase visit is one shopping session — once leaved, that station drifts
## off and the player must wait for the next one to spawn.
##
## Money comes from GameState.money. Items have escalating costs (esp. weapon
## power-up) and hard caps where appropriate (shield/torpedo capacity/speed/power).
##
## Items:
##   - Hull Repair        — refill HP                  flat 30
##   - Stronger Shield    — +1 max_shield, max 5       100 / 200 / 350 / 500
##   - Weapon Power Up    — +1 power_level             80 → 140 → 220 → 320 → 450 → ...
##   - Torpedo Refill     — refill torpedoes to max    flat 60
##   - Torpedo Bay        — +1 max_torpedoes, max 5    150 / 250 / 380
##   - Speed Boost        — +1 speed_tier, max 3       180 / 280 / 420
##   - Energy Cell        — +20 max_charge             120 (repeatable, raises ceiling)
##   - Switch Weapon      — cycle Phaser/Beam/Missile  40

signal closed

## Cached Orbitron font, looked up at runtime via the Fonts autoload. Going
## through get_node_or_null instead of the direct `Fonts.HEADLINE` identifier
## sidesteps a Godot parse-time issue where StarbaseShop.gd was occasionally
## reporting "Identifier not found: Fonts" before the autoload registry had
## a chance to wire itself up. Falls back to ThemeDB's default font so the
## script always loads even if the autoload (or the .ttf) is missing.
var _headline_font: Font = null


func _headline() -> Font:
	if _headline_font != null:
		return _headline_font
	var fonts_node: Node = get_node_or_null("/root/Fonts")
	if fonts_node != null and "HEADLINE" in fonts_node:
		_headline_font = fonts_node.HEADLINE
	else:
		_headline_font = ThemeDB.fallback_font
	return _headline_font


## Apply consistent dark-cyan chrome to a shop Button across every state.
## Without this, Godot's default theme renders disabled buttons with a flat
## gray panel while normal buttons get a different default — the result is
## the "some buttons gray, some not" mismatch the player saw on MAXED/100%
## rows. Each state gets its own StyleBoxFlat tinted slightly differently
## so hover/pressed still feel responsive, but they all share the same
## border + corner radius so the cards look like one consistent button set.
func _style_shop_button(b: Button) -> void:
	var border_col := Color(0.40, 0.85, 1.00, 0.85)
	var make := func(bg: Color, border: Color) -> StyleBoxFlat:
		var s := StyleBoxFlat.new()
		s.bg_color = bg
		s.border_color = border
		s.set_border_width_all(2)
		s.set_corner_radius_all(8)
		s.content_margin_left = 14
		s.content_margin_right = 14
		s.content_margin_top = 8
		s.content_margin_bottom = 8
		return s
	var normal: StyleBoxFlat = make.call(Color(0.06, 0.14, 0.22, 0.92), border_col)
	var hover: StyleBoxFlat = make.call(Color(0.10, 0.22, 0.32, 0.95), Color(0.55, 0.95, 1.0, 1.0))
	var pressed: StyleBoxFlat = make.call(Color(0.04, 0.10, 0.16, 0.95), Color(0.30, 0.75, 0.95, 1.0))
	var disabled: StyleBoxFlat = make.call(Color(0.06, 0.14, 0.22, 0.65), Color(0.40, 0.85, 1.00, 0.45))
	var focus: StyleBoxFlat = make.call(Color(0, 0, 0, 0), Color(0.70, 1.0, 1.0, 0.9))
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", pressed)
	b.add_theme_stylebox_override("disabled", disabled)
	b.add_theme_stylebox_override("focus", focus)
	b.add_theme_color_override("font_color", Color(0.90, 0.98, 1.00, 1.0))
	b.add_theme_color_override("font_hover_color", Color(1, 1, 1, 1))
	b.add_theme_color_override("font_pressed_color", Color(0.80, 0.95, 1.0, 1.0))
	b.add_theme_color_override("font_disabled_color", Color(0.65, 0.78, 0.85, 0.85))


# Shop icons. The 8 PNGs live under assets/sprites/shop/ with backgrounds
# already stripped. NOTE: buymissleweapon.png is missing from Downloads —
# the weapon_switch row falls back to using the beam icon as a generic
# "change weapon" visual until the missile asset is provided.
const TEX_REPAIR := preload("res://assets/sprites/shop/buyhullrepair.png")
const TEX_SHIELD := preload("res://assets/sprites/shop/buyshieldupgrade.png")
const TEX_POWER := preload("res://assets/sprites/shop/butweaponpowerup.png")
const TEX_TORP := preload("res://assets/sprites/shop/buytorpedo.png")
const TEX_TORP_BAY := preload("res://assets/sprites/shop/buytorpedobay.png")
const TEX_SPEED := preload("res://assets/sprites/shop/upgradeshipspeed.png")
const TEX_PHASER := preload("res://assets/sprites/shop/buyphaserweaons.png")
const TEX_BEAM := preload("res://assets/sprites/shop/buybeamweapons.png")
const TEX_SIDEKICK := preload("res://assets/sprites/shop/buysidekick.png")
const TEX_ENERGY := preload("res://assets/sprites/shop/buyenergycell.png")

# Alien trader portraits — cycles through alien1..alien4 as the player buys.
# The progression makes the trader feel reactive: idle pose → progressively
# more excited as more credits change hands. Resets when the shop closes.
const ALIEN_TEXTURES_RAW: Array = [
	preload("res://assets/sprites/shop/alien1.png"),
	preload("res://assets/sprites/shop/alien2.png"),
	preload("res://assets/sprites/shop/alien3.png"),
	preload("res://assets/sprites/shop/alien4.png"),
]

var player_ref: Node = null

var _root: ColorRect
var _money_label: Label
var _msg_label: Label
var _msg_time_left: float = 0.0
var _items_root: Container

# Alien trader — sits at the top of the shop panel above the title. Each
# successful purchase advances the portrait by one (clamped to the last frame).
var _alien_sprite: TextureRect = null
var _alien_stage: int = 0

# --- Trader speech bubble ---
# A small panel anchored to the upper-right of the trader portrait that shows
# a randomly-picked line of dialog. The line refreshes when the shop opens
# (greeting), after each successful purchase (thank-you, scaling with how
# excited the trader is), and when the player tries to buy something they
# can't afford (broke jab). Bubble + tail are drawn via _SpeechBubble below.
var _bubble: Control = null
var _bubble_label: Label = null

# Greetings shown when the shop first opens. One picked at random.
const ALIEN_LINES_GREET: Array = [
	"My favorite customer is back!",
	"What would you like to buy today?",
	"Welcome, welcome — fresh stock just landed!",
	"Ahhh, a discerning pilot. I have just the thing.",
	"Step right up — credits in, firepower out!",
]

# Post-purchase lines, one array per trader excitement stage (0..3). The
# trader gets progressively more thrilled as the credits flow.
const ALIEN_LINES_BUY: Array = [
	# Stage 0 — first sale, polite
	[
		"Yes, of course — only the best prices for you!",
		"Excellent choice. You won't regret it.",
		"A wise investment, my friend.",
		"Pleasure doing business.",
		"That one's a classic. Tested in three nebulas.",
	],
	# Stage 1 — getting interested
	[
		"Now THAT is a serious upgrade!",
		"Ohhh, you have good taste, pilot.",
		"Two for two — keep them coming!",
		"My quarterly bonus thanks you.",
		"You and I, we are going to be great friends.",
	],
	# Stage 2 — visibly excited
	[
		"YES! This is what I'm talking about!",
		"You're really going for it today, aren't you?",
		"Three sales! My ancestors are smiling.",
		"At this rate I can finally retire to Tau Ceti.",
		"Take it, take it — barely a scratch on it!",
	],
	# Stage 3 — over the moon (capped portrait)
	[
		"BEST. CUSTOMER. EVER.",
		"I'm naming my next child after you!",
		"Stop, stop, you're making me cry happy tears!",
		"Forget the war, you and I should open a chain!",
		"I would marry your wallet if it were legal.",
	],
]

# Lines shown when the player clicks BUY but can't afford it.
const ALIEN_LINES_BROKE: Array = [
	"Eh-eh — credits first, friend.",
	"Come back when the wallet is heavier!",
	"I take cash, not promises.",
	"Window shopping is free, my friend.",
	"That's a 'no' from accounting.",
]

# Lines shown when the player clicks an item that's already maxed out.
const ALIEN_LINES_MAXED: Array = [
	"You already have the best of that one!",
	"No more upgrades on that — sorry!",
	"That slot is full, pilot. Try another.",
	"Even I cannot sell you what you already own!",
]

# Cached item buttons so we can refresh prices/labels after each purchase
## Width of one grid card (half the scroll area minus separation + scrollbar).
## Item titles are shrunk to fit it on one line — see _fit_item_name.
var _card_w: float = 0.0
var _item_rows: Array = []   ## Each: { row, name_label, desc_label, button, kind, get_price, get_label, can_buy }


func _ready() -> void:
	layer = 100
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()
	_refresh_all()


func _process(delta: float) -> void:
	if _msg_time_left > 0.0:
		_msg_time_left = max(0.0, _msg_time_left - delta)
		if _msg_label != null:
			_msg_label.modulate.a = clamp(_msg_time_left, 0.0, 1.0)


# --- UI build ---

func _build_ui() -> void:
	var vp: Vector2 = get_viewport().get_visible_rect().size
	# Dim background
	_root = ColorRect.new()
	_root.color = Color(0, 0, 0, 0.78)
	_root.size = vp
	_root.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_root)

	# Panel — almost full screen so all 8 items have room and the bottom row
	# isn't clipped on tall mobile viewports.
	var panel := Panel.new()
	var panel_w: float = vp.x * 0.94
	var panel_h: float = vp.y * 0.94
	panel.size = Vector2(panel_w, panel_h)
	panel.position = Vector2((vp.x - panel_w) * 0.5, (vp.y - panel_h) * 0.5)
	panel.process_mode = Node.PROCESS_MODE_ALWAYS
	_root.add_child(panel)

	# --- Header: title + close button + funds pinned above the banner ---
	# Title — centered across the full panel width, no longer squeezed by a
	# corner portrait.
	var title := Label.new()
	title.text = "★ STARBASE SHOP ★"
	title.add_theme_font_override("font", _headline())
	title.add_theme_font_size_override("font_size", 32)
	title.add_theme_color_override("font_color", Color(0.55, 0.95, 1.0))
	title.add_theme_color_override("font_outline_color", Color.BLACK)
	title.add_theme_constant_override("outline_size", 4)
	title.size = Vector2(panel_w - 120, 44)
	title.position = Vector2(60, 16)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	panel.add_child(title)

	# Top-right close button — universal "X" so the player always has a visible
	# escape hatch, even if they can't scroll to the bottom LEAVE button.
	var close_btn := Button.new()
	close_btn.text = "✕"
	close_btn.add_theme_font_size_override("font_size", 32)
	close_btn.add_theme_color_override("font_color", Color(1.0, 0.55, 0.55))
	close_btn.size = Vector2(56, 56)
	close_btn.position = Vector2(panel_w - 68, 12)
	close_btn.process_mode = Node.PROCESS_MODE_ALWAYS
	close_btn.pressed.connect(_on_leave)
	panel.add_child(close_btn)

	# Money display — centered under the title.
	_money_label = Label.new()
	_money_label.add_theme_font_override("font", _headline())
	_money_label.add_theme_font_size_override("font_size", 24)
	_money_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.10))
	_money_label.size = Vector2(panel_w - 120, 32)
	_money_label.position = Vector2(60, 62)
	_money_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	panel.add_child(_money_label)

	# --- Alien trader banner: full-width hero strip above the products ---
	# Runs almost edge-to-edge across the panel and stands 280px tall so the
	# trader has presence instead of hiding in a corner. The banner is a
	# dark-tinted ColorRect frame with the portrait rendered inside it
	# centered on the horizon line — gives the shop a proper "you're standing
	# in front of the alien" vibe. Items scroll starts below it.
	var banner_y: float = 104.0
	var banner_h: float = 280.0
	var banner_frame := ColorRect.new()
	banner_frame.color = Color(0.03, 0.06, 0.12, 0.85)
	banner_frame.size = Vector2(panel_w - 60, banner_h)
	banner_frame.position = Vector2(30, banner_y)
	panel.add_child(banner_frame)
	# Subtle neon top/bottom rules to frame the strip.
	var rule_top := ColorRect.new()
	rule_top.color = Color(0.55, 0.95, 1.0, 0.55)
	rule_top.size = Vector2(panel_w - 60, 2)
	rule_top.position = Vector2(30, banner_y)
	panel.add_child(rule_top)
	var rule_bot := ColorRect.new()
	rule_bot.color = Color(0.55, 0.95, 1.0, 0.55)
	rule_bot.size = Vector2(panel_w - 60, 2)
	rule_bot.position = Vector2(30, banner_y + banner_h - 2)
	panel.add_child(rule_bot)

	_alien_sprite = TextureRect.new()
	_alien_sprite.texture = _get_alien_texture(0)
	_alien_sprite.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	_alien_sprite.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_alien_sprite.size = Vector2(panel_w - 80, banner_h - 16)
	_alien_sprite.position = Vector2(40, banner_y + 8)
	_alien_sprite.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Force trilinear filtering (the .import generates mipmaps) so the 1024x1024
	# portrait downscales smoothly into the ~450px banner. Without this the
	# CanvasLayer's default filter applies and the alien reads as pixelated.
	_alien_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	panel.add_child(_alien_sprite)

	# --- Trader speech bubble (top-right of the banner) ---
	# Sits to the upper-right of the trader portrait so it reads like a
	# comic-book speech balloon. PanelContainer + Label keeps it auto-sized
	# to the line length, and the bubble itself fades in when it has text.
	var bubble_w: float = min(360.0, (panel_w - 60) * 0.45)
	_bubble = PanelContainer.new()
	_bubble.custom_minimum_size = Vector2(bubble_w, 0)
	_bubble.position = Vector2(panel_w - bubble_w - 50, banner_y + 20)
	_bubble.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Soft dark-blue bubble with cyan border to match the shop palette
	var bubble_style := StyleBoxFlat.new()
	bubble_style.bg_color = Color(0.04, 0.10, 0.18, 0.92)
	bubble_style.border_color = Color(0.55, 0.95, 1.0, 0.85)
	bubble_style.set_border_width_all(2)
	bubble_style.set_corner_radius_all(14)
	bubble_style.content_margin_left = 14
	bubble_style.content_margin_right = 14
	bubble_style.content_margin_top = 10
	bubble_style.content_margin_bottom = 10
	bubble_style.shadow_color = Color(0, 0, 0, 0.45)
	bubble_style.shadow_size = 6
	_bubble.add_theme_stylebox_override("panel", bubble_style)
	_bubble_label = Label.new()
	_bubble_label.add_theme_font_size_override("font_size", 18)
	_bubble_label.add_theme_color_override("font_color", Color(0.95, 1.0, 1.0))
	_bubble_label.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	_bubble_label.add_theme_constant_override("outline_size", 2)
	_bubble_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_bubble_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_bubble.add_child(_bubble_label)
	panel.add_child(_bubble)
	# Greet the player on shop open with a random welcome line
	_say_line(ALIEN_LINES_GREET[randi() % ALIEN_LINES_GREET.size()])

	# Items scroll — starts below the banner. Adds some scroll (expected — the
	# user wanted the banner to be worth the trade-off) but every row is now
	# fully visible and nothing overlaps the trader.
	var items_top: float = banner_y + banner_h + 18.0
	var items_bot_reserve: float = 180.0
	# ScrollContainer so all 8 rows are reachable even when the panel can't
	# fit them all on shorter viewports — the player can flick to scroll.
	var scroll := ScrollContainer.new()
	scroll.position = Vector2(30, items_top)
	scroll.size = Vector2(panel_w - 60, panel_h - items_top - items_bot_reserve)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_card_w = (scroll.size.x - 16.0 - 12.0) * 0.5
	scroll.process_mode = Node.PROCESS_MODE_ALWAYS
	panel.add_child(scroll)

	# 2-column GridContainer of "card" tiles. Each tile is a tall column with
	# a big image at the top and the name + description + buy button stacked
	# below — much more readable than the old side-by-side icon+text rows.
	_items_root = GridContainer.new()
	_items_root.columns = 2
	_items_root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_items_root.add_theme_constant_override("h_separation", 16)
	_items_root.add_theme_constant_override("v_separation", 18)
	scroll.add_child(_items_root)

	_add_item("HULL REPAIR", "Restore the ship to full health.", &"repair", TEX_REPAIR)
	_add_item("STRONGER SHIELD", "Increase max shield capacity (+1).", &"shield", TEX_SHIELD)
	# One power-up button per weapon type. The "switch weapon" button is gone
	# now that the player can cycle weapons in-flight with middle mouse button.
	_add_item("PHASER POWER UP", "Boost phaser firepower one tier.", &"power_phaser", TEX_PHASER)
	_add_item("BEAM POWER UP", "Boost beam firepower one tier.", &"power_beam", TEX_BEAM)
	_add_item("MISSILE POWER UP", "Boost missile firepower one tier.", &"power_missile", TEX_POWER)
	_add_item("TORPEDO REFILL", "Top up your torpedo bay.", &"torp_refill", TEX_TORP)
	_add_item("TORPEDO BAY", "Add one torpedo slot (+1 capacity).", &"torp_bay", TEX_TORP_BAY)
	_add_item("THRUSTER UPGRADE", "Move faster — one of three tiers.", &"speed", TEX_SPEED)
	_add_item("ENERGY CELL", "Adds +50% to your weapon energy capacity. Up to 4 cells.", &"charge", TEX_ENERGY)
	_add_item("SIDEKICK", "Hire a wingmate ship. One at a time.", &"sidekick", TEX_SIDEKICK)

	# Status / message line
	_msg_label = Label.new()
	_msg_label.add_theme_font_size_override("font_size", 26)
	_msg_label.add_theme_color_override("font_color", Color(1.0, 0.95, 0.40))
	_msg_label.size = Vector2(panel_w - 60, 36)
	_msg_label.position = Vector2(30, panel_h - 130)
	_msg_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_msg_label.modulate.a = 0.0
	panel.add_child(_msg_label)

	# Leave button — large, high-contrast, pinned to the bottom of the panel
	# but not so close to the edge that it could get clipped.
	var leave := Button.new()
	leave.text = "✕  LEAVE STARBASE"
	leave.add_theme_font_size_override("font_size", 28)
	leave.add_theme_color_override("font_color", Color(1.0, 0.95, 0.55))
	leave.add_theme_color_override("font_hover_color", Color(1.0, 1.0, 0.85))
	leave.size = Vector2(360, 76)
	leave.position = Vector2((panel_w - 360) * 0.5, panel_h - 110)
	leave.process_mode = Node.PROCESS_MODE_ALWAYS
	leave.pressed.connect(_on_leave)
	panel.add_child(leave)


func _add_item(item_name: String, item_desc: String, kind: StringName, icon: Texture2D) -> void:
	# Each item is a vertical "card": big image on top, then name, then desc,
	# then the BUY button. The whole card sits inside the 2-column grid so two
	# items appear side-by-side per row instead of one wide row each.
	var card := VBoxContainer.new()
	card.add_theme_constant_override("separation", 6)
	card.process_mode = Node.PROCESS_MODE_ALWAYS
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.alignment = BoxContainer.ALIGNMENT_BEGIN
	_items_root.add_child(card)

	# --- Big icon area ---
	# Holder forces a tall slot so every card lines up regardless of icon
	# aspect ratio. The TextureButton fills it so the entire image is tappable.
	var icon_holder := Control.new()
	# Bumped from 140 → 210. Source PNGs are 1024x1024 so a bigger slot just
	# pulls more detail out — no resolution loss, the GPU samples a higher
	# mipmap level. The ScrollContainer below absorbs the extra row height.
	icon_holder.custom_minimum_size = Vector2(0, 210)
	icon_holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.add_child(icon_holder)

	var icon_btn: TextureButton = null
	if icon != null:
		icon_btn = TextureButton.new()
		icon_btn.texture_normal = icon
		icon_btn.ignore_texture_size = true
		icon_btn.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
		icon_btn.set_anchors_preset(Control.PRESET_FULL_RECT)
		icon_btn.process_mode = Node.PROCESS_MODE_ALWAYS
		icon_btn.pressed.connect(_on_buy.bind(kind))
		# Pivot is set to icon_holder center each frame via _refresh_pivots,
		# but a sane default at build time keeps the bounce centered until then.
		icon_btn.pivot_offset = Vector2(180, 105)
		# Trilinear filtering — the source PNGs are 1024x1024 but the holder
		# is only ~140px tall, so without mipmaps + linear filtering they
		# alias hard and read as pixelated. Mipmaps are enabled in the
		# matching .png.import files so the GPU has the smaller LODs to sample.
		icon_btn.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		icon_holder.add_child(icon_btn)

	# --- Name (centered, big) ---
	# Wrap is essential — card width is roughly half the panel and titles
	# like "STRONGER SHIELD (LVL 2/5)" or "MISSILE POWER UP (LVL 20/20)"
	# would otherwise overflow off the right edge of the card.
	var name_label := Label.new()
	name_label.text = item_name
	name_label.add_theme_font_override("font", _headline())
	name_label.add_theme_font_size_override("font_size", 19)
	name_label.add_theme_color_override("font_color", Color.WHITE)
	name_label.add_theme_color_override("font_outline_color", Color.BLACK)
	name_label.add_theme_constant_override("outline_size", 3)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# Single line, font shrunk to the card width in _fit_item_name (the old
	# wrap + clip_text cut "PHASER POWER UP  [LVL 12/25]" off after "[LVL").
	name_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	name_label.custom_minimum_size = Vector2(0, 52)
	card.add_child(name_label)

	# --- Description (centered, smaller, wraps) ---
	var desc_label := Label.new()
	desc_label.text = item_desc
	desc_label.add_theme_font_size_override("font_size", 15)
	desc_label.add_theme_color_override("font_color", Color(0.75, 0.85, 0.95))
	desc_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	desc_label.custom_minimum_size = Vector2(0, 40)
	card.add_child(desc_label)

	# --- BUY button below the description ---
	var button := Button.new()
	button.text = "BUY"
	button.add_theme_font_override("font", _headline())
	button.add_theme_font_size_override("font_size", 22)
	button.custom_minimum_size = Vector2(0, 56)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.process_mode = Node.PROCESS_MODE_ALWAYS
	# Force a uniform stylebox across normal / hover / pressed / disabled / focus
	# so MAXED and 100% buttons don't fall back to Godot's gray default disabled
	# panel — every card button reads with the same dark cyan chrome regardless
	# of state, only the text/modulate change when unbuyable.
	_style_shop_button(button)
	button.pressed.connect(_on_buy.bind(kind))
	card.add_child(button)

	_item_rows.append({
		"kind": kind,
		"name_label": name_label,
		"desc_label": desc_label,
		"button": button,
		"icon_btn": icon_btn,
	})


# --- Pricing / availability ---

func _price_for(kind: StringName) -> int:
	var p: Player = player_ref as Player
	match kind:
		&"repair":
			# Hide the option entirely when the player is already at full HP —
			# nothing to repair, so we mark it as 100% in the UI.
			if p != null and p.hp >= p.max_hp:
				return -1
			return 80
		&"shield":
			# Caps at 5
			var lvl: int = (p.max_shield - 1) if p != null else 0
			var ladder: Array = [220, 420, 700, 1000]
			if lvl >= ladder.size():
				return -1
			return int(ladder[lvl])
		&"power_phaser":
			return _power_price_for_weapon(p, 0)
		&"power_beam":
			return _power_price_for_weapon(p, 1)
		&"power_missile":
			return _power_price_for_weapon(p, 2)
		&"torp_refill":
			return 140
		&"torp_bay":
			# Cap at +3 over baseline (max 5)
			var t_cap: int = (p.max_torpedoes - 2) if p != null else 0
			var t_ladder: Array = [320, 520, 780]
			if t_cap >= t_ladder.size():
				return -1
			return int(t_ladder[t_cap])
		&"speed":
			# Capped at tier 3
			var st: int = p.speed_tier if p != null else 0
			var s_ladder: Array = [380, 580, 860]
			if st >= s_ladder.size():
				return -1
			return int(s_ladder[st])
		&"charge":
			# Cap at Player.ENERGY_CELL_MAX cells; price ramps so each cell
			# is meaningfully more expensive than the last.
			var cells: int = p.energy_cells_bought if p != null else 0
			var c_ladder: Array = [300, 520, 800, 1200]
			if cells >= c_ladder.size():
				return -1
			return int(c_ladder[cells])
		&"sidekick":
			# Premium one-time hire. If a sidekick is already on the field,
			# the slot is full — return -1 so the row reads as MAXED.
			if get_tree().get_first_node_in_group(&"sidekick") != null:
				return -1
			return 1500
	return -1


## Read a single weapon's slot level safely (handles missing dict, missing
## key, missing player). Used by both pricing and label refresh.
func _weapon_level(p: Player, weapon: int) -> int:
	if p == null:
		return 1
	if "weapon_levels" in p and p.weapon_levels is Dictionary and p.weapon_levels.has(weapon):
		return int(p.weapon_levels[weapon])
	return int(p.power_level)


## Per-weapon power-up price. Reads the slot level out of player.weapon_levels
## (falls back to the legacy single power_level for safety) and indexes into
## the same fixed ladder the old generic "power" button used. Returns -1 once
## that specific weapon hits the max — its row reads as MAXED while the other
## two stay buyable.
func _power_price_for_weapon(p: Player, weapon: int) -> int:
	if p == null:
		return 180
	var pl: int = 1
	if "weapon_levels" in p and p.weapon_levels is Dictionary and p.weapon_levels.has(weapon):
		pl = int(p.weapon_levels[weapon])
	else:
		pl = int(p.power_level)
	if pl >= p.max_power_level:
		return -1
	# Ladder bumped +15% from [180, 300, 460, 660, 900] to balance the more
	# common drops + the fact that there are now three independent slots to
	# pour money into.
	var fixed: Array = [210, 345, 530, 760, 1035]
	if pl - 1 < fixed.size():
		return int(fixed[pl - 1])
	return 1035 + (pl - 5) * 415


# --- Refresh button labels/colors after each purchase ---

func _refresh_all() -> void:
	_money_label.text = "FUNDS: $%d" % GameState.money
	for row in _item_rows:
		var kind: StringName = row["kind"]
		var price: int = _price_for(kind)
		var btn: Button = row["button"]
		var name_label: Label = row["name_label"]
		var icon_btn: TextureButton = row.get("icon_btn")
		# Append a "level x/y" suffix where it makes sense
		var p: Player = player_ref as Player
		var suffix: String = ""
		if p != null:
			match kind:
				&"shield":
					suffix = "  [LVL %d/5]" % p.max_shield
				&"power_phaser":
					suffix = "  [LVL %d/%d]" % [_weapon_level(p, 0), p.max_power_level]
				&"power_beam":
					suffix = "  [LVL %d/%d]" % [_weapon_level(p, 1), p.max_power_level]
				&"power_missile":
					suffix = "  [LVL %d/%d]" % [_weapon_level(p, 2), p.max_power_level]
				&"torp_bay":
					suffix = "  [%d/5]" % p.max_torpedoes
				&"speed":
					suffix = "  [TIER %d/3]" % p.speed_tier
				&"charge":
					suffix = "  [%d/4]" % p.energy_cells_bought
		var base_text := name_label.text.split("  [")[0]
		name_label.text = base_text + suffix
		_fit_item_name(name_label)
		if price < 0:
			# Friendlier per-row labels instead of the generic MAXED
			if kind == &"repair":
				btn.text = "100%"
			elif kind == &"sidekick":
				btn.text = "HIRED"
			else:
				btn.text = "MAXED"
			btn.disabled = true
		elif GameState.money < price:
			btn.text = "$%d" % price
			btn.disabled = true
		else:
			btn.text = "BUY  $%d" % price
			btn.disabled = false
		# Mirror enabled state on the icon button + dim the icon when locked
		if icon_btn != null:
			icon_btn.disabled = btn.disabled
			icon_btn.modulate = Color(0.45, 0.45, 0.5, 0.7) if btn.disabled else Color(1, 1, 1, 1)


## Shrink an item title's font (base 19, floor 11) so the whole string,
## level suffix included, fits on one line inside its card.
func _fit_item_name(label: Label) -> void:
	var base_size: int = 19
	var font_size: int = base_size
	if _card_w > 0.0:
		var w: float = _headline().get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, base_size).x + 6.0
		if w > _card_w * 0.96:
			font_size = max(11, int(floor(base_size * _card_w * 0.96 / w)))
	label.add_theme_font_size_override("font_size", font_size)


# --- Purchase handling ---

func _on_buy(kind: StringName) -> void:
	var price: int = _price_for(kind)
	# Maxed-out item — trader has nothing left to sell on this slot
	if price < 0:
		_say_line(ALIEN_LINES_MAXED[randi() % ALIEN_LINES_MAXED.size()])
		return
	# Player can't afford it — broke jab
	if GameState.money < price:
		_say_line(ALIEN_LINES_BROKE[randi() % ALIEN_LINES_BROKE.size()])
		return
	if not _apply_purchase(kind):
		return
	# Deduct money manually (GameState.add_money is for gains)
	GameState.money -= price
	EventBus.money_changed.emit(GameState.money)
	_show_message("PURCHASED!", Color(0.55, 1.0, 0.65))
	_bounce_icon(kind)
	_advance_alien()
	# Persist immediately so a shop-then-quit sequence never loses the
	# purchase. _apply_purchase only mutates the live Player (the carry slot
	# was consumed on spawn), so snapshot it into carry_* before saving.
	if player_ref != null and is_instance_valid(player_ref):
		GameState.snapshot_player(player_ref)
	GameState.save_run_state()
	# Trader thank-you line, scaling with the (now-advanced) excitement stage
	var stage_lines: Array = ALIEN_LINES_BUY[clamp(_alien_stage, 0, ALIEN_LINES_BUY.size() - 1)]
	_say_line(stage_lines[randi() % stage_lines.size()])
	_refresh_all()


## Set the trader's speech bubble text. Hides the bubble entirely if line
## is empty. A tiny pop-tween makes the bubble feel like fresh dialog instead
## of a static label.
func _say_line(line: String) -> void:
	if _bubble == null or _bubble_label == null:
		return
	if line == "":
		_bubble.visible = false
		return
	_bubble.visible = true
	_bubble_label.text = line
	_bubble.pivot_offset = _bubble.size * 0.5
	_bubble.scale = Vector2(0.85, 0.85)
	_bubble.modulate.a = 0.0
	var tw := create_tween()
	tw.set_parallel(true)
	tw.set_ease(Tween.EASE_OUT)
	tw.set_trans(Tween.TRANS_BACK)
	tw.tween_property(_bubble, "scale", Vector2.ONE, 0.20)
	tw.tween_property(_bubble, "modulate:a", 1.0, 0.18)


## Returns the Nth alien portrait. The PNGs ship with the background already
## keyed out to alpha (scripts/tools/strip_backgrounds.gd) and their .import
## files generate mipmaps for the downscaled banner.
func _get_alien_texture(stage: int) -> Texture2D:
	if stage < 0 or stage >= ALIEN_TEXTURES_RAW.size():
		return null
	return ALIEN_TEXTURES_RAW[stage]

## Advance the trader portrait one frame, capped at the last image. Each
## purchase makes the alien progressively more excited about your business.
func _advance_alien() -> void:
	if _alien_sprite == null:
		return
	_alien_stage = min(ALIEN_TEXTURES_RAW.size() - 1, _alien_stage + 1)
	_alien_sprite.texture = _get_alien_texture(_alien_stage)
	# Tiny pop animation so the change reads as a reaction.
	_alien_sprite.pivot_offset = _alien_sprite.size * 0.5
	_alien_sprite.scale = Vector2.ONE
	var tw := create_tween()
	tw.set_ease(Tween.EASE_OUT)
	tw.set_trans(Tween.TRANS_BACK)
	tw.tween_property(_alien_sprite, "scale", Vector2(1.15, 1.15), 0.10)
	tw.tween_property(_alien_sprite, "scale", Vector2(1.0, 1.0), 0.18)


## Tween scale-bounce on the row's icon so the click reads as a satisfying
## confirmation. Uses pivot_offset set in _add_item so it scales around center.
func _bounce_icon(kind: StringName) -> void:
	for row in _item_rows:
		if row["kind"] != kind:
			continue
		var icon_btn: TextureButton = row.get("icon_btn")
		if icon_btn == null:
			return
		icon_btn.pivot_offset = icon_btn.size * 0.5
		icon_btn.scale = Vector2.ONE
		var tw := create_tween()
		tw.set_ease(Tween.EASE_OUT)
		tw.set_trans(Tween.TRANS_BACK)
		tw.tween_property(icon_btn, "scale", Vector2(1.25, 1.25), 0.10)
		tw.tween_property(icon_btn, "scale", Vector2(1.0, 1.0), 0.18)
		return


func _apply_purchase(kind: StringName) -> bool:
	var p: Player = player_ref as Player
	if p == null:
		return false
	match kind:
		&"repair":
			p.hp = p.max_hp
		&"shield":
			p.max_shield += 1
			p.shield = float(p.max_shield)
		&"power_phaser":
			if p.has_method("add_power_to_weapon"):
				p.add_power_to_weapon(0)
			else:
				return false
		&"power_beam":
			if p.has_method("add_power_to_weapon"):
				p.add_power_to_weapon(1)
			else:
				return false
		&"power_missile":
			if p.has_method("add_power_to_weapon"):
				p.add_power_to_weapon(2)
			else:
				return false
		&"torp_refill":
			p.torpedo_count = p.max_torpedoes
		&"torp_bay":
			p.max_torpedoes += 1
			p.torpedo_count = p.max_torpedoes
		&"speed":
			p.speed_tier = min(Player.SPEED_TIER_MAX, p.speed_tier + 1)
		&"charge":
			if p.has_method("buy_energy_cell"):
				if not p.buy_energy_cell():
					return false
			else:
				return false
		&"sidekick":
			if p.has_method("_grant_sidekick"):
				p._grant_sidekick()
			else:
				return false
		_:
			return false
	return true


func _show_message(text: String, color: Color) -> void:
	if _msg_label == null:
		return
	_msg_label.text = text
	_msg_label.add_theme_color_override("font_color", color)
	_msg_label.modulate.a = 1.0
	_msg_time_left = 1.6


func _on_leave() -> void:
	closed.emit()
	queue_free()
