extends Node

## Réduit la fenêtre si la taille du projet dépasse l'écran (ex. portable), puis centre.
func _ready() -> void:
	await get_tree().process_frame
	var win := get_window()
	if win == null:
		return
	if win.mode != Window.MODE_WINDOWED:
		return
	var usable := DisplayServer.screen_get_usable_rect(win.current_screen)
	var sz := win.size
	if sz.x <= usable.size.x and sz.y <= usable.size.y:
		win.position = usable.position + (usable.size - sz) / 2
		return
	var ratio := minf(float(usable.size.x) / float(sz.x), float(usable.size.y) / float(sz.y))
	win.size = Vector2i(int(sz.x * ratio), int(sz.y * ratio))
	win.position = usable.position + (usable.size - win.size) / 2
