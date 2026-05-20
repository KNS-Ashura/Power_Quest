extends RefCounted

## Extra gold per second per site when its region is fully controlled.
const BONUS_INCOME_PER_SITE := 3

## map_index -> region_id -> { "sites": [node names in Main.scn], "name": "..." }
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


static func regions_for_map(map_index: int) -> Dictionary:
	if REGIONS.has(map_index):
		return REGIONS[map_index]
	return {}
