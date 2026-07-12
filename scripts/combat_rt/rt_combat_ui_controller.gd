class_name RTCombatUIController
extends RefCounted

func apply_end_panel_style(panel: PanelContainer, title: Label, button: Button, victory: bool) -> void:
	if panel == null or title == null or button == null:
		return
	var accent := Color(0.38, 1.0, 0.64) if victory else Color(1.0, 0.34, 0.24)
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.08, 0.09, 0.115, 0.985)
	panel_style.border_width_left = 1
	panel_style.border_width_top = 1
	panel_style.border_width_right = 1
	panel_style.border_width_bottom = 1
	panel_style.border_color = accent
	panel_style.corner_radius_top_left = 8
	panel_style.corner_radius_top_right = 8
	panel_style.corner_radius_bottom_right = 8
	panel_style.corner_radius_bottom_left = 8
	panel_style.shadow_color = Color(0.0, 0.0, 0.0, 0.55)
	panel_style.shadow_size = 14
	panel.add_theme_stylebox_override("panel", panel_style)
	title.add_theme_color_override("font_color", accent)
	button.add_theme_stylebox_override("normal", _button_style(accent.darkened(0.35), accent))
	button.add_theme_stylebox_override("hover", _button_style(accent.darkened(0.22), accent.lightened(0.12)))
	button.add_theme_stylebox_override("pressed", _button_style(accent.darkened(0.48), accent))
	button.add_theme_color_override("font_color", Color(0.96, 0.98, 0.96))

func _button_style(bg_color: Color, border_color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg_color
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.border_color = border_color
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_right = 6
	style.corner_radius_bottom_left = 6
	return style
