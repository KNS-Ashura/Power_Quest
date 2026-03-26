extends Node

# Signal envoyé à chaque fois que l'argent change
signal argent_modifie(nouveau_montant)

# L'argent de départ du joueur
var argent : int = 100

func ajouter_argent(montant : int):
	argent += montant
	# On prévient tout le monde (UI, commerces, etc.)
	argent_modifie.emit(argent)

func retrancher_argent(montant : int) -> bool:
	if argent >= montant:
		argent -= montant
		argent_modifie.emit(argent)
		return true # Achat réussi
	else:
		return false # Pas assez d'argent
