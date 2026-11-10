class_name UIKit
extends RefCounted
## Shared visual language for every menu and the HUD: palette, theme, fonts,
## buttons and panels. Keeps typography/spacing/colour consistent.

const BG := Color(0.055, 0.062, 0.072, 0.94)
const PANEL := Color(0.09, 0.1, 0.115, 0.88)
const PANEL_LIGHT := Color(0.13, 0.145, 0.165, 0.92)
const LINE := Color(0.25, 0.28, 0.31)
const TEXT := Color(0.86, 0.88, 0.86)
const TEXT_DIM := Color(0.56, 0.6, 0.6)
const AMBER := Color(0.85, 0.62, 0.22)
const OLIVE := Color(0.52, 0.58, 0.38)
const BLUE := Color(0.42, 0.66, 0.95)
const RED := Color(0.9, 0.24, 0.18)
const GREEN := Color(0.4, 0.88, 0.52)

static var _theme: Theme
static var _fonts: Dictionary = {}


static func font(kind: String = "regular") -> Font:
	if _fonts.has(kind):
		return _fonts[kind]
	var fv := FontVariation.new()
	fv.base_font = ThemeDB.fallback_font
	match kind:
		"title":
			fv.variation_embolden = 0.9
			fv.spacing_glyph = 6
		"heading":
			fv.variation_embolden = 0.6
			fv.spacing_glyph = 3
		"label":
			fv.variation_embolden = 0.35
			fv.spacing_glyph = 2
		"mono":
			fv.spacing_glyph = 1
		_:
			fv.variation_embolden = 0.1
	_fonts[kind] = fv
	return fv


static func flat(c: Color, border: Color = Color(0, 0, 0, 0), bw: int = 0, radius: int = 2, pad: int = 10) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = c
	s.border_color = border
	s.set_border_width_all(bw)
	s.set_corner_radius_all(radius)
	s.content_margin_left = pad
	s.content_margin_right = pad
	s.content_margin_top = pad * 0.6
	s.content_margin_bottom = pad * 0.6
	return s


static func theme() -> Theme:
	if _theme:
		return _theme
	var t := Theme.new()
	t.default_font = font("regular")
	t.default_font_size = 20
	t.set_color("font_color", "Label", TEXT)
	# Buttons: left accent bar on hover, amber focus line.
	var normal := flat(Color(0.1, 0.11, 0.125, 0.85), LINE, 1, 2, 18)
	var hover := flat(Color(0.17, 0.16, 0.13, 0.95), AMBER, 1, 2, 18)
	hover.border_width_left = 4
	var pressed := flat(Color(0.25, 0.2, 0.12, 0.95), AMBER, 1, 2, 18)
	var disabled := flat(Color(0.08, 0.085, 0.09, 0.6), Color(0.15, 0.15, 0.15), 1, 2, 18)
	var focus := flat(Color(0, 0, 0, 0), AMBER, 2, 2, 18)
	for cls in ["Button", "OptionButton", "CheckButton"]:
		t.set_stylebox("normal", cls, normal)
		t.set_stylebox("hover", cls, hover)
		t.set_stylebox("pressed", cls, pressed)
		t.set_stylebox("disabled", cls, disabled)
		t.set_stylebox("focus", cls, focus)
		t.set_color("font_color", cls, TEXT)
		t.set_color("font_hover_color", cls, Color(1, 0.92, 0.78))
		t.set_color("font_pressed_color", cls, AMBER)
		t.set_color("font_disabled_color", cls, Color(0.4, 0.42, 0.42))
		t.set_color("font_focus_color", cls, Color(1, 0.92, 0.78))
		t.set_font("font", cls, font("label"))
	t.set_stylebox("panel", "Panel", flat(PANEL, LINE, 1, 3, 16))
	t.set_stylebox("panel", "PanelContainer", flat(PANEL, LINE, 1, 3, 16))
	t.set_stylebox("slider", "HSlider", flat(Color(0.2, 0.22, 0.24), Color(0, 0, 0, 0), 0, 2, 2))
	var grab := flat(AMBER, Color(0, 0, 0, 0), 0, 2, 2)
	t.set_stylebox("grabber_area", "HSlider", grab)
	t.set_stylebox("grabber_area_highlight", "HSlider", flat(Color(1, 0.75, 0.3), Color(0, 0, 0, 0), 0, 2, 2))
	t.set_stylebox("background", "ProgressBar", flat(Color(0.1, 0.1, 0.11, 0.85), LINE, 1, 1, 0))
	t.set_stylebox("fill", "ProgressBar", flat(AMBER, Color(0, 0, 0, 0), 0, 1, 0))
	t.set_stylebox("panel", "TabContainer", flat(PANEL, LINE, 1, 3, 16))
	t.set_stylebox("tab_selected", "TabContainer", flat(Color(0.17, 0.16, 0.13), AMBER, 0, 2, 14))
	t.set_stylebox("tab_unselected", "TabContainer", flat(Color(0.09, 0.1, 0.11), LINE, 0, 2, 14))
	t.set_stylebox("tab_hovered", "TabContainer", flat(Color(0.14, 0.14, 0.13), LINE, 0, 2, 14))
	t.set_font("font", "TabContainer", font("label"))
	t.set_color("font_selected_color", "TabContainer", AMBER)
	t.set_color("font_unselected_color", "TabContainer", TEXT_DIM)
	t.set_stylebox("normal", "LineEdit", flat(Color(0.08, 0.09, 0.1), LINE, 1, 2, 8))
	t.set_stylebox("panel", "PopupMenu", flat(Color(0.08, 0.09, 0.1, 0.98), LINE, 1, 2, 8))
	t.set_constant("separation", "VBoxContainer", 10)
	t.set_constant("separation", "HBoxContainer", 10)
	_theme = t
	return t


