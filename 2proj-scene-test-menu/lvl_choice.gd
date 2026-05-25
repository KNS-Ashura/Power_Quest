extends Node2D # Ou Control, selon le type de ton nœud racine

# Liste des difficultés disponibles
var difficultes: Array[String] = ["Débutant", "Avancé", "Expert"]
var index_actuel: int = 0

# Références aux nœuds (Ajuste les chemins si nécessaire)
@onready var label_ia: Label = $LVL_IA/IntituleIA # Remplace par le bon chemin vers ton Label
@onready var fleche_gauche: TextureButton = $MapChoice/FlecheGauche2 # À adapter selon le bouton pour l'IA
@onready var fleche_droite: TextureButton = $MapChoice/FlecheDroite2

func _ready() -> void:
	# Initialiser le texte au démarrage
	mettre_a_jour_affichage()

func mettre_a_jour_affichage() -> void:
	label_ia.text = difficultes[index_actuel]

# Fonction pour la flèche droite (Suivant)
func _on_fleche_droite_pressed() -> void:
	index_actuel += 1
	if index_actuel >= difficultes.size():
		index_actuel = 0 # Recommence au début (boucle)
	mettre_a_jour_affichage()

func _on_fleche_gauche_pressed() -> void:
	index_actuel -= 1
	if index_actuel < 0:
		index_actuel = difficultes.size() - 1 # Va au dernier élément (boucle)
	mettre_a_jour_affichage()
