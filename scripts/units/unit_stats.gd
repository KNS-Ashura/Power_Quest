extends Resource
class_name UnitStats

enum UnitType {
	INFANTRY, ARCHER, HEAVY, SUPPORT, HEAL, ANTI_ARMOR, MORTAR,
	WATER_TRANSPORT, WATER_TANK, WATER_RANGE
}

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
