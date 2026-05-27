extends RefCounted
class_name UnitNameUtils


static func level_from_unit_name(unit_name: String) -> int:
	var name_lower: String = unit_name.to_lower()
	if name_lower.find("iii") != -1 or name_lower.find(" 3") != -1:
		return 3
	if name_lower.find("ii") != -1 or name_lower.find(" 2") != -1:
		return 2
	return 1
