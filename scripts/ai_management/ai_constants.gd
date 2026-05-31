class_name AIConstants
extends RefCounted

const TEAM_PLAYER := 0
const TEAM_AI := 1
const TEAM_NEUTRAL := 2

const UNIT_INFANTRY := 0
const UNIT_RANGE := 1
const UNIT_HEAVY := 2
const UNIT_SUPPORT := 3
const UNIT_HEAL := 4
const UNIT_ANTI_ARMOR := 5
const UNIT_MORTAR := 6

const PORT_UNIT_TRANSPORT := 0
const PORT_UNIT_TANK := 1
const PORT_UNIT_RANGE := 2

const SQUAD_MODE_ATTACK := "attack"
const SQUAD_MODE_DEFEND := "defend"
const SQUAD_MODE_NAVAL := "naval"
const SQUAD_MODE_TRANSPORT := "transport"

const DEFEND_HOLD_RADIUS := 220.0
const HARD_GUARDIAN_UPGRADE_MAX := 3
const TRANSPORT_MIN_TRAVEL_FROM_PORT := 240.0
const TRANSPORT_DISEMBARK_NEAR_TARGET := 110.0
const SQUAD_RESPAWN_DEATH_THRESHOLD := 5

const SQUADS_SIMPLE: Array[Array] = [
	[UNIT_INFANTRY, UNIT_INFANTRY, UNIT_INFANTRY, UNIT_INFANTRY],
	[UNIT_RANGE, UNIT_RANGE, UNIT_RANGE],
	[UNIT_HEAVY, UNIT_SUPPORT],
]
const SQUADS_NORMAL: Array[Array] = [
	[UNIT_INFANTRY, UNIT_INFANTRY, UNIT_INFANTRY, UNIT_SUPPORT],
	[UNIT_RANGE, UNIT_RANGE, UNIT_HEAVY],
	[UNIT_MORTAR, UNIT_HEAL],
]
const SQUADS_HARD: Array[Array] = [
	[UNIT_INFANTRY, UNIT_INFANTRY, UNIT_INFANTRY, UNIT_INFANTRY, UNIT_SUPPORT],
	[UNIT_RANGE, UNIT_RANGE, UNIT_RANGE, UNIT_HEAVY],
	[UNIT_MORTAR, UNIT_HEAL, UNIT_ANTI_ARMOR],
	[UNIT_INFANTRY, UNIT_INFANTRY, UNIT_INFANTRY, UNIT_INFANTRY, UNIT_HEAVY, UNIT_SUPPORT],
	[UNIT_RANGE, UNIT_RANGE, UNIT_RANGE, UNIT_ANTI_ARMOR, UNIT_HEAL],
]

const DEFEND_SQUADS_SIMPLE: Array[Array] = [
	[UNIT_INFANTRY, UNIT_INFANTRY, UNIT_INFANTRY],
	[UNIT_RANGE, UNIT_RANGE, UNIT_HEAVY],
]
const DEFEND_SQUADS_NORMAL: Array[Array] = [
	[UNIT_INFANTRY, UNIT_INFANTRY, UNIT_INFANTRY, UNIT_SUPPORT],
	[UNIT_RANGE, UNIT_RANGE, UNIT_HEAVY],
]
const DEFEND_SQUADS_HARD: Array[Array] = [
	[UNIT_INFANTRY, UNIT_INFANTRY, UNIT_INFANTRY, UNIT_SUPPORT],
	[UNIT_RANGE, UNIT_RANGE, UNIT_HEAVY],
]

const PROFILE_SIMPLE := {
	"think_interval": 0.5,
	"max_parallel_squads": 1,
	"squad_cooldown": 55.0,
	"build_speed": 0.75,
	"upgrade_interval": 45.0,
	"spawn_credit_interval": 60.0,
}
const PROFILE_NORMAL := {
	"think_interval": 0.4,
	"max_parallel_squads": 2,
	"squad_cooldown": 40.0,
	"build_speed": 1.0,
	"upgrade_interval": 30.0,
	"spawn_credit_interval": 50.0,
}
const PROFILE_HARD := {
	"think_interval": 0.3,
	"max_parallel_squads": 2,
	"squad_cooldown": 25.0,
	"build_speed": 1.5,
	"upgrade_interval": 20.0,
	"spawn_credit_interval": 40.0,
}

static func profile_for_difficulty(difficulty: int) -> Dictionary:
	match difficulty:
		MapSession.AIDifficulty.SIMPLE:
			return PROFILE_SIMPLE
		MapSession.AIDifficulty.HARD:
			return PROFILE_HARD
		_:
			return PROFILE_NORMAL
