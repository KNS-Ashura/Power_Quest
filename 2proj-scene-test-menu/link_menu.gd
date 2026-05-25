extends VBoxContainer


const URL_MANUEL = "https://google.com"
const URL_GITHUB = "https://github.com/KNS-Ashura/Power_Quest.git"


const PATH_LICENCES = "https://craftpix.net/file-licenses/"
const PATH_DOC_TECH = "res://assets/utils pour proj - Copie/hud/book-green/Lettre_demission.pdf"

func _ready():
	
	$BtnLicences.pressed.connect(_on_licences_pressed)
	$BtnManuel.pressed.connect(_on_manuel_pressed)
	$BtnGithub.pressed.connect(_on_github_pressed)
	$BtnDocTech.pressed.connect(_on_doctech_pressed)



func _on_licences_pressed():

	_ouvrir_ressource(PATH_LICENCES)

func _on_manuel_pressed():

	OS.shell_open(URL_MANUEL)

func _on_github_pressed():
	
	OS.shell_open(URL_GITHUB)

func _on_doctech_pressed():
	
	_ouvrir_ressource(PATH_DOC_TECH)


func _ouvrir_ressource(chemin: String):
	if chemin.begins_with("res://"):
		
		OS.shell_open(ProjectSettings.globalize_path(chemin))
	else:
		
		OS.shell_open(chemin)
