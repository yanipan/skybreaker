extends Node
## Global game state singleton.
## Holds runtime data for the current player session.
## Persistent data is loaded/saved via SaveSystem.

# Player progression
var money: int = 0
var total_score: int = 0
var current_sector: int = 1
var current_mission: int = 1

# Current run state
var current_ship_id: StringName = &"scout"
var current_primary_weapon_id: StringName = &"vulcan"
var current_secondary_weapon_id: StringName = &"bomb"

# Run stats (reset each mission)
var mission_score: int = 0
var mission_money: int = 0
var mission_kills: int = 0
var mission_damage_taken: int = 0


func reset_mission_stats() -> void:
	mission_score = 0
	mission_money = 0
	mission_kills = 0
	mission_damage_taken = 0


func add_money(amount: int) -> void:
	money += amount
	mission_money += amount
	EventBus.money_changed.emit(money)


func add_score(amount: int) -> void:
	total_score += amount
	mission_score += amount
	EventBus.score_changed.emit(total_score)
