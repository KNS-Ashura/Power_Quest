extends Resource
class_name UnitStats

enum UnitType {
	INFANTRY, ARCHER, HEAVY, SUPPORT, HEAL, ANTI_ARMOR, MORTAR,
	WATER_TRANSPORT, WATER_TANK, WATER_RANGE
}

## Touches clavier pour sélectionner toutes les unités alliées de ce type sur la carte.
## 1-7 : terrestres | 8-9-0 : maritimes
const SELECTION_HOTKEY_BY_TYPE: Dictionary = {
	UnitType.INFANTRY: KEY_1,
	UnitType.ARCHER: KEY_2,
	UnitType.HEAVY: KEY_3,
	UnitType.SUPPORT: KEY_4,
	UnitType.HEAL: KEY_5,
	UnitType.ANTI_ARMOR: KEY_6,
	UnitType.MORTAR: KEY_7,
	UnitType.WATER_TRANSPORT: KEY_8,
	UnitType.WATER_TANK: KEY_9,
	UnitType.WATER_RANGE: KEY_0,
}


static func selection_hotkey_for_type(unit_type: UnitType) -> int:
	return int(SELECTION_HOTKEY_BY_TYPE.get(unit_type, 0))


static func unit_type_from_selection_hotkey(keycode: int) -> int:
	for ut: UnitType in SELECTION_HOTKEY_BY_TYPE:
		if SELECTION_HOTKEY_BY_TYPE[ut] == keycode:
			return int(ut)
	return -1


static func is_selection_hotkey(keycode: int) -> bool:
	return unit_type_from_selection_hotkey(keycode) >= 0


@export var unit_type: UnitType = UnitType.INFANTRY
@export var name: String = "Soldier"
@export var price: int = 50
@export var hp_max: int = 100
@export var speed: float = 150.0
@export var damage: int = 10
@export var range: float = 40.0
@export var build_time: float = 5.0
@export var is_ranged: bool = false
@export var color: Color = Color(1, 1, 1)
@export var spell_cooldown: float = 0.0
@export var spell_duration: float = 0.0
@export var attack_rate: float = 1.0
