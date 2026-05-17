extends RefCounted

const SCENES_INFANTRY = {
	1: preload("res://scenes/personnages/infantry/infantry-1.tscn"),
	2: preload("res://scenes/personnages/infantry/infantry-2.tscn"),
	3: preload("res://scenes/personnages/infantry/infantry-3.tscn")
}
const SCENES_RANGE = {
	1: preload("res://scenes/personnages/range/range-1.tscn"),
	2: preload("res://scenes/personnages/range/range-2.tscn"),
	3: preload("res://scenes/personnages/range/range-3.tscn")
}
const SCENES_HEAVY = {
	1: preload("res://scenes/personnages/heavy/heavy-1.tscn"),
	2: preload("res://scenes/personnages/heavy/heavy-2.tscn"),
	3: preload("res://scenes/personnages/heavy/heavy-3.tscn")
}
const SCENES_SUPPORT = {
	1: preload("res://scenes/personnages/support/support-1.tscn"),
	2: preload("res://scenes/personnages/support/support-2.tscn"),
	3: preload("res://scenes/personnages/support/support-3.tscn")
}
const SCENES_HEALER = {
	1: preload("res://scenes/personnages/healer/healer-1.tscn"),
	2: preload("res://scenes/personnages/healer/healer-2.tscn"),
	3: preload("res://scenes/personnages/healer/healer-3.tscn")
}
const SCENES_MORTAR = {
	1: preload("res://scenes/personnages/mortar/mortar-1.tscn"),
	2: preload("res://scenes/personnages/mortar/mortar-2.tscn"),
	3: preload("res://scenes/personnages/mortar/mortar-3.tscn")
}
const SCENES_ANTI_ARMOR = {
	1: preload("res://scenes/personnages/anti_armor/anti_armor-1.tscn"),
	2: preload("res://scenes/personnages/anti_armor/anti_armor-2.tscn"),
	3: preload("res://scenes/personnages/anti_armor/anti_armor-3.tscn")
}
const SCENES_GUARDIAN = {
	1: preload("res://scenes/personnages/guardian/gardien-1.tscn"),
	2: preload("res://scenes/personnages/guardian/gardien-2.tscn"),
	3: preload("res://scenes/personnages/guardian/gardien-3.tscn")
}
const SCENES_WATER_TRANSPORT = {
	1: preload("res://scenes/personnages/Water_transport/Water_transporter_nv1.tscn"),
	2: preload("res://scenes/personnages/Water_transport/Water_transporter_nv2.tscn"),
	3: preload("res://scenes/personnages/Water_transport/Water_transporter_nv3.tscn")
}
const SCENES_WATER_TANK = {
	1: preload("res://scenes/personnages/Water_tank/Water_tank_nv1.tscn"),
	2: preload("res://scenes/personnages/Water_tank/Water_tank_nv2.tscn"),
	3: preload("res://scenes/personnages/Water_tank/Water_tank_nv3.tscn")
}
const SCENES_WATER_RANGE = {
	1: preload("res://scenes/personnages/Water_range/Water_range_nv1.tscn"),
	2: preload("res://scenes/personnages/Water_range/Water_range_nv2.tscn"),
	3: preload("res://scenes/personnages/Water_range/Water_range_nv3.tscn")
}
const CAMP_VISUAL_PATHS_BY_VARIANT = {
	"map1": {
		1: "res://scenes/camp/map1/camp_nv1.tscn",
		2: "res://scenes/camp/map1/camp_nv2.tscn",
		3: "res://scenes/camp/map1/camp_nv3.tscn"
	},
	"map2": {
		1: "res://scenes/camp/map2/camp_nv1_map2.tscn",
		2: "res://scenes/camp/map2/camp_nv2_map2.tscn",
		3: "res://scenes/camp/map2/camp_nv3_map2.tscn"
	}
}

