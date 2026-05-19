extends Node
## Global font registry. Body copy uses Rajdhani Medium automatically via the
## project's default theme/custom_font setting (see project.godot -> [gui]),
## so most labels don't need to touch this file at all.
##
## HEADLINE/SUBHEAD both reference the Orbitron variable font (single TTF that
## carries every weight 400-900). Bold/regular distinction is just visual
## convention here — both come from the same file.

var HEADLINE: Font = preload("res://assets/fonts/Orbitron.ttf")
var SUBHEAD: Font = preload("res://assets/fonts/Orbitron.ttf")
var BODY: Font = preload("res://assets/fonts/Rajdhani-Medium.ttf")
