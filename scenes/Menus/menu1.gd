extends Control

@onready var settings_ui = $MenuSettings
@onready var leaderboard_ui = $MenuLeaderboard
@onready var close_overlay = $CloseOverlay # On récupère le bouclier

func _ready():
	settings_ui.hide()
	leaderboard_ui.hide()
	close_overlay.hide()

# Fonction pour tout fermer
func _on_close_overlay_pressed():
	settings_ui.hide()
	leaderboard_ui.hide()
	close_overlay.hide()
	print("Clic à l'extérieur : tout est fermé")

func _on_settings_button_pressed():
	settings_ui.show()
	leaderboard_ui.hide()
	close_overlay.show() # On affiche le bouclier derrière le menu

func _on_leaderboard_button_pressed():
	leaderboard_ui.show()
	settings_ui.hide()
	close_overlay.show() # On affiche le bouclier derrière le menu
