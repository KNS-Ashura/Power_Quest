extends RefCounted

## Extra gold per second per site when its region is fully controlled.
const BONUS_INCOME_PER_SITE := 3

## Maps that build regions from camp positions when no manual REGIONS entry exists.
const AUTO_REGION_MAPS: Array[int] = [3]

const AUTO_REGION_NAMES := {
	1: "Upper Cavern",
	2: "Crystal Depths",
	3: "Lower Grotto",
}

## map_index -> region_id -> { "sites": [camp node names in the map scene], "name": "..." }
const REGIONS := {
	2: {
		1: {
			"sites": ["camp3", "camp4", "camp5", "camp6", "camp10", "port", "port4"],
			"name": "Northwest Region"
		},
		2: {
			"sites": ["camp1", "camp2", "camp7", "camp9", "port2", "port5"],
			"name": "East Region"
		},
		3: {
			"sites": ["camp8", "camp11", "camp12", "port6", "port7"],
			"name": "South Region"
		},
	}
}


static func uses_auto_regions(map_index: int) -> bool:
	return map_index in AUTO_REGION_MAPS


static func auto_region_display_name(region_id: int) -> String:
	return AUTO_REGION_NAMES.get(region_id, "Region %s" % region_id)


static func regions_for_map(map_index: int) -> Dictionary:
	if REGIONS.has(map_index):
		return REGIONS[map_index]
	return {}
