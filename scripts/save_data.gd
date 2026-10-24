class_name SaveData
extends RefCounted
## Progression conservée entre les runs : crédits, implants, nombre de runs, issue de la dernière
## run (pour que la relique la commente au hub).

const PATH := "user://save.cfg"


static func load_credits() -> int:
	return int(_read("meta", "credits", 0))


static func add_credits(amount: int) -> int:
	var total := load_credits() + amount
	_write("meta", "credits", total)
	return total


## Retire `amount` crédits si le joueur les a. Rend false sinon, sans rien changer.
static func spend_credits(amount: int) -> bool:
	var credits := load_credits()
	if credits < amount:
		return false
	_write("meta", "credits", credits - amount)
	return true


static func implant_level(id: String) -> int:
	return int(_read("implants", id, 0))


static func set_implant_level(id: String, level: int) -> void:
	_write("implants", id, level)


## `result` : "relic" (fuite avec la relique), "loot" (fuite sans) ou "dead".
static func record_run(result: String) -> void:
	_write("meta", "runs", run_count() + 1)
	_write("meta", "last_result", result)


static func run_count() -> int:
	return int(_read("meta", "runs", 0))


static func last_result() -> String:
	return String(_read("meta", "last_result", ""))


static func clear_last_result() -> void:
	_write("meta", "last_result", "")


static func intro_seen() -> bool:
	return bool(_read("story", "intro_seen", false))


static func mark_intro_seen() -> void:
	_write("story", "intro_seen", true)


static func _read(section: String, key: String, default: Variant) -> Variant:
	var config := ConfigFile.new()
	if config.load(PATH) != OK:
		return default
	return config.get_value(section, key, default)


static func _write(section: String, key: String, value: Variant) -> void:
	var config := ConfigFile.new()
	config.load(PATH)
	config.set_value(section, key, value)
	config.save(PATH)
