class_name Implants
extends RefCounted
## Implants vendus au hub. Chaque niveau acheté améliore le hunter pour toutes les runs suivantes.

const CATALOG := [
	{"id": "derme", "name": "Derme renforcé", "effect": "+1 PV max", "costs": [120, 240]},
	{"id": "myofibres", "name": "Myofibres", "effect": "+8 % de vitesse", "costs": [80, 160, 240]},
	{
		"id": "propulseurs",
		"name": "Propulseurs",
		"effect": "dash rechargé 20 % plus vite",
		"costs": [100, 200],
	},
	{"id": "servo", "name": "Servo-bras", "effect": "assomme 0,8 s de plus", "costs": [90, 180]},
]


static func bonus_health() -> int:
	return SaveData.implant_level("derme")


static func speed_factor() -> float:
	return 1.0 + 0.08 * SaveData.implant_level("myofibres")


static func dash_cooldown_factor() -> float:
	return 1.0 - 0.2 * SaveData.implant_level("propulseurs")


static func extra_stun_time() -> float:
	return 0.8 * SaveData.implant_level("servo")


## Prix du prochain niveau, ou -1 si l'implant est au maximum.
static func next_cost(entry: Dictionary) -> int:
	var level := SaveData.implant_level(entry["id"])
	var costs: Array = entry["costs"]
	return -1 if level >= costs.size() else int(costs[level])


## Achète le niveau suivant. Rend false si c'est déjà le maximum ou si les crédits manquent.
static func buy(entry: Dictionary) -> bool:
	var cost := next_cost(entry)
	if cost < 0 or not SaveData.spend_credits(cost):
		return false
	SaveData.set_implant_level(entry["id"], SaveData.implant_level(entry["id"]) + 1)
	return true
