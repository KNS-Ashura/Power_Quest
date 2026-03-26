extends StaticBody2D

var hp_max : int = 500
var hp_actuels : int = hp_max

func _ready():
	add_to_group("ennemis")

func recevoir_degats(montant : int):
	hp_actuels -= montant
	print("Camp ennemi touché ! HP restants : ", hp_actuels)
	if hp_actuels <= 0:
		moteur_de_mort()

func moteur_de_mort():
	print("Le camp ennemi a été détruit !")
	queue_free()
