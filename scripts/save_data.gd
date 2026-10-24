class_name SaveData
extends RefCounted
## Progression conservée entre les runs : pour l'instant, seulement les crédits.

const PATH := "user://save.cfg"


static func load_credits() -> int:
	var config := ConfigFile.new()
	if config.load(PATH) != OK:
		return 0
	return int(config.get_value("meta", "credits", 0))


static func add_credits(amount: int) -> int:
	var total := load_credits() + amount
	var config := ConfigFile.new()
	config.set_value("meta", "credits", total)
	config.save(PATH)
	return total
