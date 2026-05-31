extends RefCounted
class_name BestiaryCatalogue

const CampCatalogue = preload("res://scripts/camp/camp_catalogue.gd")

const MAPS: Array[Dictionary] = [
	{
		"name_key": "MAP_NAME_1",
		"image": preload("res://assets/menu/map-img/map1.png"),
		"map_index": 1,
	},
	{
		"name_key": "MAP_NAME_2",
		"image": preload("res://assets/menu/map-img/map2.png"),
		"map_index": 2,
	},
	{
		"name_key": "MAP_NAME_3",
		"image": preload("res://assets/objects/map3/Castle.png"),
		"map_index": 3,
	},
]

## Display order in the bestiary (10 buttons).
const UNITS: Array[Dictionary] = [
	{"type": UnitStats.UnitType.INFANTRY, "name_key": "UNIT_INFANTRY", "desc_key": "UNIT_DESC_INFANTRY"},
	{"type": UnitStats.UnitType.ARCHER, "name_key": "UNIT_RANGE", "desc_key": "UNIT_DESC_RANGE"},
	{"type": UnitStats.UnitType.HEAVY, "name_key": "UNIT_HEAVY", "desc_key": "UNIT_DESC_HEAVY"},
	{"type": UnitStats.UnitType.SUPPORT, "name_key": "UNIT_SUPPORT", "desc_key": "UNIT_DESC_SUPPORT"},
	{"type": UnitStats.UnitType.HEAL, "name_key": "UNIT_HEAL", "desc_key": "UNIT_DESC_HEAL"},
	{"type": UnitStats.UnitType.ANTI_ARMOR, "name_key": "UNIT_ANTI_ARMOR", "desc_key": "UNIT_DESC_ANTI_ARMOR"},
	{"type": UnitStats.UnitType.MORTAR, "name_key": "UNIT_MORTAR", "desc_key": "UNIT_DESC_MORTAR"},
	{"type": UnitStats.UnitType.WATER_TRANSPORT, "name_key": "UNIT_WATER_TRANSPORT", "desc_key": "UNIT_DESC_WATER_TRANSPORT"},
	{"type": UnitStats.UnitType.WATER_TANK, "name_key": "UNIT_WATER_TANK", "desc_key": "UNIT_DESC_WATER_TANK"},
	{"type": UnitStats.UnitType.WATER_RANGE, "name_key": "UNIT_WATER_RANGE", "desc_key": "UNIT_DESC_WATER_RANGE"},
]


static func unit_entry(index: int) -> Dictionary:
	if index < 0 or index >= UNITS.size():
		return UNITS[0]
	return UNITS[index]


static func stats_for_unit_type(unit_type: int, level: int = 1) -> UnitStats:
	match unit_type:
		UnitStats.UnitType.ARCHER:
			return CampCatalogue.stats_for_level(CampCatalogue.STATS_ARCHER, level)
		UnitStats.UnitType.HEAVY:
			return CampCatalogue.stats_for_level(CampCatalogue.STATS_HEAVY, level)
		UnitStats.UnitType.SUPPORT:
			return CampCatalogue.stats_for_level(CampCatalogue.STATS_SUPPORT, level)
		UnitStats.UnitType.HEAL:
			return CampCatalogue.stats_for_level(CampCatalogue.STATS_HEAL, level)
		UnitStats.UnitType.ANTI_ARMOR:
			return CampCatalogue.stats_for_level(CampCatalogue.STATS_ANTI_ARMOR, level)
		UnitStats.UnitType.MORTAR:
			return CampCatalogue.stats_for_level(CampCatalogue.STATS_MORTAR, level)
		UnitStats.UnitType.WATER_TRANSPORT:
			return CampCatalogue.stats_for_level(CampCatalogue.STATS_WATER_TRANSPORTER, level)
		UnitStats.UnitType.WATER_TANK:
			return CampCatalogue.stats_for_level(CampCatalogue.STATS_WATER_TANK, level)
		UnitStats.UnitType.WATER_RANGE:
			return CampCatalogue.stats_for_level(CampCatalogue.STATS_WATER_RANGE, level)
		_:
			return CampCatalogue.stats_for_level(CampCatalogue.STATS_INFANTRY, level)


static func scene_for_unit_type(unit_type: int, level: int = 1) -> PackedScene:
	var stats := stats_for_unit_type(unit_type, level)
	return CampCatalogue.scene_for_unit(stats, 0, level)


static func format_stats(stats: UnitStats) -> String:
	if stats == null:
		return ""
	var lines: PackedStringArray = PackedStringArray()
	lines.append(TranslationServer.translate("BESTIAIRE_HP").format([stats.hp_max]))
	lines.append(TranslationServer.translate("BESTIAIRE_DAMAGE").format([stats.damage]))
	lines.append(TranslationServer.translate("BESTIAIRE_SPEED").format([int(stats.speed)]))
	lines.append(TranslationServer.translate("BESTIAIRE_RANGE").format([int(stats.range)]))
	lines.append(TranslationServer.translate("BESTIAIRE_PRICE").format([stats.price]))
	lines.append(TranslationServer.translate("BESTIAIRE_BUILD_TIME").format([stats.build_time]))
	return "\n".join(lines)
