extends Control

@onready var label_user_value: Label = $CenterContainer/PanelContainer/Margin/VBox/Header/UserInfo/UserValue
@onready var line_email: LineEdit = $CenterContainer/PanelContainer/Margin/VBox/Body/SectionEmail/EmailInput
@onready var line_current_password: LineEdit = $CenterContainer/PanelContainer/Margin/VBox/Body/SectionPassword/CurrentPasswordInput
@onready var line_new_password: LineEdit = $CenterContainer/PanelContainer/Margin/VBox/Body/SectionPassword/NewPasswordInput
@onready var line_confirm_password: LineEdit = $CenterContainer/PanelContainer/Margin/VBox/Body/SectionPassword/ConfirmPasswordInput
@onready var label_status: Label = $CenterContainer/PanelContainer/Margin/VBox/Footer/Status


func _ready() -> void:
	var user_id := ""
	if ServerConnection.session != null:
		user_id = str(ServerConnection.session.user_id)
	label_user_value.text = user_id if user_id != "" else "Non connecte"
	label_status.text = ""


func _on_back_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/Menus/main_menu_wireframe_test.tscn")


func _on_save_email_pressed() -> void:
	var email := line_email.text.strip_edges().to_lower()
	if email == "":
		label_status.text = "Entrez un email."
		return
	if not _is_valid_email(email):
		label_status.text = "Format d'email invalide."
		return

	label_status.text = "Email mis a jour (simulation)."


func _on_save_password_pressed() -> void:
	var current_password := line_current_password.text
	var new_password := line_new_password.text
	var confirm_password := line_confirm_password.text

	if current_password == "" or new_password == "" or confirm_password == "":
		label_status.text = "Remplissez tous les champs mot de passe."
		return
	if new_password.length() < 8:
		label_status.text = "Le nouveau mot de passe doit faire au moins 8 caracteres."
		return
	if new_password != confirm_password:
		label_status.text = "Le nouveau mot de passe et la confirmation ne correspondent pas."
		return

	label_status.text = "Mot de passe mis a jour (simulation)."
	line_current_password.text = ""
	line_new_password.text = ""
	line_confirm_password.text = ""


func _on_logout_pressed() -> void:
	if ServerConnection.current_match_id != "":
		await ServerConnection.leave_current_match()

	ServerConnection.clear_session_and_socket()

	label_status.text = "Deconnexion reussie."
	await get_tree().create_timer(0.2).timeout
	get_tree().change_scene_to_file("res://scene_login.tscn")


func _is_valid_email(email: String) -> bool:
	return email.contains("@") and email.contains(".")