static func label(text: String, size: int = 20, color: Color = TEXT, kind: String = "regular") -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", font(kind))
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


static func button(text: String, callback: Callable, min_width: float = 320.0) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(min_width, 52)
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.add_theme_font_size_override("font_size", 22)
	b.pressed.connect(func():
		AudioManager.play_ui(&"ui_click")
		callback.call())
	b.mouse_entered.connect(func(): AudioManager.play_ui(&"ui_hover"))
	b.focus_entered.connect(func(): AudioManager.play_ui(&"ui_hover"))
	return b


static func panel(min_size: Vector2 = Vector2.ZERO, color: Color = PANEL) -> PanelContainer:
	var p := PanelContainer.new()
	p.custom_minimum_size = min_size
	p.add_theme_stylebox_override("panel", flat(color, LINE, 1, 3, 22))
	return p


static func accent_line(width: float = 80.0, color: Color = AMBER) -> ColorRect:
	var r := ColorRect.new()
	r.color = color
	r.custom_minimum_size = Vector2(width, 3)
	r.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	return r


static func backdrop(parent: Control, dim: float = 0.0) -> void:
	var bg := TextureRect.new()
	bg.texture = _backdrop_texture()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_SCALE
	parent.add_child(bg)
	if dim > 0.0:
		var d := ColorRect.new()
		d.color = Color(0, 0, 0, dim)
		d.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		parent.add_child(d)


static var _bg_tex: Texture2D


## Procedural tactical backdrop: dark gradient, grid, scan bands.
static func _backdrop_texture() -> Texture2D:
	if _bg_tex:
		return _bg_tex
	var w := 480
	var h := 270
	var img := Image.create(w, h, false, Image.FORMAT_RGB8)
	for y in h:
		for x in w:
			var u := float(x) / w
			var v := float(y) / h
			var c := Color(0.035, 0.042, 0.052).lerp(Color(0.07, 0.085, 0.1), (1.0 - v) * 0.6 + u * 0.2)
			var vign := clampf(1.0 - Vector2(u - 0.55, v - 0.45).length() * 1.1, 0.0, 1.0)
			c = c * (0.55 + 0.45 * vign)
			if x % 24 == 0 or y % 24 == 0:
				c = c.lerp(Color(0.16, 0.19, 0.21), 0.35)
			if (y / 3) % 2 == 0:
				c = c * 0.96
			img.set_pixel(x, y, c)
	_bg_tex = ImageTexture.create_from_image(img)
	return _bg_tex


static func format_time(t: float) -> String:
	var s := int(t)
	return "%02d:%02d" % [s / 60, s % 60]
