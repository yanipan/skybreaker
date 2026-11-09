extends Node
## Windowed check that story clips really play in the engine: opens the intro
## cutscene, jumps to the launch beat (which has a .ogv), and reports that the
## clip is playing, covers the screen and stretches the beat to its length.
## Saves user://cutscene_video.png. Needs a window (video decoding + capture):
##   godot --path . res://scenes/tools/CutsceneVideoShot.tscn

var _fails: int = 0

func _check(ok: bool, label: String) -> void:
	print("%s  %s" % ["PASS" if ok else "FAIL", label])
	if not ok:
		_fails += 1

func _ready() -> void:
	var beats: Array = CutsceneData.beats_for(CutsceneData.INTRO_KEY)
	var cs: Cutscene = load("res://scripts/Cutscene.gd").new()
	add_child(cs)
	cs.play(beats)
	await get_tree().create_timer(0.8, true).timeout
	cs._advance_to_beat(3, false)
	await get_tree().create_timer(2.2, true).timeout
	var vp: Vector2 = get_viewport().get_visible_rect().size
	var v: VideoStreamPlayer = cs._video_b if cs._video_b.visible and cs._video_b.is_playing() else cs._video_a
	print("video size=", v.size, " pos=", v.position, " viewport=", vp, " playing=", v.is_playing(), " t=", v.stream_position, " beat=", cs._beat_duration)
	_check(v.visible and v.is_playing(), "the launch clip is playing")
	_check(v.stream_position > 1.0, "the clip advances (%.1f s in)" % v.stream_position)
	_check(v.size.x >= vp.x - 1.0 and v.size.y >= vp.y - 1.0, "the clip covers the whole screen")
	_check(absf(v.size.x / v.size.y - 720.0 / 1096.0) < 0.02, "the clip keeps its aspect (no stretching)")
	_check(cs._beat_duration >= 9.9, "the beat lasts as long as the 10 s clip (%.1f s)" % cs._beat_duration)
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("user://cutscene_video.png")
	var clips: int = 0
	for key in [CutsceneData.INTRO_KEY, CutsceneData.ACT_1_KEY, CutsceneData.ACT_2_KEY, CutsceneData.ACT_3_KEY, CutsceneData.ACT_4_KEY, CutsceneData.ACT_5_KEY, CutsceneData.ENDING_KEY]:
		var has: bool = false
		for b in CutsceneData.beats_for(key):
			if ResourceLoader.exists(Cutscene.CUTSCENE_DIR + String(b["image_file"]) + ".ogv"):
				has = true
		if has:
			clips += 1
		else:
			print("no clip yet for ", key)
	print("cutscenes with a clip: %d of 7" % clips)
	print("CutsceneVideoShot: %d failure(s)" % _fails)
	get_tree().paused = false
	get_tree().quit(1 if _fails > 0 else 0)
