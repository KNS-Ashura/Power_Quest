extends Node2D

# Références aux nœuds de l'interface
@onready var login_email = $LoginContainer/LoginEmail
@onready var login_password = $LoginContainer/LoginPassword
@onready var register_username = $RegisterContainer/RegisterUsername
@onready var register_email = $RegisterContainer/RegisterEmail
@onready var register_password = $RegisterContainer/RegisterPassword
@onready var error_message = $RegisterContainer/ErrorMessage

# Configuration du client Nakama
var client : NakamaClient
var session : NakamaSession

func _ready():
	print("[DEBUG INIT] Lancement de la scène. Initialisation du client Nakama...")
	# Initialisation du client (identique à ton proxy VPS)
	client = Nakama.create_client("defaultkey", "api.powerquest.robinmatelot.codes", 443, "https")
	error_message.text = ""
	print("[DEBUG INIT] Client Nakama initialisé avec succès.")

# ==============================================================================
# SECTION 1 : CONNEXION (PAGE DE GAUCHE)
# ==============================================================================
func _on_btn_login_pressed():
	print("\n[DEBUG LOGIN] --- Bouton Connexion cliqué ---")
	
	var email = login_email.text.strip_edges()
	var password = login_password.text.strip_edges()
	
	print("[DEBUG LOGIN] Valeurs lues -> Email: '", email, "' | Password length: ", password.length())
	
	if email.is_empty() or password.is_empty():
		print("[DEBUG LOGIN] Échec : Un ou plusieurs champs sont vides.")
		show_error("Veuillez remplir tous les champs de connexion.")
		return
		
	error_message.text = "Connexion en cours..."
	print("[DEBUG LOGIN] Envoi de la requête d'authentification à Nakama...")
	
	# Authentification par Email via Nakama
	# create = false signifie qu'on refuse de créer un compte s'il n'existe pas
	var auth_result = await client.authenticate_email_async(email, password, "", false)
	
	print("[DEBUG LOGIN] Réponse de Nakama reçue !")
	
	if auth_result.is_exception():
		print("[DEBUG LOGIN] Nakama a renvoyé une exception.")
		var err_msg = auth_result.get_exception().message
		print("[DEBUG LOGIN] Détails complets de l'erreur : ", err_msg)
		show_error("Échec de la connexion : Email ou mot de passe incorrect.")
	else:
		print("[DEBUG LOGIN] Authentification réussie. Session récupérée.")
		session = auth_result
		show_success("Connecté avec succès !")
		_on_login_success()

# ==============================================================================
# SECTION 2 : INSCRIPTION (PAGE DE DROITE - CHECK DB AUTOMATIQUE)
# ==============================================================================
func _on_btn_register_pressed():
	print("\n[DEBUG REGISTER] --- Bouton Inscription cliqué ---")
	
	var username = register_username.text.strip_edges()
	var email = register_email.text.strip_edges()
	var password = register_password.text.strip_edges()
	
	print("[DEBUG REGISTER] Valeurs lues -> Pseudo: '", username, "' | Email: '", email, "' | Password length: ", password.length())
	
	if username.is_empty() or email.is_empty() or password.is_empty():
		print("[DEBUG REGISTER] Échec : Un ou plusieurs champs sont vides.")
		show_error("Veuillez remplir tous les champs d'inscription.")
		return
		
	if password.length() < 6:
		print("[DEBUG REGISTER] Échec : Mot de passe trop court (", password.length(), " caractères).")
		show_error("Le mot de passe doit faire au moins 6 caractères.")
		return

	error_message.text = "Création du compte..."
	print("[DEBUG REGISTER] Validation des inputs OK. Envoi de la requête de création à Nakama...")
	
	# Authentification par Email avec create = true pour forcer l'inscription
	# On passe le 'username' pour que Nakama l'enregistre
	var auth_result = await client.authenticate_email_async(email, password, username, true)
	
	print("[DEBUG REGISTER] Réponse de Nakama reçue !")
	
	if auth_result.is_exception():
		print("[DEBUG REGISTER] Nakama a renvoyé une exception.")
		var msg_err = auth_result.get_exception().message
		print("[DEBUG REGISTER] Détails complets de l'erreur : ", msg_err)
		
		# Nakama interroge directement les contraintes de ta DB PostgreSQL.
		# Si le pseudo ou l'email existent déjà, il renvoie une exception.
		if "username" in msg_err.to_lower() or "unique" in msg_err.to_lower():
			print("[DEBUG REGISTER] Analyse : Pseudo ou email déjà pris.")
			show_error("Ce pseudo ou cet email est déjà utilisé par un autre joueur.")
		else:
			print("[DEBUG REGISTER] Analyse : Erreur non identifiée.")
			show_error("Erreur lors de l'inscription. Vérifiez le format de vos saisies.")
	else:
		print("[DEBUG REGISTER] Création de compte réussie ! Session récupérée.")
		session = auth_result
		show_success("Compte créé avec succès !")
		
		# OPTIONNEL: Ici, tu peux aussi déclencher un script RPC 
		# pour ajouter une ligne synchro dans ta table custom 'players' si nécessaire
		
		_on_login_success()

# ==============================================================================
# UTILITAIRES
# ==============================================================================
func show_error(text: String):
	print("[DEBUG UI] Affichage d'une ERREUR : '", text, "'")
	error_message.add_theme_color_override("font_color", Color("#e53e3e")) # Rouge
	error_message.text = text

func show_success(text: String):
	print("[DEBUG UI] Affichage d'un SUCCÈS : '", text, "'")
	error_message.add_theme_color_override("font_color", Color("#38a169")) # Vert
	error_message.text = text

func _on_login_success():
	print("[DEBUG ROUTING] Lancement du timer (1.5s) avant changement de scène...")
	# Sauvegarder la session quelque part globalement (ex: Autoload Autoload_Nakama.session = session)
	# Puis changer de scène vers ton vrai profil utilisateur autonome !
	await get_tree().create_timer(1.5).timeout
	print("[DEBUG ROUTING] Changement de scène vers : res://scenes/menu/profil.tscn")
	get_tree().change_scene_to_file("res://scenes/menu/profil.tscn")
