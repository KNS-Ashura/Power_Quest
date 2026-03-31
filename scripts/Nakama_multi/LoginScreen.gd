extends Node

# On définit les accès directs aux nœuds de l'interface
@onready var email_input = $Panel/VBoxContainer/LineEdit_Email
@onready var password_input = $Panel/VBoxContainer/LineEdit_Password
@onready var username_input = $Panel/VBoxContainer/LineEdit_Username
@onready var status_label = $Panel/VBoxContainer/Label_Status

func _on_button_login_pressed():
	var email = email_input.text
	var password = password_input.text
	var username = username_input.text
	
	if email.is_empty() or password.length() < 6:
		status_label.text = "Erreur : Email vide ou MDP trop court (min 6)."
		status_label.modulate = Color.RED
		return
	
	status_label.text = "Connexion..."
	status_label.modulate = Color.WHITE
	
	# Appel au gestionnaire d'authentification Autoload
	var success = await AuthManager.authenticate_player(email, password, username)
	
	if success:
		status_label.text = "Succès ! Authentifié."
		status_label.modulate = Color.GREEN
		print("Connecté avec succès !")
	else:
		status_label.text = "Échec de l'authentification."
		status_label.modulate = Color.RED
