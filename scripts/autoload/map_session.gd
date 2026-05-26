extends Node

## Active map for this session (1 = Undead Land, 2 = Desert Land, 3 = TBD).
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

const GAME_SHELL_SCENE := "res://scenes/jeu/Main.scn"


func get_map_scene_path(map_index: int = -1) -> String:
	var idx := map_index if map_index > 0 else active_map_index
	return MAP_SCENE_PATHS.get(idx, MAP_SCENE_PATHS[1])


func is_map_available(map_index: int = -1) -> bool:
	return ResourceLoader.exists(get_map_scene_path(map_index))


func get_ai_difficulty() -> int:
	if active_ai_difficulty < AIDifficulty.SIMPLE or active_ai_difficulty > AIDifficulty.HARD:
		return AIDifficulty.NORMAL
	return active_ai_difficulty
