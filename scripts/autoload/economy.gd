extends Node

signal gold_changed(new_amount: int)

const STARTING_GOLD := 100

var gold: int = STARTING_GOLD


func reset_for_match(starting_gold: int = STARTING_GOLD) -> void:
	gold = starting_gold
	gold_changed.emit(gold)


func add_gold(amount: int) -> void:
	gold += amount
	gold_changed.emit(gold)


func spend_gold(amount: int) -> bool:
	if gold >= amount:
		gold -= amount
		gold_changed.emit(gold)
		return true
	return false
