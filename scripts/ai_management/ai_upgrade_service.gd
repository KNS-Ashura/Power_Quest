class_name AIUpgradeService
extends RefCounted

var mgr: Node
var camps: AICampService


func _init(manager: Node, camp_service: AICampService) -> void:
	mgr = manager
	camps = camp_service


func tick_upgrades(owned: Array) -> void:
	var dt: float = float(mgr._profile.get("think_interval", 0.4))
	mgr._upgrade_timer -= dt
	if mgr._upgrade_timer > 0.0:
		return

	if mgr.current_difficulty == MapSession.AIDifficulty.HARD:
		mgr._upgrade_timer = float(mgr._profile.get("hard_upgrade_interval", 45.0))
	else:
		mgr._upgrade_timer = float(mgr._profile.get("upgrade_interval", 45.0))

	var candidates: Array = []
	for camp in owned:
		if not is_instance_valid(camp):
			continue
		if camp.has_method("can_upgrade") and camp.can_upgrade(AIConstants.TEAM_AI):
			candidates.append(camp)
	if candidates.is_empty():
		return
	var pick: Node = candidates.pick_random()
	if pick.has_method("upgrade_camp"):
		pick.upgrade_camp(false, AIConstants.TEAM_AI)


func tick_guardian_upgrades(owned: Array) -> void:
	if mgr.current_difficulty != MapSession.AIDifficulty.HARD:
		return
	if mgr._hard_guardian_upgrades_used >= AIConstants.HARD_GUARDIAN_UPGRADE_MAX:
		return
	for camp in owned:
		if mgr._hard_guardian_upgrades_used >= AIConstants.HARD_GUARDIAN_UPGRADE_MAX:
			break
		if not is_instance_valid(camp) or not camp.has_method("can_upgrade"):
			continue
		if not camp.can_upgrade(AIConstants.TEAM_AI):
			continue
		var guardian: Node2D = camps.guardian(camp as Node2D)
		if guardian == null:
			continue
		var guardian_id: int = guardian.get_instance_id()
		if mgr._guardian_low_hp_upgraded.has(guardian_id):
			continue
		if guardian.get("current_hp") == null or guardian.get("hp_max") == null:
			continue
		var current_hp: int = int(guardian.current_hp)
		var hp_max: int = int(guardian.hp_max)
		if current_hp > hp_max / 2:
			continue
		mgr._guardian_low_hp_upgraded[guardian_id] = true
		if camp.upgrade_camp(false, AIConstants.TEAM_AI):
			mgr._hard_guardian_upgrades_used += 1
