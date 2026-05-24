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
const SCENES_PORT_GUARDIAN = {
	1: preload("res://scenes/personnages/port_guardian/port-gardian-1.tscn"),
	2: preload("res://scenes/personnages/port_guardian/port-gardian-2.tscn"),
	3: preload("res://scenes/personnages/port_guardian/port-gardian-3.tscn")
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

const PORT_VISUAL_PATHS_BY_VARIANT = {
	"map1": {
		1: "res://scenes/camp/map1/port/port_nv1.tscn",
		2: "res://scenes/camp/map1/port/port_nv2.tscn",
		3: "res://scenes/camp/map1/port/port_nv3.tscn"
	},
	"map2": {
		1: "res://scenes/camp/map2/port2/port_nv1.tscn",
		2: "res://scenes/camp/map2/port2/port_nv2.tscn",
		3: "res://scenes/camp/map2/port2/port_nv3.tscn"
	}
}

const STATS_INFANTRY = {
	1: preload("res://scripts/units/stats/infantry/infantry-1.tres"),
	2: preload("res://scripts/units/stats/infantry/infantry-2.tres"),
	3: preload("res://scripts/units/stats/infantry/infantry-3.tres")
}
const STATS_ARCHER = {
	1: preload("res://scripts/units/stats/range/range-1.tres"),
	2: preload("res://scripts/units/stats/range/range-2.tres"),
	3: preload("res://scripts/units/stats/range/range-3.tres")
}
const STATS_HEAVY = {
	1: preload("res://scripts/units/stats/heavy/heavy-1.tres"),
	2: preload("res://scripts/units/stats/heavy/heavy-2.tres"),
	3: preload("res://scripts/units/stats/heavy/heavy-3.tres")
}
const STATS_SUPPORT = {
	1: preload("res://scripts/units/stats/support/support-1.tres"),
	2: preload("res://scripts/units/stats/support/support-2.tres"),
	3: preload("res://scripts/units/stats/support/support-3.tres")
}
const STATS_HEAL = {
	1: preload("res://scripts/units/stats/healer/healer-1.tres"),
	2: preload("res://scripts/units/stats/healer/healer-2.tres"),
	3: preload("res://scripts/units/stats/healer/healer-3.tres")
}
const STATS_ANTI_ARMOR = {
	1: preload("res://scripts/units/stats/anti_armor/anti_armor-1.tres"),
	2: preload("res://scripts/units/stats/anti_armor/anti_armor-2.tres"),
	3: preload("res://scripts/units/stats/anti_armor/anti_armor-3.tres")
}
const STATS_GUARDIAN = {
	1: preload("res://scripts/units/stats/gardien/gardien-1.tres"),
	2: preload("res://scripts/units/stats/gardien/gardien-2.tres"),
	3: preload("res://scripts/units/stats/gardien/gardien-3.tres")
}
const STATS_PORT_GUARDIAN = {
	1: preload("res://scripts/units/stats/port_guardian/port_guardian-1.tres"),
	2: preload("res://scripts/units/stats/port_guardian/port_guardian-2.tres"),
	3: preload("res://scripts/units/stats/port_guardian/port_guardian-3.tres")
}
const STATS_MORTAR = {
	1: preload("res://scripts/units/stats/mortar/mortar-1.tres"),
	2: preload("res://scripts/units/stats/mortar/mortar-2.tres"),
	3: preload("res://scripts/units/stats/mortar/mortar-3.tres")
}

const SCENES_WATER_TRANSPORTER = {
	1: preload("res://scenes/personnages/water-transporter/water-transporter-1.tscn"),
	2: preload("res://scenes/personnages/water-transporter/water-transporter-2.tscn"),
	3: preload("res://scenes/personnages/water-transporter/water-transporter-3.tscn"),
}
const SCENES_WATER_TANK = {
	1: preload("res://scenes/personnages/water-tank/water-tank-1.tscn"),
	2: preload("res://scenes/personnages/water-tank/water-tank-2.tscn"),
	3: preload("res://scenes/personnages/water-tank/water-tank-3.tscn"),
}
const SCENES_WATER_RANGE = {
	1: preload("res://scenes/personnages/water-range/water-range-1.tscn"),
	2: preload("res://scenes/personnages/water-range/water-range-2.tscn"),
	3: preload("res://scenes/personnages/water-range/water-range-3.tscn"),
}

const STATS_WATER_TRANSPORTER = {
	1: preload("res://scripts/units/stats/water_transporter/water_transporter-1.tres"),
	2: preload("res://scripts/units/stats/water_transporter/water_transporter-2.tres"),
	3: preload("res://scripts/units/stats/water_transporter/water_transporter-3.tres"),
}
const STATS_WATER_TANK = {
	1: preload("res://scripts/units/stats/water_tank/water_tank-1.tres"),
	2: preload("res://scripts/units/stats/water_tank/water_tank-2.tres"),
	3: preload("res://scripts/units/stats/water_tank/water_tank-3.tres"),
}
const STATS_WATER_RANGE = {
	1: preload("res://scripts/units/stats/water_range/water_range-1.tres"),
	2: preload("res://scripts/units/stats/water_range/water_range-2.tres"),
	3: preload("res://scripts/units/stats/water_range/water_range-3.tres"),
}


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


static func port_unit_catalog(camp_level: int) -> Dictionary:
	return {
		0: stats_for_level(STATS_WATER_TRANSPORTER, camp_level),
		1: stats_for_level(STATS_HEAL, camp_level),
		2: stats_for_level(STATS_WATER_TANK, camp_level),
		3: stats_for_level(STATS_WATER_RANGE, camp_level),
	}


static func stats_for_level(stats_by_level: Dictionary, camp_level: int) -> UnitStats:
	if stats_by_level.has(camp_level):
		return stats_by_level[camp_level]
	return stats_by_level[1]


static func scene_for_level(scenes_by_level: Dictionary, camp_level: int) -> PackedScene:
	if scenes_by_level.has(camp_level):
		return scenes_by_level[camp_level]
	return scenes_by_level[1]


static func _load_scene_if_exists(path: String) -> PackedScene:
	if path.is_empty() or not ResourceLoader.exists(path):
		return null
	var res = load(path)
	return res if res is PackedScene else null




static func guardian_scene(camp_level: int) -> PackedScene:
	return scene_for_level(SCENES_GUARDIAN, camp_level)


static func port_guardian_scene(camp_level: int) -> PackedScene:
	return scene_for_level(SCENES_PORT_GUARDIAN, camp_level)


static func guardian_scene_for_site(camp_level: int, port: bool) -> PackedScene:
	if port:
		return port_guardian_scene(camp_level)
	return guardian_scene(camp_level)


static func guardian_stats(camp_level: int) -> UnitStats:
	return stats_for_level(STATS_GUARDIAN, camp_level)


static func port_guardian_stats(camp_level: int) -> UnitStats:
	return stats_for_level(STATS_PORT_GUARDIAN, camp_level)


static func guardian_stats_for_site(camp_level: int, port: bool) -> UnitStats:
	if port:
		return port_guardian_stats(camp_level)
	return guardian_stats(camp_level)


static func scene_for_unit(stat: UnitStats, _unit_id: int, camp_level: int) -> PackedScene:
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
		UnitStats.UnitType.WATER_TRANSPORT:
			return scene_for_level(SCENES_WATER_TRANSPORTER, camp_level)
		UnitStats.UnitType.WATER_TANK:
			return scene_for_level(SCENES_WATER_TANK, camp_level)
		UnitStats.UnitType.WATER_RANGE:
			return scene_for_level(SCENES_WATER_RANGE, camp_level)
		_:
			return scene_for_level(SCENES_INFANTRY, camp_level)


static func visual_paths(variant: String, port: bool = false) -> Dictionary:
	var table: Dictionary = PORT_VISUAL_PATHS_BY_VARIANT if port else CAMP_VISUAL_PATHS_BY_VARIANT
	return table.get(variant, table["map1"])
