extends RefCounted
class_name NodeTeamUtils


static func team_id(node: Variant, default: int = -1) -> int:
	if node == null or not is_instance_valid(node):
		return default
	var value = node.get("team")
	if value == null:
		return default
	return int(value)


static func is_enemy_of(node: Variant, other_team: int) -> bool:
	var team := team_id(node)
	return team >= 0 and team != other_team


static func is_same_team(node_a: Variant, node_b: Variant) -> bool:
	var team_a := team_id(node_a)
	var team_b := team_id(node_b)
	return team_a >= 0 and team_a == team_b
