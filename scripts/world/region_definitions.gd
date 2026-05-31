extends RefCounted

## Extra gold per second per site when its region is fully controlled.
const BONUS_INCOME_PER_SITE := 2
## One-time gold for the local player when they capture a full region.
const REGION_CAPTURE_GOLD_PLAYER := 60

## Maps that build regions from camp positions when no manual REGIONS entry exists.
const AUTO_REGION_MAPS: Array[int] = []

const AUTO_REGION_NAMES := {
	1: "Upper Cavern",
	2: "Crystal Depths",
	3: "Lower Grotto",
}

## map_index -> region_id -> { "sites": [camp node names in the map scene], "name": "..." }
const REGIONS := {
	1: {
		1: {
			"sites": ["camp12", "port3", "port4", "camp8"],
			"name": "Region 1"
		},
		2: {
			"sites": ["camp7", "camp6", "camp5", "camp4", "camp9", "camp", "port7", "port2"],
			"name": "Region 2"
		},
		3: {
			"sites": ["camp13", "camp11", "camp3", "camp2", "camp10", "port", "port6", "port5"],
			"name": "Region 3"
		},
	},
	2: {
		1: {
			"sites": ["camp10", "camp3", "camp4", "camp6", "camp5", "port4", "port1"],
			"name": "Northwest Region"
		},
		2: {
			"sites": ["camp11", "camp8", "camp2", "port5", "port2"],
			"name": "East Region"
		},
		3: {
			"sites": ["camp13", "camp12", "camp1", "camp7", "camp9", "port6", "port7", "port3"],
			"name": "South Region"
		},
	},
	3: {
		1: {
			"sites": ["camp10", "camp9", "camp7", "port1", "port5", "port2"],
			"name": "Upper Cavern"
		},
		2: {
			"sites": ["camp6", "camp5", "camp2", "camp1", "camp12", "camp13", "camp3", "port6", "port7"],
			"name": "Crystal Depths"
		},
		3: {
			"sites": ["camp11", "camp8", "camp4", "port4", "port3"],
			"name": "Lower Grotto"
		},
	},
}

## Massifs terrestres séparés (même région, pas de chemin à pied entre eux).
## Chaque sous-tableau = un îlot/massif distinct.
## Map 2 South : camp12, camp13 et port6 sont sur des îles séparées du continent.
const SEPARATE_LANDMASSES := {
	2: {
		3: [
			["camp1", "camp7", "camp9", "port7", "port3"],
			["camp12"],
			["camp13"],
			["port6"],
		],
	},
}


static func uses_auto_regions(map_index: int) -> bool:
	return map_index in AUTO_REGION_MAPS


static func auto_region_display_name(region_id: int) -> String:
	return AUTO_REGION_NAMES.get(region_id, "Region %s" % region_id)


static func regions_for_map(map_index: int) -> Dictionary:
	if REGIONS.has(map_index):
		return REGIONS[map_index]
	return {}


static func separate_landmass_groups_for_region(map_index: int, region_id: int) -> Array:
	if not SEPARATE_LANDMASSES.has(map_index):
		return []
	var per_region: Variant = SEPARATE_LANDMASSES[map_index]
	if per_region is Dictionary and (per_region as Dictionary).has(region_id):
		return (per_region as Dictionary)[region_id]
	return []
