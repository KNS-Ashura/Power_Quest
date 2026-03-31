extends Control

# INSCRIPTION
@onready var ins_email = $Panel/HBoxContainer/VBoxInscription/LineEdit_Email
@onready var ins_pass = $Panel/HBoxContainer/VBoxInscription/LineEdit_Password
@onready var ins_user = $Panel/HBoxContainer/VBoxInscription/LineEdit_Username
@onready var status_label = $Panel/HBoxContainer/VBoxInscription/Label_Status

# CONNEXION
@onready var log_email = $Panel/HBoxContainer/VBoxConnexion/LineEdit_Email_Login
@onready var log_pass = $Panel/HBoxContainer/VBoxConnexion/LineEdit_Password_Login

# pour le bouton inscrire
func _on_button_register_pressed(): #lien vers le bouton s'inscrire comme une requete en gross
	_start_auth(ins_email.text, ins_pass.text, ins_user.text, true)

# pour le bouton se connecter
func _on_button_connexion_pressed(): #idem que pour s'incrire mais pr la connexion
	_start_auth(log_email.text, log_pass.text, "", false)


func _start_auth(email, password, username, create):
	if email.is_empty() or password.length() < 6:
		status_label.text = "Email vide ou MDP trop court (min 6)."
		status_label.modulate = Color.RED
		return
	
	status_label.text = "Action en cours..."
	status_label.modulate = Color.WHITE
	
	var result = await AuthManager.authenticate_player(email, password, username, create)
	
	if result.success:
		status_label.text = "Succès ! Authentifié."
		status_label.modulate = Color.GREEN
		# On attend 1 sec pour que le joueur voit le message et on change de scène
		await get_tree().create_timer(1.0).timeout
		get_tree().change_scene_to_file("res://scenes/jeu/Main.tscn")
	else:
		status_label.text = "Erreur : " + result.message
		status_label.modulate = Color.RED
