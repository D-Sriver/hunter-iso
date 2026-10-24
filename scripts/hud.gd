class_name Hud
extends CanvasLayer
## Interface de la run : stats, alertes, consignes contextuelles et écran de fin.

const ALERT_COLOR := Color(1.0, 0.3, 0.4)
const TEXT_COLOR := Color(0.85, 0.95, 1.0)
const HINT_COLOR := Color(1.0, 0.85, 0.3)
const CONTROLS_TEXT := (
	"ZQSD / flèches : bouger   Souris : viser   Espace : dash   J / clic : frapper"
	+ "   E : interagir   R : recommencer"
)

var _stats: Label
var _alert: Label
var _hint: Label
var _end_screen: Label
var _alert_timer := 0.0


func _ready() -> void:
	_stats = _make_label(26, TEXT_COLOR, HORIZONTAL_ALIGNMENT_LEFT)
	_place_top(_stats, 24.0)
	_alert = _make_label(34, ALERT_COLOR, HORIZONTAL_ALIGNMENT_CENTER)
	_place_top(_alert, 80.0)
	_hint = _make_label(26, HINT_COLOR, HORIZONTAL_ALIGNMENT_CENTER)
	_place_bottom(_hint, 110.0)
	var controls := _make_label(18, Color(TEXT_COLOR, 0.6), HORIZONTAL_ALIGNMENT_CENTER)
	controls.text = CONTROLS_TEXT
	_place_bottom(controls, 40.0)
	_end_screen = _make_label(40, TEXT_COLOR, HORIZONTAL_ALIGNMENT_CENTER)
	_end_screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_end_screen.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_end_screen.visible = false


func _process(delta: float) -> void:
	_alert_timer = maxf(_alert_timer - delta, 0.0)
	_alert.visible = _alert_timer > 0.0


func set_stats(health: int, max_health: int, loot: int, credits: int, carrying: bool) -> void:
	var relic_text := "   RELIQUE EN MAIN" if carrying else ""
	_stats.text = (
		"PV %d/%d   Butin : %d ¢   Crédits : %d ¢%s"
		% [health, max_health, loot, credits, relic_text]
	)


func show_alert(text: String, duration: float) -> void:
	_alert.text = text
	_alert_timer = duration


func set_hint(text: String) -> void:
	_hint.text = text


func show_end(text: String) -> void:
	_end_screen.text = text
	_end_screen.visible = true
	_hint.text = ""


func _make_label(font_size: int, color: Color, alignment: HorizontalAlignment) -> Label:
	var label := Label.new()
	label.horizontal_alignment = alignment
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 8)
	add_child(label)
	return label


func _place_top(label: Label, distance_from_top: float) -> void:
	label.anchor_left = 0.0
	label.anchor_right = 1.0
	label.anchor_top = 0.0
	label.anchor_bottom = 0.0
	label.offset_left = 24.0
	label.offset_right = -24.0
	label.offset_top = distance_from_top
	label.offset_bottom = distance_from_top + 44.0


func _place_bottom(label: Label, distance_from_bottom: float) -> void:
	label.anchor_left = 0.0
	label.anchor_right = 1.0
	label.anchor_top = 1.0
	label.anchor_bottom = 1.0
	label.offset_top = -distance_from_bottom
	label.offset_bottom = -distance_from_bottom + 40.0
