class_name HunterAnimator
extends RefCounted
## Pilote les animations d'un hunter importé du kit (repos, course, dash, attaque, assommé).
## Les animations ponctuelles (dash, attaque) passent avant le reste jusqu'à leur fin.

const LOOPING := [&"idle", &"run", &"stunned"]
const BLEND_TIME := 0.15
## Vitesse de course pour laquelle l'animation « run » est jouée à vitesse normale.
const RUN_REFERENCE_SPEED := 6.0

var _player: AnimationPlayer
var _locked_time := 0.0


func _init(model: Node) -> void:
	_player = model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if _player == null:
		return
	for clip: StringName in LOOPING:
		if _player.has_animation(clip):
			_player.get_animation(clip).loop_mode = Animation.LOOP_LINEAR


## À appeler à chaque image avec la vitesse au sol du hunter.
func update(delta: float, ground_speed: float, stunned := false) -> void:
	if _player == null:
		return
	_locked_time = maxf(_locked_time - delta, 0.0)
	if _locked_time > 0.0:
		return
	if stunned:
		_loop(&"stunned", 1.0)
	elif ground_speed > 0.3:
		_loop(&"run", clampf(ground_speed / RUN_REFERENCE_SPEED, 0.6, 1.5))
	else:
		_loop(&"idle", 1.0)


## Joue une animation ponctuelle jusqu'au bout.
func trigger(clip: StringName) -> void:
	if _player == null or not _player.has_animation(clip):
		return
	_player.speed_scale = 1.0
	_player.play(clip, 0.05)
	_player.seek(0.0, true)
	_locked_time = _player.get_animation(clip).length


func freeze() -> void:
	if _player != null:
		_player.pause()


func _loop(clip: StringName, speed: float) -> void:
	_player.speed_scale = speed
	if _player.current_animation != clip:
		_player.play(clip, BLEND_TIME)
