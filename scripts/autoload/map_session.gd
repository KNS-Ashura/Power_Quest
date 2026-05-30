extends Node

## Active map for this session (1 = Undead Land, 2 = Desert Land, 3 = Glowing Cave).
var active_map_index: int = 1
## AI difficulty for Solo vs IA (0 = simple, 1 = normal, 2 = hard).
var active_ai_difficulty: int = 1

enum AIDifficulty {
	SIMPLE,
	NORMAL,
	HARD,
}

const MAP_SCENE_PATHS: Dictionary = {
	1: "res://scenes/map/Map1.scn",
	2: "res://scenes/map/Map2.scn",
	3: "res://scenes/map/Map3.scn",
}

const ONLINE_MAP_POOL: Array[int] = [1, 2, 3]

const GAME_SHELL_SCENE := "res://scenes/jeu/Main.scn"

var is_online_match: bool = false
var local_team: int = 0
var online_player_count: int = 0
var online_camps_ready: bool = false
var team_display_names: Dictionary = {}


func is_local_team(team_id: int) -> bool:
	if not is_online_match:
		return team_id == 0
	return team_id == local_team


func is_hostile_team(team_id: int) -> bool:
	if team_id == 2:
		return false
	if not is_online_match:
		return team_id == 1
	return team_id != local_team and team_id != 2


func is_neutral_team(team_id: int) -> bool:
	return team_id == 2


func set_team_display_names(names: PackedStringArray) -> void:
	team_display_names.clear()
	for i in range(names.size()):
		var label := str(names[i]).strip_edges()
		if label != "":
			team_display_names[i] = label


func get_team_display_name(team_id: int) -> String:
	if is_neutral_team(team_id):
		return tr("TEAM_NEUTRAL")
	if team_display_names.has(team_id):
		var name: String = str(team_display_names[team_id]).strip_edges()
		if name != "":
			return name
	if not is_online_match and team_id == 1:
		return tr("TEAM_ENEMY_AI")
	return tr("TEAM_ENEMY")


func reset_online_state() -> void:
	is_online_match = false
	local_team = 0
	online_player_count = 0
	online_camps_ready = false
	team_display_names.clear()
	if OnlineGameSync.has_method("reset"):
		OnlineGameSync.reset()


func pick_random_online_map_index() -> int:
	return ONLINE_MAP_POOL[randi() % ONLINE_MAP_POOL.size()]


func normalize_online_map_index(map_index: int) -> int:
	if map_index in ONLINE_MAP_POOL:
		return map_index
	return ONLINE_MAP_POOL[0]


func get_map_scene_path(map_index: int = -1) -> String:
	var idx := map_index if map_index > 0 else active_map_index
	return MAP_SCENE_PATHS.get(idx, MAP_SCENE_PATHS[1])


func is_map_available(map_index: int = -1) -> bool:
	return ResourceLoader.exists(get_map_scene_path(map_index))


func get_ai_difficulty() -> int:
	if active_ai_difficulty < AIDifficulty.SIMPLE or active_ai_difficulty > AIDifficulty.HARD:
		return AIDifficulty.NORMAL
	return active_ai_difficulty
