extends CanvasLayer

@onready var label: Label = $Label

func _ready():
	layer = 10
	_build_text()

func _build_text():
	if ServerConnection.players_data.is_empty():
		label.text = ServerConnection.get_display_player_name()
		return
	var lines: Array = []
	for p in ServerConnection.players_data:
		var name_str: String = str(p.get("username", "Joueur"))
		var side: int = int(p.get("side", -1))
		var marker: String = " ◀" if side == ServerConnection.local_side else ""
		lines.append("J%d %s%s" % [side + 1, name_str, marker])
	label.text = "\n".join(lines)
