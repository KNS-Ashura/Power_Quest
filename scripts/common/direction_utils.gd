extends RefCounted
class_name DirectionUtils


static func direction_from_vector(
	delta_vec: Vector2,
	vertical_negative: String = "b",
	vertical_positive: String = "f",
	horizontal_negative: String = "l",
	horizontal_positive: String = "r"
) -> String:
	if abs(delta_vec.y) >= abs(delta_vec.x):
		return vertical_negative if delta_vec.y < 0.0 else vertical_positive
	return horizontal_negative if delta_vec.x < 0.0 else horizontal_positive
