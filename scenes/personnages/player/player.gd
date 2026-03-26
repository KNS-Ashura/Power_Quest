extends CharacterBody2D

const VITESSE = 150.0
var est_selectionne : bool = false

var hp_max : int = 100
var hp_actuels : int = hp_max

# On récupère notre nouveau GPS
@onready var agent_navigation = $NavigationAgent2D

func _ready():
	# Configuration pour un arrêt plus souple
	agent_navigation.target_desired_distance = 10.0
	agent_navigation.path_desired_distance = 10.0
	# On dit au soldat de rester sur place au début
	agent_navigation.target_position = global_position

func set_selection(etat : bool):
	est_selectionne = etat
	if est_selectionne:
		modulate = Color(0, 1, 0) # Devient vert
	else:
		modulate = Color(1, 1, 1) # Redevient normal

# Nouvelle fonction appelée par la souris
func aller_vers(cible : Vector2):
	# On donne la destination au GPS
	agent_navigation.target_position = cible

# Cette fonction gère la physique et le mouvement (elle tourne en boucle)
var dernier_regard : String = "f" # "f", "b", "l", ou "r"

func _physics_process(_delta):
	# Si on est arrivé à destination ou proche, on s'arrête
	if agent_navigation.is_navigation_finished():
		velocity = Vector2.ZERO
	else:
		# On demande au GPS le prochain petit pas à faire
		var prochain_point = agent_navigation.get_next_path_position()
		var direction = global_position.direction_to(prochain_point)
		
		# On avance dans cette direction
		velocity = direction * VITESSE
		move_and_slide()
	
	mettre_a_jour_animation()

func mettre_a_jour_animation():
	if velocity.length() > 5.0: # Petite marge pour éviter les micro-vibrations
		# On détermine la direction dominante
		if abs(velocity.x) > abs(velocity.y):
			dernier_regard = "r" if velocity.x > 0 else "l"
		else:
			dernier_regard = "f" if velocity.y > 0 else "b"
		
		$AnimatedSprite2D.play("run_" + dernier_regard)
	else:
		$AnimatedSprite2D.play("idle_" + dernier_regard)

func recevoir_degats(montant : int):
	hp_actuels -= montant
	print("Soldat touché ! HP restants : ", hp_actuels)
	if hp_actuels <= 0:
		moteur_de_mort()

func moteur_de_mort():
	print("Un soldat est mort.")
	queue_free() # On supprime le soldat de la scène
