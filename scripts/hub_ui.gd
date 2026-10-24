class_name HubUi
extends CanvasLayer
## Interface du hub : crédits, consigne, boîte de dialogue de la relique, boutique d'implants.

const TEXT_COLOR := Color(0.9, 0.95, 1.0)
const HINT_COLOR := Color(1.0, 0.85, 0.3)
const RELIC_COLOR := Color(0.35, 1.0, 0.95)
const SELECTED_COLOR := Color(1.0, 0.4, 0.75)
const PANEL_COLOR := Color(0.08, 0.05, 0.18, 0.92)
## Lettres affichées par seconde : la relique « parle » au lieu d'apparaître d'un bloc.
const LETTERS_PER_SECOND := 45.0

var _credits: Label
var _hint: Label
var _dialogue: PanelContainer
var _dialogue_text: Label
var _shop: PanelContainer
var _shop_lines: VBoxContainer
var _shop_message: Label
var _typing: Tween


func _ready() -> void:
	_credits = _make_label(26, TEXT_COLOR)
	_credits.position = Vector2(24.0, 20.0)

	_hint = _make_label(26, HINT_COLOR)
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_hint.offset_left = -500.0
	_hint.offset_right = 500.0
	_hint.offset_top = -80.0
	_hint.offset_bottom = -40.0

	_build_dialogue()
	_build_shop()


func set_credits(credits: int) -> void:
	_credits.text = "Crédits : %d ¢" % credits


func set_hint(text: String) -> void:
	_hint.text = text


# --- Dialogue ---


func show_line(text: String) -> void:
	_dialogue.visible = true
	_hint.text = ""
	_dialogue_text.text = text
	_dialogue_text.visible_ratio = 0.0
	if _typing != null:
		_typing.kill()
	_typing = create_tween()
	_typing.tween_property(_dialogue_text, "visible_ratio", 1.0, text.length() / LETTERS_PER_SECOND)


func is_typing() -> bool:
	return _dialogue_text.visible_ratio < 1.0


func finish_typing() -> void:
	if _typing != null:
		_typing.kill()
	_dialogue_text.visible_ratio = 1.0


func hide_dialogue() -> void:
	_dialogue.visible = false


# --- Boutique ---


func show_shop(selected: int, message: String) -> void:
	_shop.visible = true
	_hint.text = ""
	for child in _shop_lines.get_children():
		child.queue_free()
	for i in Implants.CATALOG.size():
		var entry: Dictionary = Implants.CATALOG[i]
		var level := SaveData.implant_level(entry["id"])
		var max_level: int = (entry["costs"] as Array).size()
		var cost := Implants.next_cost(entry)
		var price := "MAX" if cost < 0 else "%d ¢" % cost
		var line := _make_label(24, SELECTED_COLOR if i == selected else TEXT_COLOR, _shop_lines)
		line.text = (
			"%s %s  [%d/%d]  %s  —  %s"
			% [
				"▶" if i == selected else "  ",
				entry["name"],
				level,
				max_level,
				entry["effect"],
				price
			]
		)
	_shop_message.text = message


func hide_shop() -> void:
	_shop.visible = false


func _build_dialogue() -> void:
	_dialogue = _make_panel()
	_dialogue.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_dialogue.offset_left = -560.0
	_dialogue.offset_right = 560.0
	_dialogue.offset_top = -230.0
	_dialogue.offset_bottom = -40.0
	var column := VBoxContainer.new()
	_dialogue.add_child(column)
	var speaker := _make_label(22, RELIC_COLOR, column)
	speaker.text = "LA RELIQUE"
	_dialogue_text = _make_label(26, TEXT_COLOR, column)
	_dialogue_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_dialogue_text.custom_minimum_size = Vector2(1060.0, 90.0)
	var next := _make_label(18, Color(TEXT_COLOR, 0.6), column)
	next.text = "E : suite"
	next.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_dialogue.visible = false


func _build_shop() -> void:
	_shop = _make_panel()
	_shop.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_shop.offset_left = -520.0
	_shop.offset_right = 520.0
	_shop.offset_top = -200.0
	_shop.offset_bottom = 200.0
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	_shop.add_child(column)
	var title := _make_label(30, RELIC_COLOR, column)
	title.text = "IMPLANTS — CLINIQUE CLANDESTINE"
	_shop_lines = VBoxContainer.new()
	column.add_child(_shop_lines)
	_shop_message = _make_label(22, HINT_COLOR, column)
	var help := _make_label(18, Color(TEXT_COLOR, 0.6), column)
	help.text = "Haut / bas : choisir   E : acheter   Espace : fermer"
	_shop.visible = false


func _make_panel() -> PanelContainer:
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = PANEL_COLOR
	style.border_color = SELECTED_COLOR
	style.set_border_width_all(3)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(18.0)
	panel.add_theme_stylebox_override("panel", style)
	add_child(panel)
	return panel


func _make_label(font_size: int, color: Color, parent: Node = null) -> Label:
	var label := Label.new()
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 6)
	(self if parent == null else parent).add_child(label)
	return label