const STATS_INFANTRY = {
	1: preload("res://scripts/resources/infantry/infantry-1.tres"),
	2: preload("res://scripts/resources/infantry/infantry-2.tres"),
	3: preload("res://scripts/resources/infantry/infantry-3.tres")
}
const STATS_ARCHER = {
	1: preload("res://scripts/resources/range/range-1.tres"),
	2: preload("res://scripts/resources/range/range-2.tres"),
	3: preload("res://scripts/resources/range/range-3.tres")
}
const STATS_HEAVY = {
	1: preload("res://scripts/resources/heavy/heavy-1.tres"),
	2: preload("res://scripts/resources/heavy/heavy-2.tres"),
	3: preload("res://scripts/resources/heavy/heavy-3.tres")
}
const STATS_SUPPORT = {
	1: preload("res://scripts/resources/support/support-1.tres"),
	2: preload("res://scripts/resources/support/support-2.tres"),
	3: preload("res://scripts/resources/support/support-3.tres")
}
const STATS_HEAL = {
	1: preload("res://scripts/resources/healer/healer-1.tres"),
	2: preload("res://scripts/resources/healer/healer-2.tres"),
	3: preload("res://scripts/resources/healer/healer-3.tres")
}
const STATS_ANTI_ARMOR = {
	1: preload("res://scripts/resources/anti_armor/anti_armor-1.tres"),
	2: preload("res://scripts/resources/anti_armor/anti_armor-2.tres"),
	3: preload("res://scripts/resources/anti_armor/anti_armor-3.tres")
}
const STATS_GUARDIAN = {
	1: preload("res://scripts/resources/gardien/gardien-1.tres"),
	2: preload("res://scripts/resources/gardien/gardien-2.tres"),
	3: preload("res://scripts/resources/gardien/gardien-3.tres")
}
const STATS_MORTAR = {
	1: preload("res://scripts/resources/mortar/mortar-1.tres"),
	2: preload("res://scripts/resources/mortar/mortar-2.tres"),
	3: preload("res://scripts/resources/mortar/mortar-3.tres")
}

const NAVAL_UNIT_IDS := [7, 8, 9]


static func land_unit_catalog(camp_level: int) -> Dictionary:
	return {
		0: stats_for_level(STATS_INFANTRY, camp_level),
		1: stats_for_level(STATS_ARCHER, camp_level),
		2: stats_for_level(STATS_HEAVY, camp_level),
		3: stats_for_level(STATS_SUPPORT, camp_level),
		4: stats_for_level(STATS_HEAL, camp_level),
		5: stats_for_level(STATS_ANTI_ARMOR, camp_level),
		6: stats_for_level(STATS_MORTAR, camp_level),
	}


static func naval_unit_catalog(_camp_level: int) -> Dictionary:
	return {}


static func stats_for_level(stats_by_level: Dictionary, camp_level: int) -> UnitStats:
	if stats_by_level.has(camp_level):
		return stats_by_level[camp_level]
	return stats_by_level[1]


static func scene_for_level(scenes_by_level: Dictionary, camp_level: int) -> PackedScene:
	if scenes_by_level.has(camp_level):
		return scenes_by_level[camp_level]
	return scenes_by_level[1]


static func guardian_scene(camp_level: int) -> PackedScene:
	return scene_for_level(SCENES_GUARDIAN, camp_level)


static func guardian_stats(camp_level: int) -> UnitStats:
	return stats_for_level(STATS_GUARDIAN, camp_level)


static func scene_for_unit(stat: UnitStats, unit_id: int, camp_level: int) -> PackedScene:
	if unit_id == 1:
		return scene_for_level(SCENES_RANGE, camp_level)
	if unit_id == 2:
		return scene_for_level(SCENES_HEAVY, camp_level)
	if unit_id == 3:
		return scene_for_level(SCENES_SUPPORT, camp_level)
	if unit_id == 4:
		return scene_for_level(SCENES_HEALER, camp_level)
	if unit_id == 5:
		return scene_for_level(SCENES_ANTI_ARMOR, camp_level)
	if unit_id == 6:
		return scene_for_level(SCENES_MORTAR, camp_level)
	if unit_id == 7:
		return scene_for_level(SCENES_WATER_TRANSPORT, camp_level)
	if unit_id == 8:
		return scene_for_level(SCENES_WATER_TANK, camp_level)
	if unit_id == 9:
		return scene_for_level(SCENES_WATER_RANGE, camp_level)
	match stat.unit_type:
		UnitStats.UnitType.ARCHER:
			return scene_for_level(SCENES_RANGE, camp_level)
		UnitStats.UnitType.HEAVY:
			return scene_for_level(SCENES_HEAVY, camp_level)
		UnitStats.UnitType.SUPPORT:
			return scene_for_level(SCENES_SUPPORT, camp_level)
		UnitStats.UnitType.HEAL:
			return scene_for_level(SCENES_HEALER, camp_level)
		UnitStats.UnitType.ANTI_ARMOR:
			return scene_for_level(SCENES_ANTI_ARMOR, camp_level)
		UnitStats.UnitType.MORTAR:
			return scene_for_level(SCENES_MORTAR, camp_level)
		_:
			return scene_for_level(SCENES_INFANTRY, camp_level)


static func visual_paths(variant: String) -> Dictionary:
	return CAMP_VISUAL_PATHS_BY_VARIANT.get(variant, CAMP_VISUAL_PATHS_BY_VARIANT["map1"])
