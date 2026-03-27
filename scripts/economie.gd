extends Node

signal argent_modifie(nouveau_montant)

var argent : int = 100

func ajouter_argent(montant : int):
	argent += montant
	argent_modifie.emit(argent)

func retrancher_argent(montant : int) -> bool:
	if argent >= montant:
		argent -= montant
		argent_modifie.emit(argent)
		return true
	return false
